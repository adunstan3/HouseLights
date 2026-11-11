import SwiftUI

/// The Room screen (mockups/2-room.png): power button, brightness % and bar (the Crown
/// sets brightness), Warmth, the Color wheel row, and — when the color is temporary —
/// the Temporary color card.
struct RoomView: View {
    let roomID: String
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    var body: some View {
        if let room = app.room(roomID) {
            Screen(title: room.name) {
                VStack(alignment: .leading, spacing: 7) {
                    RoomTopRow(room: room) { app.toggle(roomID) }
                    WarmthSlider(room: room) { app.setWarmth(kelvin: $0, roomID: roomID) }
                    ColorWheelRow(enabled: room.supportsColor) { router.push(.colorWheel(roomID)) }
                    TemporaryColorCard(roomID: roomID)
                }
            }
            .brightnessCrown(roomID: roomID)
        } else {
            Screen(title: "Room") {
                Text("This room is no longer on the bridge.").font(.footnote)
            }
        }
    }
}

/// Power button, brightness %, "Crown" hint and the brightness bar.
struct RoomTopRow: View {
    let room: Room
    let onPower: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "power")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(room.isOn ? Theme.onAccent : .white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(room.isOn ? room.displayColor.tileColor : Theme.secondaryButton))
                .padding(2)
                .contentShape(Circle())
                .onTapGesture(perform: onPower)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(room.isOn ? "Turn off" : "Turn on")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("power")
                .accessibilityAction { onPower() }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(room.isOn ? "\(room.percent)%" : "Off")
                        .font(.system(size: 26, weight: .bold))
                        .monospacedDigit()
                        .accessibilityIdentifier("brightness")
                    Spacer(minLength: 2)
                    Label("Crown", systemImage: "digitalcrown.horizontal.arrow.clockwise")
                        .labelStyle(CompactLabelStyle())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                BrightnessBar(fraction: room.isOn ? room.brightness / 100 : 0, color: room.displayColor.tileColor)
            }
        }
    }
}

struct BrightnessBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.secondaryButton)
                Capsule().fill(color).frame(width: max(geo.size.width * fraction, fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Icon and title close together, for the small "Crown" hint.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) { configuration.icon; configuration.title }
    }
}

/// The card that opens the Color wheel screen.
struct ColorWheelRow: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HueSwatch().frame(width: 22, height: 22)
            Text(enabled ? "Color wheel" : "No color bulbs")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(Theme.card))
        .opacity(enabled ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius))
        .onTapGesture { if enabled { action() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("colorWheelRow")
        .accessibilityAction { if enabled { action() } }
    }
}

/// A small rainbow disc.
struct HueSwatch: View {
    var body: some View {
        Circle().fill(AngularGradient(colors: HueWheel.hues, center: .center,
                                      startAngle: .degrees(-90), endAngle: .degrees(270)))
    }
}
