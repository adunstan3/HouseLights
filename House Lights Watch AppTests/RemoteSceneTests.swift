import Foundation
import Testing
@testable import House_Lights_Watch_App

/// "House Lights Now" scenes for Hue dimmer switches: the watch keeps each chosen room's scene
/// up to date, so the remote turns the room on in the watch's last look.
@MainActor
struct RemoteSceneTests {
    func ready() async -> (AppModel, MockBridgeClient) {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.remoteSceneDelay = .milliseconds(100)
        return (app, mock)
    }

    func remoteScene(_ mock: MockBridgeClient, _ roomID: String) async -> DefaultScene? {
        await mock.currentHome.remoteScenes[roomID]
    }

    @Test func namesAreToldApart() {
        #expect(DefaultScene.remoteName(for: "Kitchen") == "House Lights Now – Kitchen")
        #expect(DefaultScene.isRemoteScene("House Lights Now – Kitchen"))
        #expect(!DefaultScene.isDefaultScene("House Lights Now – Kitchen"))
        #expect(DefaultScene.isDefaultScene("House Lights – Kitchen"))
        #expect(DefaultScene.remoteName(for: "A very long upstairs room name").count <= 32)
    }

    @Test func choosingARoomCreatesItsSceneFromTheCurrentLook() async {
        let (app, mock) = await ready()
        app.setRemoteScene("mock-room-3", enabled: true)                   // Office: blue, 85%
        #expect(await eventually { await remoteScene(mock, "mock-room-3") != nil })
        let scene = await remoteScene(mock, "mock-room-3")
        #expect(scene?.name == "House Lights Now – Office")
        #expect(scene?.color == .xy(XY(x: 0.235, y: 0.235)))
        #expect(scene?.actions.first?.action.dimming?.brightness == 85)
        #expect(await mock.currentHome.defaults["mock-room-3"] == nil)     // the default is a separate scene
    }

    @Test func changesAreSavedAfterTheyStopAndTheRemoteUsesThem() async throws {
        let (app, mock) = await ready()
        app.setRemoteScene("mock-room-0", enabled: true)
        #expect(await eventually { await remoteScene(mock, "mock-room-0") != nil })
        app.setWarmth(kelvin: 5000, roomID: "mock-room-0")
        app.setBrightness(40, roomID: "mock-room-0")
        #expect(await eventually {
            let s = await remoteScene(mock, "mock-room-0")
            return s?.color == .temperature(mirek: 200) && s?.actions.first?.action.dimming?.brightness == 40
        })
        // The room is switched off, then on with the dimmer: it comes back in the watch's look.
        app.toggle("mock-room-0")
        try await Task.sleep(for: .milliseconds(1100))
        try await mock.simulateRemotePress(roomID: "mock-room-0")
        let light = await mock.currentHome.lights["mock-light-0-a"]
        #expect(light?.isOn == true && light?.color == .temperature(mirek: 200) && light?.brightness == 40)
    }

    /// Turning a room off (tap, All off, or dimming to 0%) never saves "off" or 0% into the scene.
    @Test func turningOffNeverSavesZero() async throws {
        let (app, mock) = await ready()
        app.setRemoteScene("mock-room-0", enabled: true)                   // 70%
        #expect(await eventually { await remoteScene(mock, "mock-room-0") != nil })
        app.toggle("mock-room-0")
        app.allOff()
        try await Task.sleep(for: .milliseconds(1100))
        app.toggle("mock-room-0")
        try await Task.sleep(for: .milliseconds(1100))
        for _ in 0..<20 { app.crownStep(-1) }                              // dimmed to 0% → off
        try await Task.sleep(for: .milliseconds(400))
        let scene = await remoteScene(mock, "mock-room-0")
        #expect(scene?.actions.allSatisfy { $0.action.on?.on == true } == true)
        #expect(scene?.actions.allSatisfy { ($0.action.dimming?.brightness ?? 0) >= 1 } == true)
    }

    @Test func backToDefaultResetsTheRemoteSceneToo() async {
        let (app, mock) = await ready()
        app.setRemoteScene("mock-room-0", enabled: true)
        app.setWarmth(kelvin: 5000, roomID: "mock-room-0")
        #expect(await eventually { await remoteScene(mock, "mock-room-0")?.color == .temperature(mirek: 200) })
        app.backToDefault("mock-room-0")                                   // default is 2700 K
        #expect(await eventually { await remoteScene(mock, "mock-room-0")?.color == .temperature(mirek: 370) })
    }

    @Test func roomsNotChosenGetNoScene() async throws {
        let (app, mock) = await ready()
        app.setWarmth(kelvin: 5000, roomID: "mock-room-1")
        try await Task.sleep(for: .milliseconds(300))
        #expect(await remoteScene(mock, "mock-room-1") == nil)
        #expect(app.store.remoteRooms.isEmpty)
    }
}
