import SwiftUI

/// The Color wheel screen: back arrow, the Crown brightness readout, and the largest wheel
/// that fits. The color is sent when the finger lifts, not on every movement.
struct ColorWheelView: View {
    let roomID: String
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var knob: (hue: Double, saturation: Double)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ScreenHeader(title: "Color") { router.pop() }
                    .padding(.trailing, -Metrics.clockClearance)
                Spacer(minLength: 4)
                Label(app.room(roomID).map { $0.isOn ? "\($0.percent)%" : "Off" } ?? "",
                      systemImage: "digitalcrown.horizontal.arrow.clockwise")
                    .labelStyle(CompactLabelStyle())
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("wheelBrightness")
            }
            .padding(.trailing, Metrics.clockClearance)
            GeometryReader { geo in
                let d = min(geo.size.width, geo.size.height)
                wheel(diameter: d)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .padding(.horizontal, Metrics.sideMargin)
        .padding(.top, Metrics.headerTop)
        .padding(.bottom, 8)
        .background(Theme.background)
        .ignoresSafeArea(edges: [.top, .bottom])
        .toolbar(.hidden, for: .navigationBar)
        .brightnessCrown(roomID: roomID)
    }

    private func wheel(diameter d: CGFloat) -> some View {
        let r = d / 2
        let center = CGPoint(x: r, y: r)
        let current = knob ?? app.room(roomID).map { WheelMath.hueSaturation(of: $0.displayColor) } ?? (0, 0)
        let knobPoint = WheelMath.point(hue: current.hue, saturation: current.saturation, center: center, radius: r)
        let knobColor = Color(ColorMath.rgb(hue: current.hue, saturation: current.saturation))
        return ZStack {
            HueWheel(diameter: d)
            Circle()
                .fill(knobColor)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .overlay(Circle().strokeBorder(.black, lineWidth: 1).padding(-1))
                .frame(width: 26, height: 26)
                .position(knobPoint)
                .allowsHitTesting(false)
        }
        .frame(width: d, height: d)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in knob = WheelMath.hueSaturation(at: g.location, center: center, radius: r) }
                .onEnded { g in
                    let hs = WheelMath.hueSaturation(at: g.location, center: center, radius: r)
                    knob = hs
                    send(hs)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Color wheel")
        .accessibilityIdentifier("wheel")
    }

    private func send(_ hs: (hue: Double, saturation: Double)) {
        guard let room = app.room(roomID) else { return }
        app.setColor(WheelMath.xy(hue: hs.hue, saturation: hs.saturation, gamut: room.gamut), roomID: roomID)
    }
}

/// Hue around the rim (red at the top, clockwise), fading to white at the center.
struct HueWheel: View {
    static let hues: [Color] = [.red, .yellow, .green, .cyan, .blue, Color(red: 1, green: 0, blue: 1), .red]
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(AngularGradient(colors: Self.hues, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
            .overlay(Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center,
                                                  startRadius: 0, endRadius: diameter / 2)))
            .frame(width: diameter, height: diameter)
    }
}
