import SwiftUI

/// Arrange (mockups/6-arrange.png): the same icon grid, in the rooms' current state. Drag a
/// room to any spot — including half-way between columns — and the rooms in the way slide
/// to the nearest free spot. Nothing here changes lights. See ArrangeDrag for the rules.
struct ArrangeView: View {
    @Environment(AppModel.self) private var app
    @State private var arrangement: GridArrangement?
    @State private var drag: ArrangeDrag?

    var body: some View {
        Screen(title: "Arrange", backToGrid: true) {
            GeometryReader { geo in
                VStack(spacing: 6) {
                    if let arrangement {
                        grid(arrangement, in: CGSize(width: geo.size.width, height: geo.size.height - Self.captionHeight))
                    }
                    Text("Drag a room to any spot. Lights don’t change here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { arrangement = app.arrangement }
    }

    /// Room kept under the grid for the two-line caption.
    static let captionHeight: CGFloat = 46

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
            }
            .onEnded { _ in
                guard let finished = drag else { return }
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
