import CoreGraphics

/// Tile sizes for the Rooms grid: 1–4 tiles = two across, 5–9 = three across, 10 or more =
/// three across and scrolling. Never four across. Tiles are as big as the rows in use allow
/// (so 5–6 rooms fill the width), and with 10+ they fill the width and scroll.
nonisolated struct GridLayout: Equatable, Sendable {
    var columns: Int
    var tile: CGFloat
    var spacing: CGFloat
    var scrolls: Bool

    static func make(count: Int, width: CGFloat, height: CGFloat, spacing: CGFloat = 5) -> GridLayout {
        let columns = count <= 4 ? 2 : 3
        let scrolls = count >= 10
        let rows = max(Int((Double(max(count, 1)) / Double(columns)).rounded(.up)), 1)
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
}
