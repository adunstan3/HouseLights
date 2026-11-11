import CoreGraphics
import Foundation

/// The Warmth slider: 2200 K on the left (warm) to 6500 K on the right (cool).
nonisolated enum WarmthScale {
    static let range = ColorMath.minKelvin...ColorMath.maxKelvin

    static func kelvin(atFraction f: Double) -> Int {
        let k = Double(range.lowerBound) + min(max(f, 0), 1) * Double(range.upperBound - range.lowerBound)
        return Int((k / 50).rounded()) * 50
    }

    static func fraction(ofKelvin k: Int) -> Double {
        let clamped = min(max(k, range.lowerBound), range.upperBound)
        return Double(clamped - range.lowerBound) / Double(range.upperBound - range.lowerBound)
    }

    /// The kelvin label shown above the slider, to the nearest 100 K.
    static func label(_ k: Int) -> String { "\(Int((Double(k) / 100).rounded()) * 100)K" }
}

/// The color wheel: hue runs clockwise from red at the top, saturation from white at the
/// center to full at the rim.
nonisolated enum WheelMath {
    /// Hue (0–1) and saturation (0–1) at a point, relative to the wheel's center.
    static func hueSaturation(at point: CGPoint, center: CGPoint, radius: CGFloat) -> (hue: Double, saturation: Double) {
        let dx = Double(point.x - center.x), dy = Double(point.y - center.y)
        var angle = atan2(dx, -dy)   // 0 at the top, clockwise
        if angle < 0 { angle += 2 * .pi }
        let saturation = min(hypot(dx, dy) / Double(max(radius, 1)), 1)
        return (angle / (2 * .pi), saturation)
    }

    /// Where a hue and saturation sit on the wheel.
    static func point(hue: Double, saturation: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = hue * 2 * .pi
        let r = Double(radius) * min(max(saturation, 0), 1)
        return CGPoint(x: center.x + CGFloat(sin(angle) * r), y: center.y - CGFloat(cos(angle) * r))
    }

    /// The Hue xy color for a wheel position, fitted to the room's gamut.
    static func xy(hue: Double, saturation: Double, gamut: Gamut?) -> XY {
        let p = ColorMath.xy(rgb: ColorMath.rgb(hue: hue, saturation: saturation))
        return (gamut ?? .c).clamp(p)
    }

    /// Where the knob starts for a room's current color.
    static func hueSaturation(of color: LightColor) -> (hue: Double, saturation: Double) {
        ColorMath.hueSaturation(rgb: color.rgb)
    }
}
