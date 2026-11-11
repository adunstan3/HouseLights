import Foundation

/// A CIE 1931 xy chromaticity, which is how Hue describes colors.
nonisolated struct XY: Codable, Sendable, Hashable {
    var x: Double
    var y: Double

    func distance(to other: XY) -> Double { hypot(x - other.x, y - other.y) }
}

/// What a light (or a room) is showing: a white temperature or an xy color.
nonisolated enum LightColor: Codable, Sendable, Hashable {
    /// Hue measures white in mirek (1,000,000 / kelvin). 153 ≈ 6500 K, 454 ≈ 2200 K.
    case temperature(mirek: Int)
    case xy(XY)

    static let warmWhite = LightColor.temperature(mirek: 370)   // ≈ 2700 K, Hue's default

    init(kelvin: Int) { self = .temperature(mirek: ColorMath.mirek(fromKelvin: kelvin)) }

    var kelvin: Int? {
        if case .temperature(let m) = self { return ColorMath.kelvin(fromMirek: m) }
        return nil
    }

    /// Colors within this distance are treated as "the same" (bridge rounding, gamut fitting).
    func isClose(to other: LightColor) -> Bool {
        switch (self, other) {
        case let (.temperature(a), .temperature(b)): return abs(a - b) <= 8
        case let (.xy(a), .xy(b)): return a.distance(to: b) <= 0.015
        default: return false
        }
    }

    /// Short label such as "2700K" or "Color".
    var label: String {
        if let kelvin { return "\(Int((Double(kelvin) / 100).rounded()) * 100)K" }
        return "Color"
    }

    /// Display RGB, 0–1 each.
    var rgb: RGB {
        switch self {
        case .temperature(let m): return ColorMath.rgb(kelvin: ColorMath.kelvin(fromMirek: m))
        case .xy(let p): return ColorMath.rgb(xy: p)
        }
    }
}

nonisolated struct RGB: Sendable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    func mixed(with other: RGB, amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    static let white = RGB(r: 1, g: 1, b: 1)
}
