import SwiftUI

/// One square, rounded tile. Lit: filled with the room's color, dark icon and brightness %.
/// Off: dark gray with "Off". No name label (it's in the accessibility label).
/// A moving hybrid's colors slowly drift around the tile.
struct RoomTile: View {
    let room: Room
    let size: CGFloat
    /// Arrange shows icons only.
    var showsLevel = true
    /// A lit moving hybrid's colors (from `AppModel.movingColors`); nil for a still fill.
    var movingColors: [Color]? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
        Group {
            if room.isOn, let movingColors { DriftingFill(colors: movingColors, shape: shape) }
            else { shape.fill(room.isOn ? room.fill : AnyShapeStyle(Theme.card)) }
        }
            .overlay {
                VStack(spacing: size * 0.03) {
                    Image(systemName: room.iconName)
                        .font(.system(size: size * 0.34, weight: .semibold))
                        .frame(height: size * 0.4)
                    if showsLevel {
                        Text(room.isOn ? "\(room.percent)%" : "Off")
                            .font(.system(size: max(size * 0.22, 13), weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .foregroundStyle(room.isOn ? Theme.onAccent : Color(white: 0.55))
            }
            .frame(width: size, height: size)
    }
}
