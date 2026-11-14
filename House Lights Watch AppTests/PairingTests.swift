import Foundation
import Testing
@testable import House_Lights_Watch_App

struct PairingTests {
    /// A bridge whose button is "pressed" after `pressAfter` attempts.
    actor FakeBridge: BridgeClient {
        var attempts = 0
        let pressAfter: Int
        let failWith: BridgeError?
        init(pressAfter: Int, failWith: BridgeError? = nil) { self.pressAfter = pressAfter; self.failWith = failWith }

        func pair(ip: String) async throws -> PairingAttempt {
            attempts += 1
            if let failWith { throw failWith }
            return attempts > pressAfter ? .paired(PairedBridge(ip: ip, applicationKey: "k", certificateHash: nil)) : .linkButtonNotPressed
        }
        func fetchHome() async throws -> HomeSnapshot { .empty }
        func send(_ command: GroupedLightCommand, toGroupedLight id: String) async throws {}
        func createScene(name: String, roomID: String, actions: [HueSceneAction], motion: SceneMotion?) async throws -> String { "" }
        func updateScene(id: String, actions: [HueSceneAction], motion: SceneMotion?) async throws {}
        func recallScene(id: String, brightness: Double?, dynamic: Bool) async throws {}
        nonisolated func events() -> AsyncThrowingStream<[HueEvent], any Error> { AsyncThrowingStream { $0.finish() } }
    }

    @Test func retriesUntilTheButtonIsPressed() async throws {
        let bridge = FakeBridge(pressAfter: 3)
        let outcome = try await Pairing.run(client: bridge, ip: "10.0.0.2", sleep: { _ in })
        #expect(outcome == .paired(PairedBridge(ip: "10.0.0.2", applicationKey: "k", certificateHash: nil)))
        #expect(await bridge.attempts == 4)
    }

    @Test func givesUpAfterThirtySeconds() async throws {
        let bridge = FakeBridge(pressAfter: 100)
        let outcome = try await Pairing.run(client: bridge, ip: "10.0.0.2", sleep: { _ in })
        #expect(outcome == .timedOut)
        #expect(await bridge.attempts == 16)   // at 0, 2, 4 … 30 s
    }

    @Test func stopsAtOnceWhenNoBridgeAnswers() async {
        let bridge = FakeBridge(pressAfter: 0, failWith: .unreachable("no answer"))
        await #expect(throws: BridgeError.unreachable("no answer")) {
            try await Pairing.run(client: bridge, ip: "10.0.0.9", sleep: { _ in })
        }
        #expect(await bridge.attempts == 1)
    }

    @Test func decodesPairingReplies() throws {
        let ok = try JSONDecoder().decode([HuePairingReply].self, from: Data(#"[{"success":{"username":"abc","clientkey":"DEF"}}]"#.utf8))
        #expect(ok.first?.success?.username == "abc")
        let wait = try JSONDecoder().decode([HuePairingReply].self, from: Data(#"[{"error":{"type":101,"address":"","description":"link button not pressed"}}]"#.utf8))
        #expect(wait.first?.error?.type == 101)
    }

    @Test func validatesIPAddresses() {
        #expect(Pairing.isValidIP("192.168.1.23"))
        #expect(!Pairing.isValidIP("192.168.1"))
        #expect(!Pairing.isValidIP("192.168.1.256"))
        #expect(!Pairing.isValidIP("192.168.01.2"))
        #expect(!Pairing.isValidIP("hue.local"))
    }

    @Test func certificatePinning() {
        let a = Data(repeating: 1, count: 32), b = Data(repeating: 2, count: 32)
        #expect(BridgeTrust.decide(.pairing, presented: a) == .accept)       // only while pairing
        #expect(BridgeTrust.decide(.pinned(a), presented: a) == .accept)
        #expect(BridgeTrust.decide(.pinned(a), presented: b) == .reject)     // mismatched pin refuses
        #expect(BridgeTrust.decide(.pinned(Data()), presented: a) == .reject) // an empty pin never accepts
    }
}

/// The key and its certificate pin are saved together or not at all, and a key without a
/// pin never makes a client.
struct CredentialTests {
    static let hash = Data(repeating: 9, count: 32)
    static func store() -> SharedStore { SharedStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!) }

    @Test func savedPairingLoadsWithItsPin() throws {
        let store = Self.store(), keychain = MemoryKeychain()
        try BridgeCredentials.save(PairedBridge(ip: "10.0.0.2", applicationKey: "k", certificateHash: Self.hash),
                                   store: store, keychain: keychain)
        #expect(BridgeCredentials.loadSaved(store: store, keychain: keychain)
                == .paired(BridgeCredentials(ip: "10.0.0.2", applicationKey: "k", certificateHash: Self.hash)))
    }

    @Test func keyWithoutPinNeedsRepair() {
        let store = Self.store(), keychain = MemoryKeychain()
        store.bridgeIP = "10.0.0.2"
        _ = keychain.save(Data("k".utf8), for: .applicationKey)
        #expect(BridgeCredentials.loadSaved(store: store, keychain: keychain) == .missingPin(ip: "10.0.0.2"))
        _ = keychain.save(Data([1, 2, 3]), for: .certificateHash)   // not a SHA-256 hash
        #expect(BridgeCredentials.loadSaved(store: store, keychain: keychain) == .missingPin(ip: "10.0.0.2"))
    }

    @Test func pairingWithoutACertificateIsNotSaved() {
        let store = Self.store(), keychain = MemoryKeychain()
        #expect(throws: BridgeError.self) {
            try BridgeCredentials.save(PairedBridge(ip: "10.0.0.2", applicationKey: "k", certificateHash: nil),
                                       store: store, keychain: keychain)
        }
        #expect(keychain.load(.applicationKey) == nil)
        #expect(BridgeCredentials.loadSaved(store: store, keychain: keychain) == .none)
    }

    @Test func failedPinSaveKeepsNothing() {
        let store = Self.store(), keychain = MemoryKeychain(failing: [.certificateHash])
        #expect(throws: BridgeError.self) {
            try BridgeCredentials.save(PairedBridge(ip: "10.0.0.2", applicationKey: "k", certificateHash: Self.hash),
                                       store: store, keychain: keychain)
        }
        #expect(keychain.load(.applicationKey) == nil)   // no half-saved key
        #expect(store.bridgeIP == nil)
    }
}
