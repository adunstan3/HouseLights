import SwiftUI

/// Amber, full-width main button with dark text.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .background(Capsule().fill(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
    }
}

/// Dark gray, full-width secondary button.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .background(Capsule().fill(Theme.secondaryButton.opacity(configuration.isPressed ? 0.6 : 1)))
            .contentShape(Capsule())
    }
}
