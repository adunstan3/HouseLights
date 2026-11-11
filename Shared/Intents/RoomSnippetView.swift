import SwiftUI

/// The Siri result: the room's icon, name and new state, with a brightness bar when on.
struct RoomSnippetView: View {
    enum Action { case on, off, brightness, warmth }
    let room: Room
    let action: Action

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(room.isOn ? Theme.onAccent : Color(white: 0.6))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(room.isOn ? room.displayColor.tileColor : Theme.secondaryButton))
                VStack(alignment: .leading, spacing: 0) {
                    Text(room.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(state)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.secondaryButton)
                    Rectangle().fill(Theme.accent).frame(width: geo.size.width * (room.isOn ? room.brightness / 100 : 0))
                }
            }
            .frame(height: 4)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var state: String {
        switch action {
        case .off: "Turned off"
        case .on: "Turned on · \(room.percent)%"
        case .brightness: "\(room.percent)%"
        case .warmth: room.color?.label ?? "\(room.percent)%"
        }
    }
}
