import SwiftUI

/// Arrange (mockups/6-arrange.png): the same icon grid, in the rooms' current state;
/// dragging reorders it and nothing here changes lights. See ArrangeDrag for the rules.
struct ArrangeView: View {
    @Environment(AppModel.self) private var app
    @State private var order: [String] = []
    @State private var drag: ArrangeDrag?

    var body: some View {
        Screen(title: "Arrange", backToGrid: true) {
            GeometryReader { geo in
                VStack(spacing: 6) {
                    grid(in: CGSize(width: geo.size.width, height: geo.size.height - Self.captionHeight))
                    Text("Drag a tile to move it. Lights don’t change here.")
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
        .onAppear { order = app.rooms.map(\.id) }
    }

    /// Room kept under the grid for the two-line caption.
    static let captionHeight: CGFloat = 46

    private func grid(in size: CGSize) -> some View {
        let rooms = order.compactMap { app.room($0) }
        let layout = GridLayout.fitting(count: rooms.count, width: size.width, height: size.height)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                let dragging = drag?.draggedID == room.id
                let slot = layout.frame(of: index)
                RoomTile(room: room, size: layout.tile, showsLevel: false)
                    .overlay {
                        if dragging {
                            RoundedRectangle(cornerRadius: layout.tile * 0.21, style: .continuous)
                                .strokeBorder(.white, lineWidth: 2)
                        }
                    }
                    .scaleEffect(dragging ? 1.1 : 1)
                    .position(dragging ? drag!.point : CGPoint(x: slot.midX, y: slot.midY))
                    .zIndex(dragging ? 1 : 0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(room.name)
                    .accessibilityValue("position \(index + 1) of \(rooms.count)")
                    .accessibilityIdentifier("arrange-\(room.name)")
                    .accessibilityAdjustableAction { direction in
                        move(room.id, by: direction == .increment ? 1 : -1)
                    }
            }
        }
        .frame(width: layout.gridWidth, height: layout.height(count: rooms.count), alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(dragGesture(layout))
        .animation(.spring(duration: 0.25), value: order)
        .task(id: drag?.draggedID) {
            // While a tile is held, check every 30 ms whether it has waited long enough on a
            // new slot. (The finger can sit still, so this can't wait for drag events.)
            while drag != nil, !Task.isCancelled {
                if drag!.commitIfDue(now: .now) { order = drag!.order }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func dragGesture(_ layout: GridLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if drag == nil {
                    drag = ArrangeDrag(order: order, layout: layout, at: g.startLocation)
                }
                guard drag != nil else { return }
                drag!.move(to: g.location, now: .now)
            }
            .onEnded { _ in
                guard let finished = drag else { return }
                withAnimation(.spring(duration: 0.25)) {
                    order = finished.order
                    drag = nil
                }
                app.saveOrder(order)
            }
    }

    /// VoiceOver: swipe up/down on a tile to move it.
    private func move(_ id: String, by offset: Int) {
        guard let i = order.firstIndex(of: id) else { return }
        let j = min(max(i + offset, 0), order.count - 1)
        guard i != j else { return }
        order.remove(at: i)
        order.insert(id, at: j)
        app.saveOrder(order)
    }
}
