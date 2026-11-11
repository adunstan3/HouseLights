import Foundation
import Testing
@testable import House_Lights_Watch_App

@MainActor
struct DefaultsTests {
    func ready() async -> (AppModel, MockBridgeClient) {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        return (app, mock)
    }

    @Test func firstChangeSavesTheCurrentStateAsTheDefaultScene() async throws {
        let (app, mock) = await ready()
        #expect(app.home.defaults["mock-room-3"] == nil)                       // Office has no default yet
        app.setWarmth(kelvin: 3000, roomID: "mock-room-3")
        #expect(await eventually { await mock.currentHome.defaults["mock-room-3"] != nil })
        let scene = try #require(await mock.currentHome.defaults["mock-room-3"])
        #expect(scene.name == "House Lights – Office")
        #expect(scene.color == .xy(XY(x: 0.235, y: 0.235)))                    // the blue it had before
        #expect(app.isTemporary("mock-room-3"))
    }

    @Test func changingBackToTheDefaultColorIsNotTemporary() async {
        let (app, _) = await ready()
        app.setWarmth(kelvin: 2200, roomID: "mock-room-0")                      // default is 2700 K
        #expect(app.isTemporary("mock-room-0"))
        app.setWarmth(kelvin: 2700, roomID: "mock-room-0")
        #expect(!app.isTemporary("mock-room-0"))
    }

    @Test func temporaryColorSurvivesOffAndOn() async throws {
        let (app, _) = await ready()
        app.setWarmth(kelvin: 5000, roomID: "mock-room-0")
        app.toggle("mock-room-0")
        try await Task.sleep(for: .milliseconds(1100))
        app.toggle("mock-room-0")
        #expect(app.isTemporary("mock-room-0"))
    }

    @Test func backToDefaultRecallsTheSceneAtTheCurrentBrightness() async throws {
        let (app, mock) = await ready()
        app.setWarmth(kelvin: 5000, roomID: "mock-room-0")
        try await Task.sleep(for: .milliseconds(1100))
        app.backToDefault("mock-room-0")
        #expect(!app.isTemporary("mock-room-0"))
        #expect(app.room("mock-room-0")?.color == .temperature(mirek: 370))
        #expect(await eventually { await mock.currentHome.lights["mock-light-0-a"]?.color == .temperature(mirek: 370) })
        #expect(await mock.currentHome.lights["mock-light-0-a"]?.brightness == 70)
    }

    @Test func backToDefaultWhileOffWaitsForTheNextTurnOn() async throws {
        let (app, mock) = await ready()
        app.setWarmth(kelvin: 5000, roomID: "mock-room-0")
        app.toggle("mock-room-0")                                                 // off
        try await Task.sleep(for: .milliseconds(1100))
        app.backToDefault("mock-room-0")
        #expect(app.room("mock-room-0")?.isOn == false)                         // doesn't turn on
        #expect(app.store.pendingDefaults.contains("mock-room-0"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(await mock.currentHome.room("mock-room-0")?.isOn == false)
        app.toggle("mock-room-0")                                                 // on → default
        #expect(await eventually {
            let light = await mock.currentHome.lights["mock-light-0-a"]
            return light?.isOn == true && light?.color == .temperature(mirek: 370)
        })
        #expect(!app.store.pendingDefaults.contains("mock-room-0"))
    }

    @Test func setAsDefaultRewritesTheScene() async throws {
        let (app, mock) = await ready()
        app.setWarmth(kelvin: 4000, roomID: "mock-room-0")
        app.setAsDefault("mock-room-0")
        #expect(!app.isTemporary("mock-room-0"))
        #expect(await eventually { await mock.currentHome.defaults["mock-room-0"]?.color == .temperature(mirek: 250) })
    }

    @Test func colorChangedOutsideTheAppDropsTheTemporaryLabel() async throws {
        let (app, mock) = await ready()
        app.isActive = true
        app.startEventStream()
        #expect(await eventually { await mock.streamCount > 0 })                 // let the stream connect
        app.setWarmth(kelvin: 5000, roomID: "mock-room-0")
        #expect(app.isTemporary("mock-room-0"))
        app.lastLocalChange["mock-room-0"] = .distantPast                        // pretend it was a while ago
        await mock.simulateOutsideColor(roomID: "mock-room-0", color: .temperature(mirek: 366))   // power-cut warm white
        #expect(await eventually { !app.isTemporary("mock-room-0") })
        app.stopEventStream()
    }

    @Test func echoesOfOurOwnChangesKeepTheLabel() async throws {
        let (app, mock) = await ready()
        app.isActive = true
        app.startEventStream()
        #expect(await eventually { await mock.streamCount > 0 })
        app.setWarmth(kelvin: 5000, roomID: "mock-room-0")
        try await Task.sleep(for: .milliseconds(200))                             // the bridge echoes it back
        #expect(app.isTemporary("mock-room-0"))
        app.stopEventStream()
    }
}
