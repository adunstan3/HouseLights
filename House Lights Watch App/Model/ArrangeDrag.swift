import CoreGraphics
import Foundation

/// Drag-to-place on the Arrange screen. Rooms can go anywhere on the grid, including half-way
/// between columns, and the rooms in the way slide to the nearest free spot. The rules that
/// keep it from fighting itself (SPEC.md › Arrange drag rules):
/// 1. The finger is hit-tested against the grid's *fixed* slot positions, never the moving tiles.
/// 2. A slot becomes the target only while the finger is in the middle 60% of its cell.
/// 3. The finger must stay on a new slot for ~150 ms before the other tiles move aside.
/// 4. The arrangement is saved on release (by the view).
/// The other rooms are always placed from the arrangement at the start of the drag, so a room
/// passed over on the way returns to where it was.
nonisolated struct ArrangeDrag: Sendable, Equatable {
    static let dwell: TimeInterval = 0.15

    let layout: GridLayout
    let rows: Int
    let start: GridArrangement
    let draggedID: String
    /// Where the dragged room will land.
    private(set) var target: Slot
    /// The arrangement shown while dragging (dragged room at `target`, others moved aside).
    private(set) var arrangement: GridArrangement
    private(set) var candidate: Slot?
    private(set) var candidateSince: Date?
    private(set) var point: CGPoint

    /// Starts a drag on the room whose tile is under `point`, or nil if there isn't one.
    init?(arrangement: GridArrangement, layout: GridLayout, rows: Int, at point: CGPoint) {
        guard let hit = arrangement.slots.first(where: { layout.frame(of: $0.value).contains(point) }) else { return nil }
        self.layout = layout
        self.rows = rows
        self.start = arrangement
        self.draggedID = hit.key
        self.target = hit.value
        self.arrangement = arrangement
        self.point = point
    }

    /// The finger moved. Returns true when a new candidate slot starts its 150 ms wait.
    @discardableResult
    mutating func move(to p: CGPoint, now: Date) -> Bool {
        point = p
        let (slot, inMiddle) = layout.slot(near: p, rows: rows)
        if let c = candidate, slot != c { candidate = nil; candidateSince = nil }   // left the candidate
        guard inMiddle else { return false }
        if slot == target { candidate = nil; candidateSince = nil; return false }
        guard slot != candidate else { return false }
        candidate = slot
        candidateSince = now
        return true
    }

    /// Called often while dragging: once the finger has stayed on the candidate for 150 ms,
    /// the dragged room takes it and the rooms in the way move to the nearest free spots.
    mutating func commitIfDue(now: Date) -> Bool {
        guard let c = candidate, let since = candidateSince, now.timeIntervalSince(since) >= Self.dwell - 0.001,
              layout.slot(near: point, rows: rows).slot == c else { return false }
        target = c
        arrangement = start.placing(draggedID, at: c, rows: rows)
        candidate = nil
        candidateSince = nil
        return true
    }
}

extension GridLayout {
    /// Arrange shows every spot you can drag to without scrolling: the same two- or
    /// three-across tiles, shrunk to fit `rows` rows.
    nonisolated static func fitting(count: Int, rows: Int, width: CGFloat, height: CGFloat, spacing: CGFloat = 6) -> GridLayout {
        var layout = make(count: count, rows: rows, width: width, height: height, spacing: spacing)
        let byHeight = (height - spacing * CGFloat(rows - 1)) / CGFloat(max(rows, 1))
        layout.tile = max(floor(min(layout.tile, byHeight)), 24)
        layout.scrolls = false
        return layout
    }
}
