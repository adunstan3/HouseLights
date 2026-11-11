import SwiftUI

/// The Temporary color card: the default's swatch, and Back to default and Set as default
/// side by side. Only shown while the room's color is temporary.
struct TemporaryColorCard: View {
    let roomID: String
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.isTemporary(roomID) {
            let defaultColor = app.defaultScene(roomID)?.color
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(defaultColor?.swatchColor ?? Theme.secondaryButton)
                        .frame(width: 14, height: 14)
                    Text("Temporary")
                        .font(.footnote.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                    Text("Default \(defaultColor?.label ?? "")")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let error = app.defaultsError {
                    Text(error).font(.footnote).foregroundStyle(.red).lineLimit(1)
                }
                HStack(spacing: 5) {
                    Button("Back to default") { app.backToDefault(roomID) }
                        .buttonStyle(SmallCapsuleStyle(primary: true))
                        .disabled(app.home.defaults[roomID] == nil)
                        .accessibilityIdentifier("backToDefault")
                    Button("Set as default") { app.setAsDefault(roomID) }
                        .buttonStyle(SmallCapsuleStyle(primary: false))
                        .accessibilityIdentifier("setAsDefault")
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(Theme.card))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("temporaryCard")
        }
    }
}

/// The two half-width buttons on the Temporary color card.
struct SmallCapsuleStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            // Both labels side by side need ~195 pt at 13 pt; the card has ~175 pt on a
            // 49mm Ultra, so they shrink to about 11 pt rather than truncate.
            .minimumScaleFactor(0.78)
            .foregroundStyle(primary ? Theme.onAccent : .white)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Capsule().fill((primary ? Theme.accent : Theme.secondaryButton).opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
    }
}
