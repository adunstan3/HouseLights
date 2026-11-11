import SwiftUI

/// Settings: Arrange rooms and Bridge (matching mockups/5-settings.png).
struct SettingsView: View {
    @Environment(Router.self) private var router

    var body: some View {
        Screen(title: "Settings") {
            VStack(spacing: 8) {
                SettingsRow(icon: "square.grid.2x2", title: "Arrange rooms", subtitle: "Order of the grid") {
                    router.push(.arrange)
                }
                SettingsRow(icon: "dot.square", title: "Bridge", subtitle: "IP address and pairing") {
                    router.push(.bridge)
                }
            }
        }
    }
}

/// A card row with an icon, two lines of text and a chevron. Uses a tap gesture rather
/// than a Button so rows never share a tap target.
struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.secondaryButton))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(Theme.card))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius))
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
