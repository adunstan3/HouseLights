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

    /// Creates a scene in a room; returns its id.
    func createScene(name: String, roomID: String, actions: [HueSceneAction]) async throws -> String
    func updateScene(id: String, actions: [HueSceneAction]) async throws
    /// Recalls a scene, optionally at a given brightness instead of the scene's own.
    func recallScene(id: String, brightness: Double?) async throws

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
    /// Default: read everything (mock and test bridges).
    func fetchStates() async throws -> LiveStates {
        let home = try await fetchHome()
        var groups: [String: LiveStates.Group] = [:]
        for room in home.rooms { groups[room.groupedLightID] = .init(on: room.isOn, brightness: room.brightness) }
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
    var certificateHash: Data?
}

/// What a client needs to talk to a paired bridge.
nonisolated struct BridgeCredentials: Sendable, Equatable {
    var ip: String
    var applicationKey: String
    var certificateHash: Data?

    /// Saved credentials, or nil if not paired yet.
    static func load(store: SharedStore = SharedStore()) -> BridgeCredentials? {
        guard let ip = store.bridgeIP, let key = KeychainStore.loadString(.applicationKey) else { return nil }
        return BridgeCredentials(ip: ip, applicationKey: key, certificateHash: KeychainStore.load(.certificateHash))
    }

    static func save(_ paired: PairedBridge, store: SharedStore = SharedStore()) {
        store.bridgeIP = paired.ip
        KeychainStore.saveString(paired.applicationKey, for: .applicationKey)
        if let hash = paired.certificateHash { KeychainStore.save(hash, for: .certificateHash) }
        else { KeychainStore.delete(.certificateHash) }
    }

    static func forget() {
        KeychainStore.delete(.applicationKey)
        KeychainStore.delete(.certificateHash)
    }
}
