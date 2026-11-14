import SwiftUI
import WatchKit

/// Arrange (mockups/6-arrange.png): the same icon grid, in the rooms' current state. Drag a
/// room to any spot — including half-way between columns — and the rooms in the way slide
/// to the nearest free spot. Nothing here changes lights. See ArrangeDrag for the rules.
/// Under the grid is Hidden rooms: drag a room down onto it to hide it from the grid. Scroll
/// down (Crown or drag below the grid) to the hidden rooms; hold one to put it back on the
/// grid in the first free spot.
struct ArrangeView: View {
    @Environment(AppModel.self) private var app
    @State private var arrangement: GridArrangement?
    @State private var drag: ArrangeDrag?
    /// The dragged room is over Hidden rooms: letting go hides it.
    @State private var overHidden = false

    @Environment(Router.self) private var router

    // A scrolling screen, so it uses the system bar like the Color screen (a scroll view
    // moves the clock to the middle, over a custom header). Back still goes to the grid.
    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    if let arrangement {
                        grid(arrangement, in: CGSize(width: geo.size.width, height: geo.size.height - Self.dropZoneHeight - 6))
                            .zIndex(1)   // the dragged tile draws over Hidden rooms
                    }
                    hiddenHeader
                    hiddenList(width: geo.size.width)
                }
                .padding(.bottom, 24)
            }
            .scrollDisabled(drag != nil)
        }
        .padding(.horizontal, Metrics.sideMargin)
        .background(Theme.background)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Arrange")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.popToRoot() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("back")
            }
        }
        .onAppear { arrangement = app.arrangement }
    }

    /// Height of the Hidden rooms drop zone, which sits under the grid on the first screen.
    static let dropZoneHeight: CGFloat = 40

    private var hiddenHeader: some View {
        VStack(spacing: 1) {
            Text("Hidden rooms")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(overHidden ? Theme.accent : .white)
            Text(overHidden ? "Let go to hide it" : drag != nil ? "Drop here to hide" : "Drag a room here to hide it")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: Self.dropZoneHeight)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(overHidden ? Theme.accent : Color(white: 0.3),
                              style: StrokeStyle(lineWidth: overHidden ? 2 : 1, dash: overHidden ? [] : [4, 3]))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hiddenRooms")
    }

    @ViewBuilder
    private func hiddenList(width: CGFloat) -> some View {
        let hidden = app.hiddenRoomList
        if !hidden.isEmpty {
            let tile = floor((width - 2 * 8) / 3)
            // Three across, built eagerly (a lazy grid leaves off-screen rooms out of the
            // accessibility tree until scrolled to).
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(stride(from: 0, to: hidden.count, by: 3)), id: \.self) { start in
                    HStack(spacing: 8) {
                        ForEach(hidden[start..<min(start + 3, hidden.count)]) { room in hiddenTile(room, size: tile) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            Text("Hold a hidden room to put it back.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        Text("Lights don’t change here.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
    }

    private func hiddenTile(_ room: Room, size: CGFloat) -> some View {
        VStack(spacing: 2) {
            RoomTile(room: room, size: size, showsLevel: false)
                .opacity(0.7)
            Text(room.name)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: size)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) { show(room.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(room.name)
        .accessibilityHint("Hold to put it back on the grid")
        .accessibilityAction(named: "Show on grid") { show(room.id) }
        .accessibilityIdentifier("hidden-\(room.name)")
    }

    private func show(_ id: String) {
        WKInterfaceDevice.current().play(.success)
        withAnimation(.spring(duration: 0.25)) {
            app.showRoom(id)
            arrangement = app.arrangement
        }
    }

    private func hide(_ id: String, from saved: GridArrangement) {
        WKInterfaceDevice.current().play(.directionDown)
        withAnimation(.spring(duration: 0.25)) {
            app.hideRoom(id, from: saved)
            arrangement = app.arrangement
        }
    }

    private func grid(_ saved: GridArrangement, in size: CGSize) -> some View {
        let count = saved.slots.count
        let rows = max(GridArrangement.baseRows(for: count), saved.rowsUsed)
        let layout = GridLayout.fitting(count: count, rows: rows, width: size.width, height: size.height)
        let shown = drag?.arrangement ?? saved
        let order = shown.readingOrder
        return ZStack(alignment: .topLeading) {
            // Faint outlines of the full-column spots, so empty places are visible.
            ForEach(0..<rows, id: \.self) { row in
                ForEach(Array(stride(from: 0, through: saved.maxHalf, by: 2)), id: \.self) { half in
                    let f = layout.frame(of: Slot(row: row, half: half))
                    RoundedRectangle(cornerRadius: layout.tile * 0.21, style: .continuous)
                        .strokeBorder(Color(white: 0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: f.width, height: f.height)
                        .position(x: f.midX, y: f.midY)
                }
            }
            ForEach(order, id: \.self) { id in
                if let room = app.room(id), let slot = shown.slots[id] {
                    let dragging = drag?.draggedID == id
                    let f = layout.frame(of: slot)
                    RoomTile(room: room, size: layout.tile, showsLevel: false)
                        .overlay {
                            if dragging {
                                RoundedRectangle(cornerRadius: layout.tile * 0.21, style: .continuous)
                                    .strokeBorder(.white, lineWidth: 2)
                            }
                        }
                        .scaleEffect(dragging ? 1.1 : 1)
                        .position(dragging ? drag!.point : CGPoint(x: f.midX, y: f.midY))
                        .zIndex(dragging ? 1 : 0)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(room.name)
                        .accessibilityValue("position \((order.firstIndex(of: id) ?? 0) + 1) of \(order.count)")
                        .accessibilityIdentifier("arrange-\(room.name)")
                        .accessibilityAdjustableAction { direction in
                            move(id, by: direction == .increment ? 1 : -1, in: saved)
                        }
                        .accessibilityAction(named: "Hide") { hide(id, from: saved) }
                }
            }
        }
        .frame(width: layout.gridWidth, height: layout.height(rows: rows), alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(dragGesture(saved, layout: layout, rows: rows))
        .animation(.spring(duration: 0.25), value: drag?.arrangement)
        .frame(maxWidth: .infinity, alignment: .top)
        .task(id: drag?.draggedID) {
            // While a room is held, check every 30 ms whether it has waited long enough on a
            // new spot. (The finger can sit still, so this can't wait for drag events.)
            while drag != nil, !Task.isCancelled {
                _ = drag!.commitIfDue(now: .now)
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private func dragGesture(_ saved: GridArrangement, layout: GridLayout, rows: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if drag == nil {
                    drag = ArrangeDrag(arrangement: saved, layout: layout, rows: rows, at: g.startLocation)
                }
                guard drag != nil else { return }
                drag!.move(to: g.location, now: .now)
                // Below the grid is the Hidden rooms drop zone.
                let over = g.location.y > layout.height(rows: rows) + 3
                if over != overHidden {
                    overHidden = over
                    if over { WKInterfaceDevice.current().play(.click) }
                }
            }
            .onEnded { _ in
                guard let finished = drag else { return }
                if overHidden {
                    overHidden = false
                    drag = nil
                    hide(finished.draggedID, from: finished.start)   // the others stay where they were
                    return
                }
                withAnimation(.spring(duration: 0.25)) {
                    arrangement = finished.arrangement
                    drag = nil
                }
                app.saveArrangement(finished.arrangement)
            }
    }

    /// VoiceOver: swipe up/down on a room to swap it with the next or previous one.
    private func move(_ id: String, by offset: Int, in saved: GridArrangement) {
        let order = saved.readingOrder
        guard let i = order.firstIndex(of: id), order.indices.contains(i + offset),
              let mine = saved.slots[id], let theirs = saved.slots[order[i + offset]] else { return }
        var next = saved
        next.slots[id] = theirs
        next.slots[order[i + offset]] = mine
        arrangement = next
        app.saveArrangement(next)
    }
}
