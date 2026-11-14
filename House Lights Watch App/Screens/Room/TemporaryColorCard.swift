import SwiftUI

/// Shown on the Room screen while the room's color is temporary: two tall buttons side by
/// side. "Back to default" is filled with the room's default color, "Set as default" with
/// the color the lights show now (a blend, for a hybrid). A moving hybrid's colors drift on
/// the button, as on its tile and power button.
struct TemporaryColorCard: View {
    let roomID: String
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.isTemporary(roomID), let room = app.room(roomID) {
            HStack(spacing: 6) {
                Button("Back to default") { app.backToDefault(roomID) }
                    .buttonStyle(ColorButtonStyle(colors: app.defaultScene(roomID)?.colors ?? [],
                                                  movingColors: app.movingDefaultColors(roomID)))
                    .disabled(app.home.defaults[roomID] == nil)
                    .accessibilityIdentifier("backToDefault")
                Button("Set as default") { app.setAsDefault(roomID) }
                    .buttonStyle(ColorButtonStyle(colors: room.colors, movingColors: app.movingColors(room)))
                    .accessibilityIdentifier("setAsDefault")
            }
            .overlay(alignment: .bottom) {
                if let error = app.defaultsError {
                    Text(error).font(.footnote).foregroundStyle(.red).lineLimit(1).offset(y: 18)
                }
            }
            .padding(.horizontal, 6)   // clear of the screen's rounded bottom corners
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("temporaryCard")
        }
    }
}

/// A tall rounded button filled with a light color; the label wraps onto two lines.
/// With `movingColors`, the fill slowly drifts through them (a moving hybrid).
struct ColorButtonStyle: ButtonStyle {
    let colors: [LightColor]
    var movingColors: [Color]? = nil
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .foregroundStyle(colors.first?.labelColor ?? Theme.onAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                Group {
                    if let movingColors { DriftingFill(colors: movingColors, shape: shape) }
                    else { shape.fill(colors.isEmpty ? AnyShapeStyle(Theme.accent) : ColorFill.of(colors)) }
                }
                .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.5))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
