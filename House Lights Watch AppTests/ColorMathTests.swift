import Foundation
import Testing
@testable import House_Lights_Watch_App

struct ColorMathTests {
    @Test func kelvinMirekRoundTrip() {
        #expect(ColorMath.mirek(fromKelvin: 2200) == 455)
        #expect(ColorMath.mirek(fromKelvin: 6500) == 154)
        #expect(ColorMath.kelvin(fromMirek: 370) == 2703)
        #expect(LightColor.temperature(mirek: 370).label == "2700K")
    }

    @Test func whiteMapsNearD65() {
        let p = ColorMath.xy(rgb: .white)
        #expect(abs(p.x - 0.3227) < 0.01)
        #expect(abs(p.y - 0.329) < 0.01)
    }

    @Test func primariesRoundTrip() {
        for c in [RGB(r: 1, g: 0, b: 0), RGB(r: 0, g: 1, b: 0), RGB(r: 0, g: 0, b: 1), RGB(r: 1, g: 0.5, b: 0.2)] {
            let back = ColorMath.rgb(xy: ColorMath.xy(rgb: c))
            // xy loses brightness, so compare normalized channels.
            let peak = max(c.r, c.g, c.b)
            #expect(abs(back.r - c.r / peak) < 0.03)
            #expect(abs(back.g - c.g / peak) < 0.03)
            #expect(abs(back.b - c.b / peak) < 0.03)
        }
    }

    @Test func hueSaturationRoundTrip() {
        for (h, s) in [(0.0, 1.0), (0.33, 0.5), (0.66, 0.8), (0.9, 0.2)] {
            let back = ColorMath.hueSaturation(rgb: ColorMath.rgb(hue: h, saturation: s))
            #expect(abs(back.hue - h) < 0.01)
            #expect(abs(back.saturation - s) < 0.01)
        }
        #expect(ColorMath.hueSaturation(rgb: .white).saturation == 0)
    }

    @Test func warmIsRedderThanCool() {
        let warm = ColorMath.rgb(kelvin: 2200), cool = ColorMath.rgb(kelvin: 6500)
        #expect(warm.r == 1)
        #expect(warm.b < 0.3)
        #expect(cool.b > 0.9)
    }

    @Test func gamutKeepsInsidePoints() {
        let inside = XY(x: 0.4, y: 0.4)
        #expect(Gamut.c.contains(inside))
        #expect(Gamut.c.clamp(inside) == inside)
    }

    @Test func gamutClampsOutsidePointsToTheEdge() {
        let outside = XY(x: 0.75, y: 0.25)   // redder than gamut C's red corner
        #expect(!Gamut.c.contains(outside))
        let clamped = Gamut.c.clamp(outside)
        #expect(Gamut.c.contains(XY(x: clamped.x - 0.0001, y: clamped.y)) || clamped.distance(to: Gamut.c.red) < 0.05)
        #expect(clamped.distance(to: outside) < outside.distance(to: Gamut.c.red) + 0.0001)
    }

    @Test func colorsCloseTogetherCompareEqual() {
        #expect(LightColor.temperature(mirek: 370).isClose(to: .temperature(mirek: 375)))
        #expect(!LightColor.temperature(mirek: 370).isClose(to: .temperature(mirek: 300)))
        #expect(LightColor.xy(XY(x: 0.3, y: 0.3)).isClose(to: .xy(XY(x: 0.305, y: 0.302))))
        #expect(!LightColor.xy(XY(x: 0.3, y: 0.3)).isClose(to: .temperature(mirek: 300)))
    }
}
