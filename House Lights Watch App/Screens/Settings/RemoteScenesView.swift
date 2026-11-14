import SwiftUI

/// Settings › Remote scenes: tap the rooms that have a Hue dimmer switch. Each gets a
/// "House Lights Now – <room>" scene that the watch keeps up to date; set the dimmer's On
/// button to that scene in the Hue app.
struct RemoteScenesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Screen(title: "Remote scenes") {
            GeometryReader { geo in
                VStack(spacing: 6) {
                    let rooms = app.allRooms   // hidden rooms can still have a dimmer
                    let layout = GridLayout.fitting(count: rooms.count, rows: GridArrangement.baseRows(for: rooms.count),
                                                    width: geo.size.width, height: geo.size.height - Self.captionHeight)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.tile), spacing: layout.spacing), count: layout.columns),
                              spacing: layout.spacing) {
                        ForEach(rooms) { room in tile(room, size: layout.tile) }
                    }
                    .frame(width: layout.gridWidth)
                    .frame(maxWidth: .infinity)
                    Text("Tap rooms with a dimmer. Then pick “House Lights Now” for its On button in the Hue app.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    static let captionHeight: CGFloat = 52

    private func tile(_ room: Room, size: CGFloat) -> some View {
        let on = app.hasRemoteScene(room.id)
        var shown = room
        shown.isOn = on   // chosen rooms drawn lit, the rest dark
        return RoomTile(room: shown, size: size, showsLevel: false)
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white, Theme.onAccent)
                        .padding(4)
                }
            }
            .onTapGesture { app.setRemoteScene(room.id, enabled: !on) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(room.name)
            .accessibilityValue(on ? "remote scene on" : "off")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("remote-\(room.name)")
            .accessibilityAction { app.setRemoteScene(room.id, enabled: !on) }
    }
}
