import CoreGraphics

/// Tile sizes for the Rooms grid: 1–4 tiles = two across, 5–9 = three across, 10 or more =
/// three across and scrolling. Never four across. Tiles are as big as the rows in use allow
/// (so 5–6 rooms fill the width), and with 10+ they fill the width and scroll.
nonisolated struct GridLayout: Equatable, Sendable {
    var columns: Int
    var tile: CGFloat
    var spacing: CGFloat
    var scrolls: Bool

    /// `rows` is how many rows the arrangement uses (defaults to packing the rooms).
    static func make(count: Int, rows usedRows: Int? = nil, width: CGFloat, height: CGFloat, spacing: CGFloat = 5) -> GridLayout {
        let columns = count <= 4 ? 2 : 3
        let scrolls = count >= 10
        let rows = max(usedRows ?? Int((Double(max(count, 1)) / Double(columns)).rounded(.up)), 1)
        let byWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let byHeight = (height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        let tile = scrolls ? byWidth : min(byWidth, byHeight)
        return GridLayout(columns: columns, tile: max(floor(tile), 20), spacing: spacing, scrolls: scrolls)
    }

    var gridWidth: CGFloat { tile * CGFloat(columns) + spacing * CGFloat(columns - 1) }

    /// Top-left corner of slot `index` within the grid.
    func origin(of index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index % columns) * (tile + spacing), y: CGFloat(index / columns) * (tile + spacing))
    }

    func frame(of index: Int) -> CGRect { CGRect(origin: origin(of: index), size: CGSize(width: tile, height: tile)) }

    // MARK: Free placement (GridArrangement)

    /// Half a tile plus half a gap: the step between a column and a half-way position.
    var halfStep: CGFloat { (tile + spacing) / 2 }
    var rowStep: CGFloat { tile + spacing }

    func frame(of slot: Slot) -> CGRect {
        CGRect(x: CGFloat(slot.half) * halfStep, y: CGFloat(slot.row) * rowStep, width: tile, height: tile)
    }

    func height(rows: Int) -> CGFloat { CGFloat(max(rows, 1)) * rowStep - spacing }

    /// The slot whose centre is nearest `p` (clamped to the grid), and whether `p` is inside
    /// the middle 60% of that slot's cell (half a tile wide, a row high).
    func slot(near p: CGPoint, rows: Int) -> (slot: Slot, inMiddle: Bool) {
        let maxHalf = 2 * (columns - 1)
        let fx = (p.x - tile / 2) / halfStep
        let fy = (p.y - tile / 2) / rowStep
        let half = min(max(Int(fx.rounded()), 0), maxHalf)
        let row = min(max(Int(fy.rounded()), 0), max(rows - 1, 0))
        let inMiddle = abs(fx - CGFloat(half)) <= 0.3 && abs(fy - CGFloat(row)) <= 0.3
        return (Slot(row: row, half: half), inMiddle)
    }
}
