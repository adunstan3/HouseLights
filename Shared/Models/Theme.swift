import SwiftUI

/// Colors and type from SPEC.md's Look section (shared with the widget).
nonisolated enum Theme {
    /// Amber, for back arrows, main buttons and highlights.
    static let accent = Color(hex: 0xFFB65C)
    /// Dark text drawn on amber and on lit tiles.
    static let onAccent = Color(hex: 0x1A1400)
    static let background = Color.black
    /// Cards and off tiles.
    static let card = Color(hex: 0x1C1C1E)
    /// Secondary buttons.
    static let secondaryButton = Color(hex: 0x2C2C2E)
    static let secondaryText = Color(white: 0.72)

    static let titleFont = Font.system(size: 18, weight: .bold)
}

extension Color {
    /// A color from a 0xRRGGBB literal.
    nonisolated init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    nonisolated init(_ rgb: RGB) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

extension LightColor {
    /// The color a lit tile or swatch is filled with: the light's color, softened a little
    /// toward white so the dark icon stays readable (as in the mockups).
    var tileColor: Color { Color(rgb.mixed(with: .white, amount: 0.25)) }
    /// The pure color, for small swatches.
    var swatchColor: Color { Color(rgb) }

    /// Dark text on light fills, white on dark ones (a saturated blue, say), for buttons
    /// filled with `tileColor`.
    var labelColor: Color {
        let c = rgb.mixed(with: .white, amount: 0.25)
        let luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return luminance > 0.55 ? Theme.onAccent : .white
    }
}

/// Fills for colors that may be a hybrid: one color, or a diagonal blend of several.
enum ColorFill {
    static func of(_ colors: [LightColor]) -> AnyShapeStyle {
        if colors.count >= 2 {
            return AnyShapeStyle(LinearGradient(colors: colors.map(\.tileColor), startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle((colors.first ?? .warmWhite).tileColor)
    }
}

extension Room {
    /// What a lit tile or swatch is filled with: the room's color, or a blend of its hybrid's colors.
    var colors: [LightColor] { mixColors ?? [displayColor] }
    var fill: AnyShapeStyle { ColorFill.of(colors) }
}

