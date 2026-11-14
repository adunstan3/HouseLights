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
        GeometryReader { geo in
            tiles(in: geo.size)
        }
        .overlay(alignment: .top) {
            if let pill { CrownPillView(pill: pill).padding(.top, 2) }
        }
        .padding(.horizontal, 3)
        .padding(.top, 4)
        .padding(.bottom, 9)   // keeps the bottom corner tiles inside the screen's rounded corners
        .background(Theme.background)
        .ignoresSafeArea(edges: .bottom)
        // "Lights" sits centered under the clock, between the two toolbar buttons.
        .navigationTitle("Lights")
        // System toolbar buttons sit in the top corners with the clock between them.
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: app.allOff) {
                    Image(systemName: "power").font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                }
                .tint(.white)
                .accessibilityLabel("All off")
                .accessibilityIdentifier("allOff")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.settings) } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .tint(Theme.secondaryButton)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("gear")
            }
        }
        .focusable()
        .focused($crownFocused)
        .focusEffectDisabled()
        .digitalCrownRotation($crown, from: -100_000, through: 100_000, by: 1, sensitivity: .low,
                              isContinuous: true, isHapticFeedbackEnabled: true)
        .digitalCrownAccessory(.hidden)
        .onChange(of: crown) { _, value in crownMoved(to: value) }
        .onAppear { crownFocused = true }
        .task(id: pill?.id) {
            guard pill != nil else { return }
            // `-pillSeconds 10` (debug) keeps it up long enough for UI tests to see it.
            try? await Task.sleep(for: .seconds(RuntimeEnvironment.debugValue("pillSeconds").flatMap(Double.init) ?? 1.2))
            if !Task.isCancelled { withAnimation { pill = nil } }
        }
    }

    @ViewBuilder
    private func tiles(in size: CGSize) -> some View {
        let arrangement = app.arrangement
        let count = arrangement.slots.count
        let rows = max(arrangement.rowsUsed, 1)
        let layout = GridLayout.make(count: count, rows: rows, width: size.width, height: size.height)
        // Rooms sit where Arrange put them: gaps stay, and half-way spots are allowed.
        let grid = ZStack(alignment: .topLeading) {
            ForEach(arrangement.readingOrder, id: \.self) { id in
                if let room = app.room(id), let slot = arrangement.slots[id] {
                    let f = layout.frame(of: slot)
                    TileButton(room: room, size: layout.tile, movingColors: app.movingColors(room),
                               onTap: { app.toggle(room.id) },
                               onHold: { router.push(.room(room.id)) })
                        .position(x: f.midX, y: f.midY)
                }
            }
        }
        .frame(width: layout.gridWidth, height: layout.height(rows: rows), alignment: .topLeading)
        .frame(maxWidth: .infinity)

        if count == 0, !app.hiddenRoomList.isEmpty {
            Text("Every room is hidden. Settings › Arrange rooms puts them back.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if layout.scrolls {
            // Drag to scroll. The Crown is bound to brightness above, so it can't scroll this.
            ScrollView(.vertical, showsIndicators: false) { grid.padding(.bottom, 20) }
        } else {
            grid.frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func crownMoved(to value: Double) {
        let steps = Int((value - appliedCrown).rounded(.towardZero))
        guard steps != 0 else { return }
        appliedCrown += Double(steps)
        app.crownStep(steps)
        pill = CrownPill(brighter: steps > 0, count: CrownBrightness.affected(app.gridControlledRooms))
    }
}

/// "Brighter · 4 on" / "Dimmer · 4 on", shown briefly while the Crown turns.
struct CrownPill: Equatable {
    var id = UUID()
    var brighter: Bool
    var count: Int
    var text: String { "\(brighter ? "Brighter" : "Dimmer") · \(count) on" }
}

/// The Crown feedback pill, next to the title.
private struct CrownPillView: View {
    let pill: CrownPill

    var body: some View {
        Text(pill.text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(Theme.accent))
            .shadow(color: .black.opacity(0.6), radius: 4)
            .transition(.opacity)
            .accessibilityIdentifier("crownPill")
    }
}

/// A tile that toggles on tap and opens the Room screen on a 0.5 s hold.
private struct TileButton: View {
    let room: Room
    let size: CGFloat
    var movingColors: [Color]? = nil
    let onTap: () -> Void
    let onHold: () -> Void

    var body: some View {
        RoomTile(room: room, size: size, movingColors: movingColors)
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
