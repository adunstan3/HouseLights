import SwiftUI

/// Binds the Digital Crown to one room's brightness (Room and Color wheel screens):
/// each detent moves 5%, snapping to multiples of 5. Turning to 0 turns the room off;
/// turning up from off turns it on.
///
/// The Crown is unbounded and continuous, like the grid's, and we apply the change in each
/// turn ourselves. A bounded 0–100 Crown makes watchOS draw its green position indicator
/// on the right, as if the page were scrolling.
struct BrightnessCrown: ViewModifier {
    let roomID: String
    @Environment(AppModel.self) private var app
    @State private var crown = 0.0
    @State private var applied = 0.0
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .digitalCrownRotation($crown, from: -100_000, through: 100_000, by: 1, sensitivity: .medium,
                                  isContinuous: true, isHapticFeedbackEnabled: true)
            .digitalCrownAccessory(.hidden)
            .onAppear { focused = true }
            .onChange(of: crown) { _, value in
                let steps = Int((value - applied).rounded(.towardZero))
                guard steps != 0 else { return }
                applied += Double(steps)
                let target = Self.step(from: current, by: steps)
                if target != current { app.setBrightness(target, roomID: roomID) }
            }
    }

    /// 72% up one detent is 75%, down one is 70%.
    nonisolated static func step(from current: Double, by steps: Int) -> Double {
        let base = steps > 0 ? (current / 5).rounded(.down) : (current / 5).rounded(.up)
        return min(max((base + Double(steps)) * 5, 0), 100)
    }

    /// The brightness the Crown starts from: 0 when the room is off.
    private var current: Double {
        guard let room = app.room(roomID), room.isOn else { return 0 }
        return room.brightness.rounded()
    }
}

extension View {
    func brightnessCrown(roomID: String) -> some View { modifier(BrightnessCrown(roomID: roomID)) }
}
