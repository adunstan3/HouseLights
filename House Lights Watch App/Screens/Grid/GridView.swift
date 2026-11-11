import SwiftUI

/// The Rooms grid (home): title, all-off and Settings buttons, one tile per room and zone.
/// Tap toggles; a 0.5 s hold opens the Room screen. The Crown brightens or dims every
/// room that's on. With 10+ rooms the grid scrolls by dragging; the Crown never scrolls it.
struct GridView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var crown = 0.0
    @State private var appliedCrown = 0.0
    @State private var pill: CrownPill?
    @FocusState private var crownFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScreenHeader(title: "House Lights", showsBack: false)
            GridButtonRow(pill: pill, onAllOff: app.allOff, onSettings: { router.push(.settings) })
            GeometryReader { geo in
                tiles(in: geo.size)
            }
        }
        .padding(.horizontal, Metrics.sideMargin)
        .padding(.top, Metrics.headerTop)
        .padding(.bottom, 6)
        .background(Theme.background)
        .ignoresSafeArea(edges: [.top, .bottom])
        .toolbar(.hidden, for: .navigationBar)
        .focusable()
        .focused($crownFocused)
        .focusEffectDisabled()
        .digitalCrownRotation($crown, from: -100_000, through: 100_000, by: 1, sensitivity: .low,
                              isContinuous: true, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in crownMoved(to: value) }
        .onAppear { crownFocused = true }
        .task(id: pill?.id) {
            guard pill != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { withAnimation { pill = nil } }
        }
    }

    @ViewBuilder
    private func tiles(in size: CGSize) -> some View {
        let rooms = app.rooms
        let layout = GridLayout.make(count: rooms.count, width: size.width, height: size.height)
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.tile), spacing: layout.spacing), count: layout.columns),
                             spacing: layout.spacing) {
            ForEach(rooms) { room in
                TileButton(room: room, size: layout.tile,
                           onTap: { app.toggle(room.id) },
                           onHold: { router.push(.room(room.id)) })
            }
        }
        .frame(width: layout.gridWidth)
        .frame(maxWidth: .infinity)

        if layout.scrolls {
            // Drag to scroll. The Crown is bound to brightness above, so it can't scroll this.
            ScrollView(.vertical, showsIndicators: false) { grid.padding(.bottom, 20) }
                .scrollDisabled(false)
        } else {
            grid.frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func crownMoved(to value: Double) {
        let steps = Int((value - appliedCrown).rounded(.towardZero))
        guard steps != 0 else { return }
        appliedCrown += Double(steps)
        app.crownStep(steps)
        pill = CrownPill(brighter: steps > 0, count: CrownBrightness.affected(app.home.rooms))
    }
}

/// "Brighter · 4 on" / "Dimmer · 4 on", shown briefly while the Crown turns.
struct CrownPill: Equatable {
    var id = UUID()
    var brighter: Bool
    var count: Int
    var text: String { "\(brighter ? "Brighter" : "Dimmer") · \(count) on" }
}

/// The row under the clock: the Crown pill on the left, all-off and Settings on the right.
private struct GridButtonRow: View {
    let pill: CrownPill?
    let onAllOff: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let pill {
                Text(pill.text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(Theme.accent))
                    .transition(.opacity)
                    .accessibilityIdentifier("crownPill")
            }
            Spacer(minLength: 0)
            RoundIconButton(systemName: "power", fill: .white, foreground: .black, label: "All off", id: "allOff", action: onAllOff)
            RoundIconButton(systemName: "gearshape.fill", fill: Theme.secondaryButton, foreground: .white,
                            label: "Settings", id: "gear", action: onSettings)
        }
        .frame(height: 30)
    }
}

/// A 30 pt round button with a 44 pt tap area, as a tap gesture so it never shares a target.
struct RoundIconButton: View {
    let systemName: String
    let fill: Color
    let foreground: Color
    let label: String
    let id: String
    let action: () -> Void

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: 30, height: 30)
            .background(Circle().fill(fill))
            .padding(4)
            .contentShape(Rectangle())
            .padding(-4)
            .onTapGesture(perform: action)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(id)
            .accessibilityAction { action() }
    }
}

/// A tile that toggles on tap and opens the Room screen on a 0.5 s hold.
private struct TileButton: View {
    let room: Room
    let size: CGFloat
    let onTap: () -> Void
    let onHold: () -> Void

    var body: some View {
        RoomTile(room: room, size: size)
            .contentShape(RoundedRectangle(cornerRadius: size * 0.21))
            // The hold is tried first; the tap only counts if the hold fails (released before
            // 0.5 s), so one touch never does both.
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in onHold() }
                    .exclusively(before: TapGesture().onEnded { onTap() })
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(room.name)
            .accessibilityValue(room.isOn ? "\(room.percent) percent" : "Off")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("tile-\(room.name)")
            .accessibilityAction { onTap() }
            .accessibilityAction(named: "Open \(room.name)") { onHold() }
    }
}
