import Foundation
import Testing
@testable import House_Lights_Watch_App

struct HybridModelTests {
    let red = WheelColor(hue: 0, saturation: 1), blue = WheelColor(hue: 0.66, saturation: 1), green = WheelColor(hue: 0.33, saturation: 1)

    @Test func eachBulbGetsOneColorInTurn() {
        let h = Hybrid(colors: [red, blue], moving: false)
        let a = h.assignments(lightIDs: ["1", "2", "3"], gamut: .c)
        #expect(a["1"] == red.xy(in: .c) && a["2"] == blue.xy(in: .c) && a["3"] == red.xy(in: .c))
    }

    @Test func moreColorsThanBulbsMustMove() {
        #expect(Hybrid.mustMove(colors: 3, bulbs: 2))
        #expect(!Hybrid.mustMove(colors: 2, bulbs: 2))
    }

    @Test func scenePaletteAndDynamicsDecode() throws {
        let scene = #"{"errors":[],"data":[{"id":"s","type":"scene","metadata":{"name":"House Lights – Den"},"group":{"rid":"r","rtype":"room"},"actions":[],"palette":{"color":[{"color":{"xy":{"x":0.6,"y":0.3}},"dimming":{"brightness":80}},{"color":{"xy":{"x":0.2,"y":0.1}}}],"dimming":[],"color_temperature":[],"effects":[]},"speed":0.25,"auto_dynamic":true}]}"#
        let dto = try #require(try JSONDecoder().decode(HueResponse<HueSceneDTO>.self, from: Data(scene.utf8)).data.first)
        #expect(dto.palette?.color.count == 2 && dto.auto_dynamic == true)
        let event = #"[{"type":"update","data":[{"id":"l","type":"light","dynamics":{"status":"dynamic_palette","speed":0.25}}]}]"#
        #expect(try EventStreamParser.decode(event).first?.data.first?.dynamics?.status == "dynamic_palette")
    }

    /// Hybrids saved before speeds existed still load, and move slowly as before.
    @Test func olderSavedHybridsStillDecode() throws {
        let json = #"{"colors":[{"hue":0,"saturation":1},{"hue":0.5,"saturation":1}],"moving":true}"#
        let h = try JSONDecoder().decode(Hybrid.self, from: Data(json.utf8))
        #expect(h.speed == nil && h.pace == .slow && h.moving)
        #expect(Hybrid.Speed.nearest(0.55) == .medium)
    }
}

@MainActor
struct HybridTests {
    let red = WheelColor(hue: 0, saturation: 1), blue = WheelColor(hue: 0.66, saturation: 1), green = WheelColor(hue: 0.33, saturation: 1)

    func ready() async -> (AppModel, MockBridgeClient) {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.remoteSceneDelay = .milliseconds(100)
        return (app, mock)
    }

    func colors(_ mock: MockBridgeClient, _ ids: [String]) async -> [LightColor?] {
        let home = await mock.currentHome
        return ids.map { home.lights[$0]?.color }
    }

    @Test func aStaticHybridPutsOneColorOnEachBulb() async {
        let (app, mock) = await ready()
        app.setHybrid([red, blue], moving: false, roomID: "mock-room-0")
        #expect(app.room("mock-room-0")?.mixColors?.count == 2)        // the tile blends two colors
        #expect(app.isTemporary("mock-room-0"))
        #expect(await eventually {
            let c = await colors(mock, ["mock-light-0-a", "mock-light-0-b"])
            return c[0] == .xy(red.xy(in: .c)) && c[1] == .xy(blue.xy(in: .c))
        })
        let scene = await mock.currentHome.mixScenes["mock-room-0"]
        #expect(scene?.palette.count == 2 && scene?.autoDynamic == false)
        #expect(await mock.currentHome.lights["mock-light-0-a"]?.isDynamic == false)
    }

    @Test func moreColorsThanBulbsMoves() async {
        let (app, mock) = await ready()
        #expect(app.mixMustMove(colors: 3, roomID: "mock-room-0"))
        app.setHybrid([red, blue, green], moving: false, roomID: "mock-room-0")
        #expect(app.hybrids["mock-room-0"]?.moving == true)            // forced on
        #expect(await eventually { await mock.currentHome.lights["mock-light-0-a"]?.isDynamic == true })
        #expect(await mock.currentHome.mixScenes["mock-room-0"]?.autoDynamic == true)
        #expect(await mock.currentHome.mixScenes["mock-room-0"]?.palette.count == 3)
    }

    @Test func aMovingHybridStaysTemporaryWhileItMorphs() async throws {
        let (app, mock) = await ready()
        app.setHybrid([red, blue], moving: true, roomID: "mock-room-0")
        #expect(await eventually { await mock.currentHome.lights["mock-light-0-a"]?.isDynamic == true })
        app.lastLocalChange["mock-room-0"] = .distantPast
        app.apply(try await mock.fetchStates())                        // the bridge reports the morphing lights
        await mock.simulateOutsideColor(roomID: "mock-room-0", color: .xy(XY(x: 0.4, y: 0.45)))   // a morph step
        app.apply(try await mock.fetchStates())
        #expect(app.isTemporary("mock-room-0"))
        #expect(app.hybrids["mock-room-0"] != nil)
    }

    @Test func aSingleColorReplacesTheHybrid() async throws {
        let (app, mock) = await ready()
        app.setHybrid([red, blue], moving: true, roomID: "mock-room-0")
        #expect(await eventually { await mock.currentHome.lights["mock-light-0-a"]?.isDynamic == true })
        try await Task.sleep(for: .milliseconds(1100))
        app.setWarmth(kelvin: 3000, roomID: "mock-room-0")
        #expect(app.hybrids["mock-room-0"] == nil)
        #expect(await eventually { await mock.currentHome.lights["mock-light-0-a"]?.isDynamic == false })
    }

    @Test func aHybridCanBeTheDefault() async throws {
        let (app, mock) = await ready()
        app.setHybrid([red, blue, green], moving: true, roomID: "mock-room-0")
        app.setAsDefault("mock-room-0")
        #expect(await eventually { await mock.currentHome.defaults["mock-room-0"]?.palette.count == 3 })
        #expect(await mock.currentHome.defaults["mock-room-0"]?.autoDynamic == true)
        #expect(!app.isTemporary("mock-room-0"))
        try await Task.sleep(for: .milliseconds(1100))
        app.setWarmth(kelvin: 5000, roomID: "mock-room-0")             // something else for a while
        try await Task.sleep(for: .milliseconds(1100))
        app.backToDefault("mock-room-0")                                // back to the moving hybrid
        #expect(await eventually { await mock.currentHome.lights["mock-light-0-a"]?.isDynamic == true })
        #expect(app.room("mock-room-0")?.isMoving == true)
    }

    @Test func theRemoteStartsTheHybrid() async throws {
        let (app, mock) = await ready()
        app.setRemoteScene("mock-room-0", enabled: true)
        app.setHybrid([red, blue], moving: true, roomID: "mock-room-0")
        #expect(await eventually { await mock.currentHome.remoteScenes["mock-room-0"]?.autoDynamic == true })
        app.toggle("mock-room-0")
        #expect(await eventually { await mock.currentHome.room("mock-room-0")?.isOn == false })
        try await mock.simulateRemotePress(roomID: "mock-room-0")
        #expect(await mock.currentHome.lights["mock-light-0-a"]?.isDynamic == true)
    }

    @Test func aHybridForAnOffRoomWaitsForTurnOn() async {
        let (app, mock) = await ready()
        app.setHybrid([red, blue], moving: false, roomID: "mock-room-4")   // Front door, off
        #expect(app.room("mock-room-4")?.isOn == false)
        #expect(await eventually { await mock.currentHome.mixScenes["mock-room-4"] != nil })
        #expect(await mock.currentHome.room("mock-room-4")?.isOn == false)
        app.toggle("mock-room-4")
        #expect(await eventually {
            let c = await colors(mock, ["mock-light-4-a", "mock-light-4-b"])
            return await mock.currentHome.room("mock-room-4")?.isOn == true && c[0] == .xy(red.xy(in: .c)) && c[1] == .xy(blue.xy(in: .c))
        })
    }

    @Test func aHybridIsKeptWhenTheRoomIsSwitchedOff() async throws {
        let (app, mock) = await ready()
        app.setHybrid([red, blue], moving: false, roomID: "mock-room-0")
        #expect(await eventually { await mock.currentHome.lights["mock-light-0-b"]?.color == .xy(blue.xy(in: .c)) })
        app.toggle("mock-room-0")
        #expect(await eventually { await mock.currentHome.room("mock-room-0")?.isOn == false })
        app.lastLocalChange["mock-room-0"] = .distantPast
        app.apply(try await mock.fetchStates())
        #expect(app.hybrids["mock-room-0"] != nil)
    }

    @Test func theChosenSpeedReachesTheMixScene() async {
        let (app, mock) = await ready()
        app.setHybrid([red, blue], moving: true, speed: .fast, roomID: "mock-room-0")
        #expect(await eventually { await mock.currentHome.mixScenes["mock-room-0"]?.speed == Hybrid.Speed.fast.value })
        app.setHybrid([red, blue], moving: true, roomID: "mock-room-0")          // e.g. a color added: speed kept
        #expect(app.hybrids["mock-room-0"]?.pace == .fast)
    }

    @Test func movingRoomsDriftThroughTheHybridsColors() async {
        let (app, _) = await ready()
        app.setHybrid([red, blue], moving: false, roomID: "mock-room-0")
        #expect(app.room("mock-room-0").flatMap(app.movingColors) == nil)        // still: a plain blend
        app.setHybrid([red, blue], moving: true, roomID: "mock-room-0")
        #expect(app.room("mock-room-0").flatMap(app.movingColors)?.count == 2)
    }

    @Test func setAsDefaultAndBackToDefaultDriftForAMovingHybrid() async {
        let (app, mock) = await ready()
        app.setHybrid([red, blue, green], moving: true, roomID: "mock-room-0")
        #expect(app.room("mock-room-0").flatMap(app.movingColors)?.count == 3)        // Set as default
        #expect(app.movingDefaultColors("mock-room-0") == nil)                           // the default is still one color
        app.setAsDefault("mock-room-0")
        #expect(await eventually { await mock.currentHome.defaults["mock-room-0"]?.autoDynamic == true })
        #expect(app.movingDefaultColors("mock-room-0")?.count == 3)                      // Back to default
    }
}
