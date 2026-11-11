import Foundation

/// The real bridge client: Hue CLIP API v2 over HTTPS on the local network.
/// Every request is authenticated with the `hue-application-key` header and logged.
nonisolated final class HueBridgeClient: BridgeClient {
    let ip: String
    private let key: String?
    private let trust: BridgeTrust
    private let session: URLSession
    private let streamSession: URLSession
    private let log: LogSink

    init(ip: String, applicationKey: String?, pinnedCertificate: Data?, log: LogSink) {
        self.ip = ip
        self.key = applicationKey
        self.log = log
        trust = BridgeTrust(host: ip, pinnedHash: pinnedCertificate, log: log)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: trust, delegateQueue: nil)

        // The event stream is long-lived; this timeout is how long it may sit idle.
        let streamConfig = URLSessionConfiguration.ephemeral
        streamConfig.timeoutIntervalForRequest = 15 * 60
        streamConfig.waitsForConnectivity = false
        streamSession = URLSession(configuration: streamConfig, delegate: trust, delegateQueue: nil)
    }

    convenience init(credentials: BridgeCredentials, log: LogSink) {
        self.init(ip: credentials.ip, applicationKey: credentials.applicationKey,
                  pinnedCertificate: credentials.certificateHash, log: log)
    }

    deinit {
        session.invalidateAndCancel()
        streamSession.invalidateAndCancel()
    }

    // MARK: Pairing

    func pair(ip: String) async throws -> PairingAttempt {
        // POST /api is the v1 endpoint, but it's also how v2 apps get their key.
        // `generateclientkey` asks for the v2-style key (plus a streaming client key we don't use).
        let body = try JSONSerialization.data(withJSONObject: ["devicetype": "house_lights#watch", "generateclientkey": true])
        let data = try await perform("POST", "/api", body: body, authenticated: false)
        let replies = try decode([HuePairingReply].self, data)
        if let success = replies.first(where: { $0.success != nil })?.success {
            log(.info, "Paired: got application key")
            return .paired(PairedBridge(ip: ip, applicationKey: success.username, certificateHash: trust.presentedHash))
        }
        if let error = replies.first(where: { $0.error != nil })?.error {
            if error.type == 101 { return .linkButtonNotPressed }
            throw BridgeError.http(error.type, error.description)
        }
        throw BridgeError.badResponse("empty pairing reply")
    }

    // MARK: Reading

    func fetchHome() async throws -> HomeSnapshot {
        async let rooms = resources(HueGroupDTO.self, "room")
        async let zones = resources(HueGroupDTO.self, "zone")
        async let groups = resources(HueGroupedLightDTO.self, "grouped_light")
        async let lights = resources(HueLightDTO.self, "light")
        async let scenes = resources(HueSceneDTO.self, "scene")
        return try await HomeSnapshot(rooms: rooms, zones: zones, groupedLights: groups, lights: lights, scenes: scenes)
    }

    private func resources<T: Decodable & Sendable>(_ type: T.Type, _ name: String) async throws -> [T] {
        let data = try await perform("GET", "/clip/v2/resource/\(name)")
        return try decode(HueResponse<T>.self, data).data
    }

    // MARK: Commands

    func send(_ command: GroupedLightCommand, toGroupedLight id: String) async throws {
        _ = try await perform("PUT", "/clip/v2/resource/grouped_light/\(id)", body: try JSONEncoder().encode(command),
                              note: command.summary)
    }

    func createScene(name: String, roomID: String, actions: [HueSceneAction]) async throws -> String {
        let body = SceneCreate(metadata: HueMetadata(name: name), group: HueRef(rid: roomID, rtype: "room"), actions: actions)
        let data = try await perform("POST", "/clip/v2/resource/scene", body: try JSONEncoder().encode(body), note: name)
        guard let id = try decode(HueResponse<HueRef>.self, data).data.first?.rid else {
            throw BridgeError.badResponse("no scene id")
        }
        return id
    }

    func updateScene(id: String, actions: [HueSceneAction]) async throws {
        _ = try await perform("PUT", "/clip/v2/resource/scene/\(id)", body: try JSONEncoder().encode(["actions": actions]))
    }

    func recallScene(id: String, brightness: Double?) async throws {
        // `recall.dimming` overrides the scene's stored brightness for every light.
        let recall = SceneRecall(recall: .init(action: "active", dimming: brightness.map { HueDimming(brightness: min(max($0, 1), 100)) }))
        _ = try await perform("PUT", "/clip/v2/resource/scene/\(id)", body: try JSONEncoder().encode(recall),
                              note: brightness.map { "recall at \(Int($0))%" } ?? "recall")
    }

    private struct SceneCreate: Encodable {
        var type = "scene"
        var metadata: HueMetadata
        var group: HueRef
        var actions: [HueSceneAction]
    }

    private struct SceneRecall: Encodable {
        struct Recall: Encodable { var action: String; var dimming: HueDimming? }
        var recall: Recall
    }

    // MARK: Event stream

    func events() -> AsyncThrowingStream<[HueEvent], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [streamSession, log] in
                do {
                    var request = try makeRequest("GET", "/eventstream/clip/v2")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    log(.request, "GET /eventstream/clip/v2")
                    let (bytes, response) = try await streamSession.bytes(for: request)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    log(.response, "\(code) event stream")
                    try check(code, Data())
                    var parser = EventStreamParser()
                    for try await byte in bytes {
                        guard let message = parser.feed(byte) else { continue }
                        do {
                            continuation.yield(try EventStreamParser.decode(message))
                        } catch {
                            log(.error, "Event stream: couldn't decode an event (\(error))")
                        }
                    }
                    log(.info, "Event stream closed by bridge")
                    continuation.finish()
                } catch {
                    let mapped = self.map(error)
                    if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                        log(.error, "Event stream: \(mapped.localizedDescription)")
                    }
                    continuation.finish(throwing: mapped)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Plumbing

    private func makeRequest(_ method: String, _ path: String, authenticated: Bool = true) throws -> URLRequest {
        guard let url = URL(string: "https://\(ip)\(path)") else { throw BridgeError.badResponse("bad IP \(ip)") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if authenticated {
            guard let key else { throw BridgeError.notPaired }
            request.setValue(key, forHTTPHeaderField: "hue-application-key")
        }
        return request
    }

    private func perform(_ method: String, _ path: String, body: Data? = nil, authenticated: Bool = true,
                         note: String? = nil) async throws -> Data {
        var request = try makeRequest(method, path, authenticated: authenticated)
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        log(.request, "\(method) \(path)\(note.map { " — \($0)" } ?? "")")
        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            log(.response, "\(code) \(method) \(path) (\(ms) ms)")
            try check(code, data)
            return data
        } catch {
            let mapped = map(error)
            log(.error, "\(method) \(path): \(mapped.localizedDescription)")
            throw mapped
        }
    }

    /// Maps HTTP codes to errors and logs any v2 `errors` the bridge included.
    private func check(_ code: Int, _ data: Data) throws {
        let messages = (try? JSONDecoder().decode(HueResponse<HueRef>.self, from: data))?.errors.map(\.description) ?? []
        if !messages.isEmpty { log(.error, "Bridge says: \(messages.joined(separator: "; "))") }
        switch code {
        case 200..<300: return
        case 401, 403: throw BridgeError.unauthorized
        case 429: throw BridgeError.rateLimited
        default: throw BridgeError.http(code, messages.first ?? "")
        }
    }

    private func map(_ error: any Error) -> BridgeError {
        if let e = error as? BridgeError { return e }
        if trust.sawMismatch { return .certificateChanged }
        if let e = error as? URLError {
            switch e.code {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .secureConnectionFailed:
                return .unreachable("secure connection failed")
            case .timedOut: return .unreachable("timed out")
            case .notConnectedToInternet, .networkConnectionLost: return .unreachable("no network")
            case .cannotConnectToHost, .cannotFindHost: return .unreachable("no answer at \(ip)")
            case .cancelled: return .unreachable("cancelled")
            default: return .unreachable(e.localizedDescription)
            }
        }
        if error is DecodingError { return .badResponse("couldn't read the reply") }
        return .unreachable(error.localizedDescription)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            log(.error, "Decode \(T.self): \(error)")
            throw BridgeError.badResponse("couldn't read \(T.self)")
        }
    }
}
