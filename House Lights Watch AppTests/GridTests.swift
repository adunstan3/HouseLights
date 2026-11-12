import CoreGraphics
import Foundation
import Testing
@testable import House_Lights_Watch_App

struct GridLayoutTests {
    @Test func gridSizesFollowTheSpec() {
        for n in 1...4 { #expect(GridLayout.make(count: n, width: 190, height: 170).columns == 2) }
        for n in 5...9 { #expect(GridLayout.make(count: n, width: 190, height: 170).columns == 3) }
        for n in [10, 15, 30] {
            let l = GridLayout.make(count: n, width: 190, height: 170)
            #expect(l.columns == 3)   // never four across
            #expect(l.scrolls)
        }
        #expect(!GridLayout.make(count: 9, width: 190, height: 170).scrolls)
    }

    @Test func tilesFitTheSpace() {
        let l = GridLayout.make(count: 9, width: 190, height: 170)
        #expect(l.gridWidth <= 190)
        #expect(l.tile * 3 + l.spacing * 2 <= 170)
        #expect(l.tile >= 44)   // tap target
        let big = GridLayout.make(count: 4, width: 190, height: 170)
        #expect(big.tile > l.tile)
    }

    @Test func slotFrames() {
        let l = GridLayout(columns: 3, tile: 50, spacing: 6, scrolls: false)
        #expect(l.frame(of: 0) == CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(l.frame(of: 4) == CGRect(x: 56, y: 56, width: 50, height: 50))
    }
}

struct CrownBrightnessTests {
    func room(_ id: String, on: Bool, _ b: Double, kind: RoomKind = .room) -> Room {
        Room(id: id, kind: kind, name: id, archetype: "other", groupedLightID: "g-\(id)", lightIDs: [], isOn: on, brightness: b)
    }

    @Test func addsTheSameStepToEveryRoomThatIsOn() {
        let c = CrownBrightness.apply(steps: 1, to: [room("a", on: true, 70), room("b", on: true, 40), room("c", on: false, 50)])
        #expect(c == ["a": .brightness(75), "b": .brightness(45)])
    }

    @Test func stopsAtOneHundredAndTurnsOffAtZero() {
        #expect(CrownBrightness.apply(steps: 1, to: [room("a", on: true, 98)]) == ["a": .brightness(100)])
        #expect(CrownBrightness.apply(steps: -1, to: [room("a", on: true, 5)]) == ["a": .off])
        #expect(CrownBrightness.apply(steps: -1, to: [room("a", on: true, 3)]) == ["a": .off])
        #expect(CrownBrightness.apply(steps: -2, to: [room("a", on: true, 20)]) == ["a": .brightness(10)])
    }

    @Test func zonesAreLeftAlone() {
        #expect(CrownBrightness.apply(steps: 1, to: [room("z", on: true, 50, kind: .zone)]).isEmpty)
        #expect(CrownBrightness.affected([room("a", on: true, 5), room("z", on: true, 5, kind: .zone), room("b", on: false, 5)]) == 1)
    }
}

@MainActor
struct ControlTests {
    func ready() async -> (AppModel, MockBridgeClient) {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        return (app, mock)
    }

    @Test func tapTogglesAtOnceAndTellsTheBridge() async throws {
        let (app, mock) = await ready()
        app.toggle("mock-room-0")
        #expect(app.room("mock-room-0")?.isOn == false)   // immediately
                #expect(await eventually { await mock.currentHome.room("mock-room-0")?.isOn == false })
    }

    @Test func roomDimmedToZeroComesBackAtSeventy() async throws {
        let (app, mock) = await ready()
        for _ in 0..<20 { app.crownStep(-1) }              // living room 70% → 0 → off
        #expect(app.room("mock-room-0")?.isOn == false)
        #expect(app.store.zeroDimmed.contains("mock-room-0"))
        try await Task.sleep(for: .milliseconds(1200))
        app.toggle("mock-room-0")
        #expect(app.room("mock-room-0")?.percent == 70)
        try await Task.sleep(for: .milliseconds(1200))
        #expect(await mock.currentHome.room("mock-room-0")?.percent == 70)
        #expect(!app.store.zeroDimmed.contains("mock-room-0"))
    }

    @Test func allOffUsesTheAllLightsGroup() async throws {
        let (app, mock) = await ready()
        app.allOff()
        #expect(app.rooms.allSatisfy { !$0.isOn })
        #expect(await eventually { await mock.currentHome.lights.values.allSatisfy { !$0.isOn } })
    }

    @Test func crownKeepsDifferencesBetweenRooms() async {
        let (app, _) = await ready()
        app.crownStep(1)
        #expect(app.room("mock-room-0")?.percent == 75)    // 70 → 75
        #expect(app.room("mock-room-3")?.percent == 90)    // 85 → 90
        #expect(app.room("mock-room-1")?.percent == 100)   // already 100
        #expect(app.room("mock-room-2")?.isOn == false)    // off rooms untouched
        #expect(app.room("mock-zone-0")?.percent == 80)    // zones untouched
    }

    @Test func liveUpdatesFromTheStreamReachTheTiles() async throws {
        let (app, mock) = await ready()
        app.isActive = true
        app.startEventStream()
        #expect(await eventually { await mock.streamCount > 0 })
        await mock.simulateOutsideChange()
        let home = await mock.currentHome
        func matches() -> Bool { home.rooms.filter { $0.kind == .room }.allSatisfy { app.room($0.id)?.isOn == $0.isOn } }
        for _ in 0..<20 where !matches() { try await Task.sleep(for: .milliseconds(50)) }
        #expect(matches())
        app.stopEventStream()
    }
}

@MainActor
struct SettleTests {
    func groupedLight(_ id: String, on: Bool) -> HueEvent {
        HueEvent(type: "update", data: [HueEventItem(id: id, type: "grouped_light", on: HueOn(on: on))])
    }

    /// The reported flash: a late update with the old state arrives just after a tap.
    @Test func lateEchoDoesNotFlashATappedTile() async throws {
        let (app, _) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.toggle("mock-room-0")                                     // on → off
        try await Task.sleep(for: .milliseconds(300))                 // the command has gone out
        app.apply([groupedLight("mock-group-0", on: true)])           // an older "on" arrives late
        #expect(app.room("mock-room-0")?.isOn == false)
    }

    @Test func theBridgesLastWordWinsOnceSettled() async throws {
        let (app, _) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.toggle("mock-room-0")
        try await Task.sleep(for: .milliseconds(100))                 // the command has gone out
        app.lastLocalChange["mock-room-0"] = Date().addingTimeInterval(-1.5)   // 0.5 s left to settle
        app.apply([groupedLight("mock-group-0", on: true)])           // e.g. someone switched it back on
        #expect(app.room("mock-room-0")?.isOn == false)               // still settling
        #expect(await eventually(timeout: .seconds(3)) { app.room("mock-room-0")?.isOn == true })
    }

    @Test func otherRoomsStillUpdateLive() async {
        let (app, _) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.toggle("mock-room-0")
        app.apply([groupedLight("mock-group-2", on: true)])           // bedroom switched on elsewhere
        #expect(app.room("mock-room-2")?.isOn == true)
    }
}

@MainActor
struct ReloadRaceTests {
    /// The reported bug: reopen the app, tap a lit tile before the reload finishes — the light
    /// went off but the reload's older reply put the tile back on.
    @Test func tapDuringReloadIsNotUndoneByTheReply() async throws {
        let mock = MockBridgeClient(latency: .milliseconds(300))
        let store = SharedStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let app = AppModel(environment: .mock(mock, paired: true, store: store), store: store, log: BridgeLog(fileURL: nil))
        await app.start()
        #expect(app.room("mock-room-0")?.isOn == true)
        let reload = Task { await app.reload() }                    // coming back to the app
        try await Task.sleep(for: .milliseconds(50))                 // the read is in flight
        app.toggle("mock-room-0")                                     // tap: off
        await reload.value
        #expect(app.room("mock-room-0")?.isOn == false)               // the old reply didn't win
        #expect(await eventually(timeout: .seconds(4)) { await mock.currentHome.room("mock-room-0")?.isOn == false })
        try await Task.sleep(for: .seconds(3.2))                      // the follow-up check
        #expect(app.room("mock-room-0")?.isOn == false)
    }
}
