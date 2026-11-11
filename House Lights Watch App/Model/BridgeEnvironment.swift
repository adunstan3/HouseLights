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
        let client = MockBridgeClient(home: MockHome.sample(tiles: tiles),
                                      reachable: !RuntimeEnvironment.flag("mockOffline"), log: log)
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
