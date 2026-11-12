import SwiftUI

/// One square, rounded tile. Lit: filled with the room's color, dark icon and brightness %.
/// Off: dark gray with "Off". No name label (it's in the accessibility label).
struct RoomTile: View {
    let room: Room
    let size: CGFloat
    /// Arrange shows icons only.
    var showsLevel = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
            .fill(room.isOn ? room.fill : AnyShapeStyle(Theme.card))
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
