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
                VStack(alignment: .leading, spacing: 6) {
                    RoomTopRow(room: room, movingColors: app.movingColors(room), onPower: { app.toggle(roomID) },
                               onBrightness: { app.setBrightness($0, roomID: roomID) })
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

/// Power button, brightness %, and the brightness slider (drag it, or turn the Crown).
struct RoomTopRow: View {
    let room: Room
    /// A lit moving hybrid's colors: the power button drifts through them.
    var movingColors: [Color]? = nil
    let onPower: () -> Void
    let onBrightness: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "power")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(room.isOn ? Theme.onAccent : .white)
                .frame(width: 36, height: 36)
                .background {
                    if room.isOn, let movingColors { DriftingFill(colors: movingColors, shape: Circle()) }
                    else { Circle().fill(room.isOn ? room.fill : AnyShapeStyle(Theme.secondaryButton)) }
                }
                .padding(2)
                .contentShape(Circle())
                .onTapGesture(perform: onPower)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(room.isOn ? "Turn off" : "Turn on")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("power")
                .accessibilityAction { onPower() }
            VStack(alignment: .leading, spacing: 4) {
                Text(room.isOn ? "\(room.percent)%" : "Off")
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .accessibilityIdentifier("brightness")
                BrightnessSlider(value: room.isOn ? room.brightness : 0, color: room.displayColor.tileColor,
                                 onChange: onBrightness)
            }
        }
    }
}

/// The brightness bar, which also works as a slider: drag along it to set brightness
/// (1% steps; all the way left turns the room off).
struct BrightnessSlider: View {
    let value: Double
    let color: Color
    let onChange: (Double) -> Void
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let shown = dragValue ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.secondaryButton).frame(height: 8)
                Capsule().fill(color).frame(width: max((width - 16) * shown / 100 + 8, shown > 0 ? 8 : 0), height: 8)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                    .frame(width: 16, height: 16)
                    .offset(x: (width - 16) * shown / 100)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = (min(max((g.location.x - 8) / max(width - 16, 1), 0), 1) * 100).rounded()
                        if v != dragValue { dragValue = v; onChange(v) }
                    }
                    .onEnded { _ in dragValue = nil }
            )
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(value)) percent")
        .accessibilityIdentifier("brightnessSlider")
        .accessibilityAdjustableAction { direction in
            onChange(BrightnessCrown.step(from: value, by: direction == .increment ? 1 : -1))
        }
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
        .frame(height: 34)
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
