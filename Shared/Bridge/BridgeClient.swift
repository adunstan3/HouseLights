import Foundation

/// Where the app talks to the bridge. `HueBridgeClient` is the real one; `MockBridgeClient`
/// stands in on the simulator, which can't reach the bridge.
nonisolated protocol BridgeClient: Sendable {
    /// One POST /api attempt. Returns `.linkButtonNotPressed` until the bridge's button is pressed.
    func pair(ip: String) async throws -> PairingAttempt

    /// Reads rooms, zones, grouped lights, lights and scenes.
    func fetchHome() async throws -> HomeSnapshot

    /// PUT to a room's (or the all-lights) grouped_light.
    func send(_ command: GroupedLightCommand, toGroupedLight id: String) async throws

    /// Creates a scene in a room; returns its id. `motion` makes it a hybrid (palette, and
    /// whether it starts moving when recalled).
    func createScene(name: String, roomID: String, actions: [HueSceneAction], motion: SceneMotion?) async throws -> String
    func updateScene(id: String, actions: [HueSceneAction], motion: SceneMotion?) async throws
    /// Recalls a scene, optionally at a given brightness instead of the scene's own.
    /// `dynamic` starts its palette moving ("dynamic_palette") instead of a still recall.
    func recallScene(id: String, brightness: Double?, dynamic: Bool) async throws

    /// DELETE a scene (only ever one of ours: "House Lights…").
    func deleteScene(id: String) async throws

    /// One resource list exactly as the bridge sent it (`light`, `scene`, …), for
    /// Log › Save bridge replies.
    func rawResource(_ name: String) async throws -> Data

    /// The live event stream. It ends (or throws) when the connection drops; callers reconnect.
    func events() -> AsyncThrowingStream<[HueEvent], any Error>

    /// The lights' current state only (on, brightness, color), read quietly and often while
    /// the app is open, as a backup to the event stream.
    func fetchStates() async throws -> LiveStates
}

/// On/off and brightness per grouped light, and every light's state.
nonisolated struct LiveStates: Sendable, Equatable {
    struct Group: Sendable, Equatable { var on: Bool; var brightness: Double? }
    var groups: [String: Group]
    var lights: [String: LightState]
}

extension BridgeClient {
    func createScene(name: String, roomID: String, actions: [HueSceneAction]) async throws -> String {
        try await createScene(name: name, roomID: roomID, actions: actions, motion: nil)
    }
    func updateScene(id: String, actions: [HueSceneAction]) async throws {
        try await updateScene(id: id, actions: actions, motion: nil)
    }
    func recallScene(id: String, brightness: Double?) async throws {
        try await recallScene(id: id, brightness: brightness, dynamic: false)
    }

    /// Defaults for test bridges.
    func deleteScene(id: String) async throws { throw BridgeError.http(501, "not supported") }
    func rawResource(_ name: String) async throws -> Data { Data("{}".utf8) }

    /// Default: read everything (mock and test bridges).
    func fetchStates() async throws -> LiveStates {
        let home = try await fetchHome()
        var groups: [String: LiveStates.Group] = [:]
        // Like the bridge, an off group reports brightness 0.
        for room in home.rooms { groups[room.groupedLightID] = .init(on: room.isOn, brightness: room.isOn ? room.brightness : 0) }
        return LiveStates(groups: groups, lights: home.lights)
    }
}

nonisolated enum PairingAttempt: Sendable, Equatable {
    case paired(PairedBridge)
    case linkButtonNotPressed
}

/// What pairing gives us: the application key and the certificate we'll pin from now on.
nonisolated struct PairedBridge: Sendable, Equatable {
    var ip: String
    var applicationKey: String
    /// SHA-256 of the certificate seen while pairing. Saving refuses a pairing without it.
    var certificateHash: Data?
}

/// What a client needs to talk to a paired bridge. The certificate hash is required: a
/// client never runs without a pin (see BridgeTrust).
nonisolated struct BridgeCredentials: Sendable, Equatable {
    var ip: String
    var applicationKey: String
    var certificateHash: Data

    /// What's saved on the watch.
    enum Saved: Sendable, Equatable {
        /// Not paired yet (or forgotten).
        case none
        /// A key is saved but its certificate pin isn't: nothing may be sent until re-paired.
        case missingPin(ip: String)
        case paired(BridgeCredentials)
    }

    /// A SHA-256 hash is 32 bytes; anything else isn't a usable pin.
    static func isUsablePin(_ hash: Data?) -> Bool { hash?.count == 32 }

    /// What's saved: the app, the widget and Siri all start here.
    static func loadSaved(store: SharedStore = SharedStore(), keychain: any SecretStore = SystemKeychain()) -> Saved {
        guard let ip = store.bridgeIP, let keyData = keychain.load(.applicationKey),
              let key = String(data: keyData, encoding: .utf8), !key.isEmpty else { return .none }
        guard let hash = keychain.load(.certificateHash), isUsablePin(hash) else { return .missingPin(ip: ip) }
        return .paired(BridgeCredentials(ip: ip, applicationKey: key, certificateHash: hash))
    }

    /// Saves a pairing: the key and the certificate pin, both or neither. Throws (and leaves
    /// nothing half-saved) if no certificate was captured or either Keychain save fails.
    @discardableResult
    static func save(_ paired: PairedBridge, store: SharedStore = SharedStore(),
                     keychain: any SecretStore = SystemKeychain(), log: LogSink = .none) throws -> BridgeCredentials {
        guard let hash = paired.certificateHash, isUsablePin(hash) else {
            log(.error, "Pairing: no certificate was captured from the bridge, so the key wasn't saved")
            throw BridgeError.notSaved("the bridge's certificate wasn't seen")
        }
        let results = [keychain.save(Data(paired.applicationKey.utf8), for: .applicationKey),
                       keychain.save(hash, for: .certificateHash)]
        if let failure = results.first(where: { !$0.succeeded }), case .failed(let status) = failure {
            forget(keychain: keychain)
            log(.error, "Pairing: Keychain save failed (\(status)); nothing kept")
            throw BridgeError.notSaved("Keychain error \(status)")
        }
        store.bridgeIP = paired.ip
        return BridgeCredentials(ip: paired.ip, applicationKey: paired.applicationKey, certificateHash: hash)
    }

    static func forget(keychain: any SecretStore = SystemKeychain()) {
        keychain.delete(.applicationKey)
        keychain.delete(.certificateHash)
    }
}
