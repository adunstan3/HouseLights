import Foundation
import Testing
@testable import House_Lights_Watch_App

@MainActor
struct ConnectionTests {
    static func makeApp(paired: Bool, reachable: Bool = true,
                        keychain: MemoryKeychain = MemoryKeychain()) -> (AppModel, MockBridgeClient) {
        let mock = MockBridgeClient(reachable: reachable, latency: .milliseconds(5))
        let store = SharedStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let app = AppModel(environment: .mock(mock, paired: paired, store: store, keychain: keychain), store: store,
                           log: BridgeLog(fileURL: nil))
        return (app, mock)
    }

    @Test func firstLaunchWithoutKeyShowsBridgeScreen() async {
        let (app, _) = Self.makeApp(paired: false)
        await app.start()
        #expect(app.phase == .unpaired)
    }

    @Test func pairedLaunchLoadsRooms() async {
        let (app, _) = Self.makeApp(paired: true)
        await app.start()
        #expect(app.phase == .ready)
        #expect(app.rooms.count == 6)                          // rooms only
        #expect(app.rooms.allSatisfy { $0.kind == .room })
        #expect(app.store.lastKnownRooms.count == 7)           // the zone is still known (Siri, widget)
    }

    @Test func noAnswerShowsBridgeNotReachableAndTryAgainRecovers() async {
        let (app, mock) = Self.makeApp(paired: true, reachable: false)
        await app.start()
        guard case .unreachable = app.phase else { Issue.record("expected unreachable, got \(app.phase)"); return }
        await mock.setReachable(true)
        await app.reload()
        #expect(app.phase == .ready)
    }

    @Test func pairingSavesKeyAndKeepsPairedScreenUp() async throws {
        let (app, _) = Self.makeApp(paired: false)
        await app.start()
        let pairing = PairingModel(ip: nil, alreadyPaired: false)
        pairing.ip = "192.168.1.20"
        pairing.pair(app: app)
        #expect(pairing.isWaiting)
        // The mock answers "button not pressed" once, then pairs on the retry 2 s later.
        for _ in 0..<60 where pairing.state != .paired { try await Task.sleep(for: .milliseconds(100)) }
        #expect(pairing.state == .paired)
        #expect(app.credentials?.ip == "192.168.1.20")
        #expect(app.phase == .ready)
        #expect(app.showPairedConfirmation)   // Paired + Show rooms stays visible
    }

    @Test func keyWithoutPinSendsNothingAndAsksToRepair() async {
        let keychain = MemoryKeychain()
        let (app, mock) = Self.makeApp(paired: true, keychain: keychain)
        keychain.delete(.certificateHash)
        await app.start()
        #expect(app.phase == .unreachable(BridgeError.pinMissing.localizedDescription))
        #expect(app.client == nil)
        #expect(await mock.requestCount == 0)
        #expect(app.log.entries.contains { $0.kind == .error && $0.text.contains("No certificate pin") })
    }

    @Test func failedKeychainSaveFailsPairing() async throws {
        let (app, _) = Self.makeApp(paired: false, keychain: MemoryKeychain(failing: [.applicationKey]))
        await app.start()
        let pairing = PairingModel(ip: nil, alreadyPaired: false)
        pairing.ip = "192.168.1.20"
        pairing.pair(app: app)
        for _ in 0..<60 where pairing.isWaiting { try await Task.sleep(for: .milliseconds(100)) }
        guard case .failed(let why) = pairing.state else { Issue.record("expected failure, got \(pairing.state)"); return }
        #expect(why.contains("couldn't be saved"))
        #expect(app.credentials == nil)
        #expect(!app.showPairedConfirmation)
    }

    @Test func badIPIsRefusedBeforeAsking() async {
        let (app, _) = Self.makeApp(paired: false)
        let pairing = PairingModel(ip: nil, alreadyPaired: false)
        pairing.ip = "192.168"
        pairing.pair(app: app)
        guard case .failed = pairing.state else { Issue.record("expected failure"); return }
    }

    @Test func pairingErrorsAreWordedPlainly() {
        #expect(PairingModel.message(for: BridgeError.unreachable("x"), ip: "10.0.0.5").contains("No bridge answered at 10.0.0.5"))
        #expect(PairingModel.message(for: BridgeError.certificateChanged, ip: "x").contains("Re-pair"))
    }

    @Test func forgettingTheBridgeReturnsToPairing() async throws {
        let keychain = MemoryKeychain()
        let (app, _) = Self.makeApp(paired: true, keychain: keychain)
        let replies = FileManager.default.temporaryDirectory.appending(path: "replies-\(UUID()).json")
        app.bridgeRepliesURL = replies
        await app.start()
        _ = try #require(await app.saveBridgeReplies())
        #expect(app.store.bridgeIP != nil)
        app.forgetBridge()
        #expect(app.phase == .unpaired)
        #expect(app.credentials == nil)
        #expect(keychain.load(.applicationKey) == nil)
        #expect(keychain.load(.certificateHash) == nil)
        #expect(app.store.bridgeIP == nil)                   // the Bridge screen starts empty
        #expect(app.log.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: replies.path()))
    }

    @Test func pairingSavedAppOnlyIsLogged() throws {
        final class AppOnlyKeychain: SecretStore, @unchecked Sendable {
            var items: [KeychainStore.Account: Data] = [:]
            func save(_ data: Data, for account: KeychainStore.Account) -> KeychainStore.SaveResult { items[account] = data; return .appOnly }
            func load(_ account: KeychainStore.Account) -> Data? { items[account] }
            func delete(_ account: KeychainStore.Account) { items[account] = nil }
        }
        let lines = LockedLines()
        try BridgeCredentials.save(PairedBridge(ip: "10.0.0.2", applicationKey: "k", certificateHash: CredentialTests.hash),
                                   store: CredentialTests.store(), keychain: AppOnlyKeychain(),
                                   log: LogSink { _, text in lines.append(text) })
        #expect(lines.all.contains { $0.contains("widget and Siri can't read it") })
    }
}

@MainActor
struct NoticeTests {
    @Test func refusedChangesShowANoticeAndKeepTheGrid() async {
        let (app, _) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.fail(BridgeError.http(400, "invalid value"))
        #expect(app.phase == .ready)
        #expect(app.notice == "The bridge didn’t accept that change.")
        app.fail(BridgeError.unreachable("timed out"))
        guard case .unreachable = app.phase else { Issue.record("expected Bridge not reachable"); return }
    }
}

@MainActor
struct RoomsOnlyTests {
    @Test func gridShowsRoomsButNotZones() async {
        let (app, _) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.saveOrder(["mock-zone-0", "mock-room-3"])          // an old order that still lists the zone
        #expect(app.rooms.first?.id == "mock-room-3")
        #expect(!app.rooms.contains { $0.kind == .zone })
        #expect(app.home.room("mock-zone-0") != nil)            // still known for Siri and the widget
    }
}
