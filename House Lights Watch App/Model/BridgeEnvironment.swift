import Foundation

/// How the app gets bridge clients and stores credentials: the real Hue bridge, or the mock.
struct BridgeEnvironment {
    var isMock: Bool
    var loadCredentials: () -> BridgeCredentials?
    var saveCredentials: (PairedBridge) -> Void
    var forgetCredentials: () -> Void
    /// A client for a paired bridge.
    var makeClient: (BridgeCredentials, LogSink) -> any BridgeClient
    /// A client for pairing with the bridge at an IP (no key, no pinned certificate yet).
    var makePairingClient: (String, LogSink) -> any BridgeClient

    static func live(store: SharedStore = SharedStore()) -> BridgeEnvironment {
        BridgeEnvironment(
            isMock: false,
            loadCredentials: { BridgeCredentials.load(store: store) },
            saveCredentials: { BridgeCredentials.save($0, store: store) },
            forgetCredentials: { BridgeCredentials.forget() },
            makeClient: { HueBridgeClient(credentials: $0, log: $1) },
            makePairingClient: { HueBridgeClient(ip: $0, applicationKey: nil, pinnedCertificate: nil, log: $1) })
    }

    /// One mock bridge for the whole run, so its state carries across clients.
    static func mock(_ client: MockBridgeClient, paired: Bool, store: SharedStore = SharedStore()) -> BridgeEnvironment {
        final class Box { var credentials: BridgeCredentials? }
        let box = Box()
        if paired { box.credentials = BridgeCredentials(ip: "192.168.1.2", applicationKey: "mock-application-key", certificateHash: nil) }
        return BridgeEnvironment(
            isMock: true,
            loadCredentials: { box.credentials },
            saveCredentials: { p in
                store.bridgeIP = p.ip
                box.credentials = BridgeCredentials(ip: p.ip, applicationKey: p.applicationKey, certificateHash: p.certificateHash)
            },
            forgetCredentials: { box.credentials = nil },
            makeClient: { _, _ in client },
            makePairingClient: { _, _ in client })
    }

    /// The environment for this launch (see RuntimeEnvironment for the debug arguments).
    static func current(log: LogSink, store: SharedStore) -> BridgeEnvironment {
        guard RuntimeEnvironment.usesMockBridge else { return .live(store: store) }
        let tiles = RuntimeEnvironment.debugValue("mockTiles").flatMap(Int.init) ?? 6
        var home = MockHome.sample(tiles: tiles)
        if RuntimeEnvironment.flag("mockHybrid") {
            // The living room shows a moving red-and-blue hybrid (and those swatches are saved).
            let red = WheelColor(hue: 0, saturation: 1), blue = WheelColor(hue: 0.62, saturation: 0.85)
            store.savedSwatches = [red, WheelColor(hue: 0.08, saturation: 0.9), blue, WheelColor(hue: 0.33, saturation: 0.8)]
                .map { SavedSwatch(hue: $0.hue, saturation: $0.saturation) }
            store.hybrids = ["mock-room-0": Hybrid(colors: [red, blue], moving: true)]
            store.temporaryRooms = ["mock-room-0": .xy(red.xy(in: .c))]
            home.lights["mock-light-0-a"]?.color = .xy(red.xy(in: .c))
            home.lights["mock-light-0-b"]?.color = .xy(blue.xy(in: .c))
            home.lights["mock-light-0-a"]?.isDynamic = true
            home.lights["mock-light-0-b"]?.isDynamic = true
            if let i = home.rooms.firstIndex(where: { $0.id == "mock-room-0" }) {
                HomeSnapshot.derive(&home.rooms[i], from: home.lights(in: home.rooms[i]))
            }
        }
        let client = MockBridgeClient(home: home, reachable: !RuntimeEnvironment.flag("mockOffline"), log: log)
        if RuntimeEnvironment.flag("mockTemporary") {
            // The living room shows 2200 K while its default is 2700 K.
            store.temporaryRooms = ["mock-room-0": .temperature(mirek: 454)]
        }
        if RuntimeEnvironment.flag("mockFreeLayout") {
            // Gaps and half-way spots, as Arrange allows.
            store.gridArrangement = GridArrangement(columns: 3, slots: [
                "mock-room-0": Slot(row: 0, half: 1), "mock-room-1": Slot(row: 0, half: 4),
                "mock-room-2": Slot(row: 1, half: 0), "mock-room-3": Slot(row: 1, half: 3),
                "mock-room-4": Slot(row: 2, half: 0), "mock-room-5": Slot(row: 2, half: 4)])
        }
        if RuntimeEnvironment.flag("mockSwatches") {
            store.savedSwatches = [(0.0, 1.0), (0.08, 0.9), (0.15, 0.75), (0.33, 0.8), (0.5, 0.6), (0.62, 0.85), (0.8, 0.7), (0.92, 0.5), (0.1, 0.35)]
                .map { SavedSwatch(hue: $0.0, saturation: $0.1) }
        }
        if RuntimeEnvironment.flag("mockOutsideChanges") {
            Task {
                while true {
                    try? await Task.sleep(for: .seconds(15))
                    await client.simulateOutsideChange()
                }
            }
        }
        return .mock(client, paired: !RuntimeEnvironment.flag("unpaired"), store: store)
    }
}
