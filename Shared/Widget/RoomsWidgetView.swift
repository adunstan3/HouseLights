import AppIntents
import SwiftUI

/// The Smart Stack widget (mockups/8-smart-stack-widget.png): "HOUSE LIGHTS" and 2–4 round
/// toggles, in the room's color when on and gray when off. Each runs ToggleRoomIntent
/// without opening the app. Shows the last-known state; it doesn't poll.
struct RoomsWidgetView: View {
    let rooms: [Room]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("HOUSE LIGHTS")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                Text("Tap to toggle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if rooms.isEmpty {
                Text("Edit the widget to choose rooms.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 2) {
                    ForEach(rooms) { room in
                        Button(intent: ToggleRoomIntent(roomID: room.id)) {
                            RoomToggle(room: room, compact: rooms.count > 3)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

private struct RoomToggle: View {
    let room: Room
    let compact: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "lightbulb")
                .font(.system(size: compact ? 15 : 17, weight: .semibold))
                .foregroundStyle(room.isOn ? Theme.onAccent : Color(white: 0.6))
                .frame(width: compact ? 32 : 36, height: compact ? 32 : 36)
                .background(Circle().fill(room.isOn ? room.fill : AnyShapeStyle(Theme.secondaryButton)))
            Text(room.shortName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(room.name)
        .accessibilityValue(room.isOn ? "on" : "off")
        .accessibilityAddTraits(.isButton)
    }
}

/// Which rooms the widget shows: the configured ones in their last-known state, or the
/// first three in grid order before it's configured.
nonisolated enum WidgetRooms {
    static func resolve(configured: [String]?, store: SharedStore = SharedStore()) -> [Room] {
        let known = GridOrder.apply(store.gridOrder, to: store.lastKnownRooms)
        guard let configured, !configured.isEmpty else { return Array(known.prefix(3)) }
        return Array(configured.compactMap { id in known.first { $0.id == id } }.prefix(4))
    }
}
