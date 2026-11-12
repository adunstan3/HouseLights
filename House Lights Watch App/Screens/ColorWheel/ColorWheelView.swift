import SwiftUI
import WatchKit

/// The Color wheel screen: the largest wheel that fits and a pin button (right of the clock)
/// that saves the current color. Saved colors sit below the wheel, four across; turn the
/// Crown or drag the page to scroll to them. Tap a swatch to use it, hold it to remove it.
/// Brightness is set on the Room screen. The color is sent when the finger lifts.
struct ColorWheelView: View {
    let roomID: String
    @Environment(AppModel.self) private var app
    @State private var knob: (hue: Double, saturation: Double)?
    @State private var justPinned: SavedSwatch.ID?

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { scroller in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        let d = min(geo.size.width, geo.size.height) - 4
                        wheel(diameter: d)
                            .frame(width: geo.size.width, height: d)
                        SwatchGrid(swatches: app.savedSwatches, selected: current, highlighted: justPinned,
                                   onTap: use, onRemove: remove)
                            .id("swatches")
                    }
                    .padding(.bottom, 24)
                }
                .onAppear {
                    if RuntimeEnvironment.flag("scrollSwatches") { scroller.scrollTo("swatches", anchor: .top) }
                }
            }
        }
        .padding(.horizontal, 6)
        .background(Theme.background)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Color")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: pin) {
                    Image(systemName: "pin.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                .tint(Theme.secondaryButton)
                .accessibilityLabel("Save this color")
                .accessibilityIdentifier("pinColor")
            }
        }
    }

    /// The knob's color: where the finger last left it, or the room's current color.
    private var current: (hue: Double, saturation: Double) {
        knob ?? app.room(roomID).map { WheelMath.hueSaturation(of: $0.displayColor) } ?? (0, 0)
    }

    private func wheel(diameter d: CGFloat) -> some View {
        let r = d / 2
        let center = CGPoint(x: r, y: r)
        let current = self.current
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
        // Dragging on the wheel picks a color; dragging anywhere else scrolls the page.
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

    private func pin() {
        let hs = current
        let added = app.pinSwatch(hue: hs.hue, saturation: hs.saturation)
        WKInterfaceDevice.current().play(added ? .success : .click)
        justPinned = app.savedSwatches.first { $0.matches(hue: hs.hue, saturation: hs.saturation) }?.id
        app.log.add(.info, added ? "Saved a color" : "That color is already saved")
    }

    private func use(_ swatch: SavedSwatch) {
        knob = (swatch.hue, swatch.saturation)
        send((swatch.hue, swatch.saturation))
    }

    private func remove(_ swatch: SavedSwatch) {
        WKInterfaceDevice.current().play(.directionDown)
        withAnimation { app.removeSwatch(swatch.id) }
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
