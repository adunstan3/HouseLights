import SwiftUI

/// A moving hybrid's fill: its colors in a soft gradient that slowly turns, so the tile or
/// button drifts the way the bulbs do. Still (a plain blend) with Reduce Motion on.
struct DriftingFill<S: Shape>: View {
    let colors: [Color]
    let shape: S
    /// Seconds for one full turn.
    var period: Double = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || colors.count < 2 {
            shape.fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                shape.fill(gradient(at: context.date.timeIntervalSinceReferenceDate))
            }
        }
    }

    /// A linear gradient whose direction turns once per `period`, wrapping back to the first
    /// color so no hard edge shows as it turns.
    private func gradient(at t: Double) -> LinearGradient {
        let angle = (t / period).truncatingRemainder(dividingBy: 1) * 2 * .pi
        let dx = cos(angle) * 0.5, dy = sin(angle) * 0.5
        return LinearGradient(colors: colors + [colors[0]],
                              startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                              endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}
