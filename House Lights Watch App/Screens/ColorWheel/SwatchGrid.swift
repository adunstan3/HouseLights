import SwiftUI

/// Saved colors under the wheel, four across. Tap uses one; a 0.5 s hold removes it.
struct SwatchGrid: View {
    let swatches: [SavedSwatch]
    let selected: (hue: Double, saturation: Double)
    let highlighted: SavedSwatch.ID?
    let onTap: (SavedSwatch) -> Void
    let onRemove: (SavedSwatch) -> Void


    var body: some View {
        if swatches.isEmpty {
            Text("Tap \(Image(systemName: "pin.fill")) to save this color.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("swatchHint")
        } else {
            // Not lazy: the list is short, and every swatch stays reachable (VoiceOver, UI tests).
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(stride(from: 0, to: swatches.count, by: 4)), id: \.self) { rowStart in
                    GridRow {
                        ForEach(rowStart..<min(rowStart + 4, swatches.count), id: \.self) { index in
                            swatchView(swatches[index], index: index)
                        }
                        // Keep four columns even when the last row is short.
                        ForEach(0..<max(0, rowStart + 4 - swatches.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, minHeight: 40)
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.25), value: swatches)
        }
    }

    private func swatchView(_ swatch: SavedSwatch, index: Int) -> some View {
        let isCurrent = swatch.matches(hue: selected.hue, saturation: selected.saturation)
        return Circle()
            .fill(Color(swatch.rgb))
            .overlay(Circle().strokeBorder(.white, lineWidth: isCurrent ? 3 : 0))
            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: swatch.id == highlighted && !isCurrent ? 2 : 0).padding(-3))
            .frame(width: 36, height: 36)
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Circle())
            // The hold is tried first; a tap only counts if the finger lifts before 0.5 s.
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in onRemove(swatch) }
                    .exclusively(before: TapGesture().onEnded { onTap(swatch) })
            )
            .transition(.scale.combined(with: .opacity))
            .accessibilityElement()
            .accessibilityLabel("Saved color \(index + 1)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("swatch-\(index)")
            .accessibilityAction { onTap(swatch) }
            .accessibilityAction(named: "Remove") { onRemove(swatch) }
    }
}
