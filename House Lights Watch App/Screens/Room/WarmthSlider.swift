import SwiftUI

/// "WARMTH 3400K" over a warm-to-cool gradient track with a white knob. Drag to change;
/// the sender throttles what reaches the bridge to the latest value once a second.
struct WarmthSlider: View {
    let room: Room
    let onChange: (Int) -> Void
    @State private var dragKelvin: Int?

    private var kelvin: Int? { dragKelvin ?? room.color?.kelvin }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("WARMTH")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(room.supportsWarmth ? kelvin.map(WarmthScale.label) ?? "Color" : "—")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("warmthValue")
            }
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: Self.track, startPoint: .leading, endPoint: .trailing))
                        .frame(height: 10)
                    if let kelvin {
                        Circle()
                            .fill(.white)
                            .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                            .frame(width: 20, height: 20)
                            .offset(x: (width - 20) * WarmthScale.fraction(ofKelvin: kelvin))
                    }
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let k = WarmthScale.kelvin(atFraction: (g.location.x - 10) / max(width - 20, 1))
                            if k != dragKelvin { dragKelvin = k; onChange(k) }
                        }
                        .onEnded { _ in dragKelvin = nil }
                )
            }
            .frame(height: 20)
        }
        .disabled(!room.supportsWarmth)
        .opacity(room.supportsWarmth ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Warmth")
        .accessibilityValue(kelvin.map { "\($0) kelvin" } ?? "color")
        .accessibilityIdentifier("warmth")
        .accessibilityAdjustableAction { direction in
            let k = kelvin ?? 2700
            onChange(min(max(k + (direction == .increment ? 300 : -300), WarmthScale.range.lowerBound), WarmthScale.range.upperBound))
        }
    }

    /// 2200 K amber through warm white to 6500 K. Cool white looks nearly white on screen,
    /// so the cool end gets a light blue tint, as in the mockup.
    static let track: [Color] = [ColorMath.rgb(kelvin: 2200), ColorMath.rgb(kelvin: 3400), ColorMath.rgb(kelvin: 5000)]
        .map { Color($0.mixed(with: .white, amount: 0.2)) } + [Color(hex: 0xC9D8FF)]
}
