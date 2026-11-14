import Foundation
import Testing
@testable import House_Lights_Watch_App

/// Grid › Saved lights: whole-house configurations.
@MainActor
struct ConfigTests {
    func ready() async -> (AppModel, MockBridgeClient) {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        return (app, mock)
    }

    @Test func savingRecordsEveryShownRoomLightByLight() async throws {
        let (app, _) = await ready()
        let config = try #require(app.saveConfig(named: "  Evening  "))
        #expect(config.name == "Evening")
        #expect(config.rooms.map(\.roomID) == app.rooms.map(\.id))
        let office = try #require(config.rooms.first { $0.roomID == "mock-room-3" })
        #expect(office.isOn)
        #expect(office.lights.count == app.home.lights(in: app.room("mock-room-3")!).count)
        #expect(app.houseConfigs.first == config)
        #expect(app.store.houseConfigs == app.houseConfigs)   // kept on the watch
        #expect(app.saveConfig(named: "   ") == nil)          // a name is needed
    }

    @Test func loadingPutsTheHouseBack() async throws {
        let (app, mock) = await ready()
        let config = try #require(app.saveConfig(named: "Before"))
        let before = app.home.lights
        // Change things: living room off, office to red at 30%.
        app.toggle("mock-room-0")
        app.setColor(XY(x: 0.67, y: 0.32), roomID: "mock-room-3")
        try await Task.sleep(for: .milliseconds(1200))
        app.loadConfig(config.id)
        #expect(app.room("mock-room-0")?.isOn == true)          // the grid shows it at once
        #expect(await eventually(timeout: .seconds(4)) {
            let lights = await mock.currentHome.lights
            return app.rooms.flatMap { app.home.lights(in: $0) }.allSatisfy { light in
                guard let then = before[light.id], let now = lights[light.id] else { return false }
                return now.isOn == then.isOn && (!then.isOn || (now.brightness - then.brightness).magnitude < 1
                                                 && now.color.map { $0.isClose(to: then.color!) } ?? (then.color == nil))
            }
        })
    }

    @Test func loadingTurnsSavedOffRoomsOff() async throws {
        let (app, mock) = await ready()
        app.toggle("mock-room-0")                                // living room off
        try await Task.sleep(for: .milliseconds(1100))
        let config = try #require(app.saveConfig(named: "Living off"))
        app.toggle("mock-room-0")                                // back on
        try await Task.sleep(for: .milliseconds(1100))
        app.loadConfig(config.id)
        #expect(app.room("mock-room-0")?.isOn == false)
        #expect(await eventually { await mock.currentHome.room("mock-room-0")?.isOn == false })
    }

    @Test func renameOverwriteAndDelete() async throws {
        let (app, _) = await ready()
        let config = try #require(app.saveConfig(named: "One"))
        app.renameConfig(config.id, to: "Two")
        #expect(app.houseConfigs.first?.name == "Two")
        app.renameConfig(config.id, to: "")
        #expect(app.houseConfigs.first?.name == "Two")           // an empty name is ignored
        app.toggle("mock-room-0")
        app.overwriteConfig(config.id)
        let saved = try #require(app.houseConfigs.first)
        #expect(saved.id == config.id && saved.name == "Two")
        #expect(saved.rooms.first { $0.roomID == "mock-room-0" }?.isOn == false)
        app.deleteConfig(config.id)
        #expect(app.houseConfigs.isEmpty)
    }

    @Test func aMovingMixComesBackMoving() async throws {
        let (app, mock) = await ready()
        let red = WheelColor(hue: 0, saturation: 1), blue = WheelColor(hue: 0.66, saturation: 1)
        app.setHybrid([red, blue], moving: true, roomID: "mock-room-0")
        #expect(await eventually { await mock.currentHome.lights(in: mock.currentHome.room("mock-room-0")!).allSatisfy(\.isDynamic) })
        let config = try #require(app.saveConfig(named: "Party"))
        app.setColor(XY(x: 0.3, y: 0.3), roomID: "mock-room-0")
        #expect(app.hybrids["mock-room-0"] == nil)
        try await Task.sleep(for: .milliseconds(1100))
        app.loadConfig(config.id)
        #expect(app.hybrids["mock-room-0"]?.moving == true)
        #expect(await eventually { await mock.currentHome.lights(in: mock.currentHome.room("mock-room-0")!).allSatisfy(\.isDynamic) })
    }
}
