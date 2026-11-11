import SwiftUI

/// Binds the Digital Crown to one room's brightness (Room and Color wheel screens).
/// Turning to 0 turns the room off; turning up from off turns it on.
struct BrightnessCrown: ViewModifier {
    let roomID: String
    @Environment(AppModel.self) private var app
    @State private var value = 0.0
    @State private var lastTurn = Date.distantPast
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .digitalCrownRotation($value, from: 0, through: 100, by: 1, sensitivity: .medium,
                                  isContinuous: false, isHapticFeedbackEnabled: true)
            .onAppear {
                value = current
                focused = true
            }
            .onChange(of: value) { _, new in
                guard abs(new - current) >= 0.5 else { return }   // ignore our own sync below
                lastTurn = .now
                app.setBrightness(new, roomID: roomID)
            }
            .onChange(of: current) { _, new in
                // Follow changes from elsewhere (event stream, power button), but not while turning.
                if Date().timeIntervalSince(lastTurn) > 1.5 { value = new }
            }
    }

    private var current: Double {
        guard let room = app.room(roomID), room.isOn else { return 0 }
        return room.brightness.rounded()
    }
}

extension View {
    func brightnessCrown(roomID: String) -> some View { modifier(BrightnessCrown(roomID: roomID)) }
}
