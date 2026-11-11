import CoreGraphics
import Foundation

/// Drag-to-reorder for the Arrange screen, following SPEC.md's four rules (they're there
/// because reordering fought itself in Closing Time):
/// 1. The finger is hit-tested against the grid's *fixed* slot positions, never the moving tiles.
/// 2. The target slot changes only while the finger is in the middle 60% of a slot.
/// 3. The finger must stay on a new slot for ~150 ms before the other tiles move aside.
/// 4. The order is saved on release (by the view).
nonisolated struct ArrangeDrag: Sendable, Equatable {
    static let dwell: TimeInterval = 0.15
    /// Fraction of a slot, centered, that counts as "on" it (rule 2).
    static let hotFraction: CGFloat = 0.6

    let layout: GridLayout
    let draggedID: String
    private(set) var order: [String]
    /// The slot the dragged tile currently occupies.
    private(set) var target: Int
    private(set) var candidate: Int?
    private(set) var candidateSince: Date?
    private(set) var point: CGPoint

    /// Starts a drag on the slot under `point`, or nil if it isn't on a tile.
    init?(order: [String], layout: GridLayout, at point: CGPoint) {
        guard let slot = Self.slot(containing: point, layout: layout, count: order.count, hotOnly: false) else { return nil }
        self.layout = layout
        self.order = order
        self.draggedID = order[slot]
        self.target = slot
        self.point = point
    }

    /// The slot whose rectangle (or, with `hotOnly`, whose middle 60%) holds the point.
    static func slot(containing p: CGPoint, layout: GridLayout, count: Int, hotOnly: Bool) -> Int? {
        for i in 0..<count {
            var r = layout.frame(of: i)
            if hotOnly {
                let inset = r.width * (1 - hotFraction) / 2
                r = r.insetBy(dx: inset, dy: inset)
            }
            if r.contains(p) { return i }
        }
        return nil
    }

    /// The finger moved. Returns true when a new candidate slot starts its 150 ms wait.
    /// A slot becomes the candidate only from its middle 60%; it stays the candidate while
    /// the finger is anywhere on that slot, and is dropped if the finger leaves it.
    @discardableResult
    mutating func move(to p: CGPoint, now: Date) -> Bool {
        point = p
        let hot = Self.slot(containing: p, layout: layout, count: order.count, hotOnly: true)
        let on = Self.slot(containing: p, layout: layout, count: order.count, hotOnly: false)
        if let c = candidate, on != c { candidate = nil; candidateSince = nil }
        guard let hot else { return false }
        if hot == target { candidate = nil; candidateSince = nil; return false }
        guard hot != candidate else { return false }
        candidate = hot
        candidateSince = now
        return true
    }

    /// Called often while dragging (the view ticks every 30 ms): once the finger has been on
    /// the candidate slot for 150 ms, moves the dragged tile there.
    mutating func commitIfDue(now: Date) -> Bool {
        guard let c = candidate, let since = candidateSince, now.timeIntervalSince(since) >= Self.dwell - 0.001 else { return false }
        guard Self.slot(containing: point, layout: layout, count: order.count, hotOnly: false) == c else { return false }
        order.remove(at: target)
        order.insert(draggedID, at: c)
        target = c
        candidate = nil
        candidateSince = nil
        return true
    }
}

extension GridLayout {
    /// Arrange shows every tile without scrolling: the same 2- or 3-across rule as the grid,
    /// with tiles shrunk to fit when there are more than nine.
    nonisolated static func fitting(count: Int, width: CGFloat, height: CGFloat, spacing: CGFloat = 6) -> GridLayout {
        var layout = make(count: count, width: width, height: height, spacing: spacing)
        let rows = max(Int((Double(count) / Double(layout.columns)).rounded(.up)), 1)
        let byHeight = (height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        layout.tile = max(floor(min(layout.tile, byHeight)), 24)
        layout.scrolls = false
        return layout
    }

    nonisolated func height(count: Int) -> CGFloat {
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        return CGFloat(rows) * tile + CGFloat(max(rows - 1, 0)) * spacing
    }
}
