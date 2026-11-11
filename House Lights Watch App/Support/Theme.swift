import SwiftUI

/// Colors from SPEC.md's Look section.
nonisolated enum Theme {
    /// Amber, for back arrows, main buttons and highlights.
    static let accent = Color(hex: 0xFFB65C)
    /// Dark text drawn on amber.
    static let onAccent = Color(hex: 0x1A1400)
    static let background = Color.black
    /// Cards and off tiles.
    static let card = Color(hex: 0x1C1C1E)
    /// Secondary buttons.
    static let secondaryButton = Color(hex: 0x2C2C2E)
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
}
