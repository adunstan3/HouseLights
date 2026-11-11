import Foundation

/// Color conversions for Hue. The xy ↔ RGB formulas are the ones Philips publishes for
/// Hue ("RGB to xy Color conversion"): sRGB gamma, then the Wide RGB D65 matrix.
nonisolated enum ColorMath {
    static let minKelvin = 2200
    static let maxKelvin = 6500

    static func mirek(fromKelvin k: Int) -> Int { Int((1_000_000 / Double(max(k, 1))).rounded()) }
    static func kelvin(fromMirek m: Int) -> Int { Int((1_000_000 / Double(max(m, 1))).rounded()) }

    // MARK: RGB → xy

    static func xy(rgb: RGB) -> XY {
        let r = linear(rgb.r), g = linear(rgb.g), b = linear(rgb.b)
        let X = r * 0.664511 + g * 0.154324 + b * 0.162028
        let Y = r * 0.283881 + g * 0.668433 + b * 0.047685
        let Z = r * 0.000088 + g * 0.072310 + b * 0.986039
        let sum = X + Y + Z
        guard sum > 0 else { return XY(x: 0.3127, y: 0.3290) }   // D65 white for black
        return XY(x: X / sum, y: Y / sum)
    }

    // MARK: xy → RGB

    /// Full-brightness display color for an xy point, normalized so the largest channel is 1.
    static func rgb(xy p: XY) -> RGB {
        let y = max(p.y, 0.0001)
        let Y = 1.0
        let X = (Y / y) * p.x
        let Z = (Y / y) * (1 - p.x - p.y)
        var r = X * 1.656492 - Y * 0.354851 - Z * 0.255038
        var g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
        var b = X * 0.051713 - Y * 0.121364 + Z * 1.011530
        r = max(r, 0); g = max(g, 0); b = max(b, 0)
        let peak = max(r, g, b, 0.0001)
        r /= peak; g /= peak; b /= peak
        return RGB(r: gamma(r), g: gamma(g), b: gamma(b))
    }

    // MARK: Kelvin → RGB

    /// Approximate display color of a white temperature (Tanner Helland's fit).
    static func rgb(kelvin: Int) -> RGB {
        let t = Double(min(max(kelvin, 1000), 40000)) / 100
        let red = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let green = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let blue = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        func c(_ v: Double) -> Double { min(max(v, 0), 255) / 255 }
        return RGB(r: c(red), g: c(green), b: c(blue))
    }

    // MARK: Hue / saturation (the color wheel)

    /// HSV with value 1. `hue` is 0–1 (0 = red), `saturation` 0–1.
    static func rgb(hue: Double, saturation: Double) -> RGB {
        let h = (hue - floor(hue)) * 6
        let s = min(max(saturation, 0), 1)
        let i = Int(h) % 6
        let f = h - floor(h)
        let p = 1 - s, q = 1 - s * f, t = 1 - s * (1 - f)
        switch i {
        case 0: return RGB(r: 1, g: t, b: p)
        case 1: return RGB(r: q, g: 1, b: p)
        case 2: return RGB(r: p, g: 1, b: t)
        case 3: return RGB(r: p, g: q, b: 1)
        case 4: return RGB(r: t, g: p, b: 1)
        default: return RGB(r: 1, g: p, b: q)
        }
    }

    /// Inverse of `rgb(hue:saturation:)` (value is ignored).
    static func hueSaturation(rgb c: RGB) -> (hue: Double, saturation: Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let d = mx - mn
        guard mx > 0, d > 0.0001 else { return (0, 0) }
        var h: Double
        if mx == c.r { h = (c.g - c.b) / d }
        else if mx == c.g { h = 2 + (c.b - c.r) / d }
        else { h = 4 + (c.r - c.g) / d }
        h /= 6
        if h < 0 { h += 1 }
        return (h, d / mx)
    }

    // MARK: Helpers

    private static func linear(_ v: Double) -> Double {
        v > 0.04045 ? pow((v + 0.055) / 1.055, 2.4) : v / 12.92
    }

    private static func gamma(_ v: Double) -> Double {
        let out = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        return min(max(out, 0), 1)
    }
}
