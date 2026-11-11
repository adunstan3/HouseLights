import Foundation
import Testing
@testable import House_Lights_Watch_App

@MainActor
struct ConnectionTests {
    static func makeApp(paired: Bool, reachable: Bool = true) -> (AppModel, MockBridgeClient) {
        let mock = MockBridgeClient(reachable: reachable, latency: .milliseconds(5))
        let store = SharedStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let app = AppModel(environment: .mock(mock, paired: paired, store: store), store: store, log: BridgeLog(fileURL: nil))
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

    @Test func forgettingTheBridgeReturnsToPairing() async {
        let (app, _) = Self.makeApp(paired: true)
        await app.start()
        app.forgetBridge()
        #expect(app.phase == .unpaired)
        #expect(app.credentials == nil)
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
