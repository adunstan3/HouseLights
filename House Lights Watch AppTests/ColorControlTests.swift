import CoreGraphics
import Foundation
import Testing
@testable import House_Lights_Watch_App

struct ColorControlMathTests {
    @Test func warmthScaleEnds() {
        #expect(WarmthScale.kelvin(atFraction: 0) == 2200)
        #expect(WarmthScale.kelvin(atFraction: 1) == 6500)
        #expect(WarmthScale.kelvin(atFraction: -1) == 2200)
        #expect(abs(WarmthScale.fraction(ofKelvin: 4350) - 0.5) < 0.01)
        #expect(WarmthScale.label(3420) == "3400K")
    }

    @Test func wheelTopIsRedAndRimIsSaturated() {
        let c = CGPoint(x: 100, y: 100)
        let top = WheelMath.hueSaturation(at: CGPoint(x: 100, y: 0), center: c, radius: 100)
        #expect(abs(top.hue) < 0.001 && abs(top.saturation - 1) < 0.001)
        let right = WheelMath.hueSaturation(at: CGPoint(x: 200, y: 100), center: c, radius: 100)
        #expect(abs(right.hue - 0.25) < 0.001)
        let centre = WheelMath.hueSaturation(at: c, center: c, radius: 100)
        #expect(centre.saturation == 0)
        let outside = WheelMath.hueSaturation(at: CGPoint(x: 100, y: -50), center: c, radius: 100)
        #expect(outside.saturation == 1)   // past the rim is clamped
    }

    @Test func wheelPointRoundTrips() {
        let c = CGPoint(x: 90, y: 90)
        let p = WheelMath.point(hue: 0.6, saturation: 0.7, center: c, radius: 90)
        let hs = WheelMath.hueSaturation(at: p, center: c, radius: 90)
        #expect(abs(hs.hue - 0.6) < 0.001 && abs(hs.saturation - 0.7) < 0.001)
    }

    @Test func wheelColorsAreClampedToTheGamut() {
        for hue in stride(from: 0.0, to: 1.0, by: 0.05) {
            let xy = WheelMath.xy(hue: hue, saturation: 1, gamut: .a)
            let back = Gamut.a.clamp(xy)
            #expect(back.distance(to: xy) < 1e-9)
        }
    }
}

@MainActor
struct ColorControlTests {
    @Test func warmthIsClampedToTheRoomsRange() async throws {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.setWarmth(kelvin: 2000, roomID: "mock-room-0")          // below 2200 K → room's warmest (454)
        #expect(app.room("mock-room-0")?.color == .temperature(mirek: 454))
                #expect(await eventually { await mock.currentHome.lights["mock-light-0-a"]?.color == .temperature(mirek: 454) })
    }

    @Test func colorTurnsAnOffRoomOn() async throws {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        let xy = WheelMath.xy(hue: 0.6, saturation: 1, gamut: .c)
        app.setColor(xy, roomID: "mock-room-4")                       // Front door, off
        #expect(app.room("mock-room-4")?.isOn == true)
        #expect(app.room("mock-room-4")?.color == .xy(xy))
                #expect(await eventually { await mock.currentHome.room("mock-room-4")?.isOn == true })
    }

    @Test func roomScreenBrightnessToZeroTurnsOff() async {
        let (app, _) = ConnectionTests.makeApp(paired: true)
        await app.start()
        app.setBrightness(0, roomID: "mock-room-0")
        #expect(app.room("mock-room-0")?.isOn == false)
        app.setBrightness(35, roomID: "mock-room-0")
        #expect(app.room("mock-room-0")?.isOn == true)
        #expect(app.room("mock-room-0")?.percent == 35)
    }
}

/// Changes on the Room screen reach the bridge while the finger or Crown is still moving
/// (at most once a second per room), not when the screen is left.
@MainActor
struct LiveSendingTests {
    @Test func warmthDragReachesTheBridgeWhileDragging() async throws {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        var seen: [LightColor?] = []
        for step in 0..<25 {                                       // a 2.5 s drag, 100 ms per move
            app.setWarmth(kelvin: 2200 + step * 150, roomID: "mock-room-0")
            try await Task.sleep(for: .milliseconds(100))
            let c = await mock.currentHome.lights["mock-light-0-a"]?.color
            if seen.last != c { seen.append(c) }
        }
        #expect(seen.count >= 3)                                   // the lights changed during the drag
        #expect(await eventually { await mock.currentHome.lights["mock-light-0-a"]?.color == app.room("mock-room-0")?.color })
    }

    @Test func crownBrightnessReachesTheBridgeWhileTurning() async throws {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        var levels: Set<Int> = []
        for step in 0..<25 {
            app.setBrightness(Double(70 - step), roomID: "mock-room-0")
            try await Task.sleep(for: .milliseconds(100))
            if let b = await mock.currentHome.lights["mock-light-0-a"]?.brightness { levels.insert(Int(b)) }
        }
        #expect(levels.count >= 3)
        #expect(await eventually { await mock.currentHome.lights["mock-light-0-a"]?.brightness == 46 })
    }

    @Test func temporaryCardAppearsAsSoonAsTheColorChanges() async {
        let (app, _) = ConnectionTests.makeApp(paired: true)
        await app.start()
        #expect(!app.isTemporary("mock-room-3"))
        app.setColor(XY(x: 0.6, y: 0.35), roomID: "mock-room-3")
        #expect(app.isTemporary("mock-room-3"))                    // observed property, no reload needed
        #expect(app.temporaryRooms["mock-room-3"] != nil)
    }
}
