import CoreGraphics

/// Tile sizes for the Rooms grid: 1–4 tiles = 2×2 big tiles, 5–9 = 3×3, 10 or more =
/// three across (3×3-sized tiles) and scrolling. Never four across.
nonisolated struct GridLayout: Equatable, Sendable {
    var columns: Int
    var tile: CGFloat
    var spacing: CGFloat
    var scrolls: Bool

    static func make(count: Int, width: CGFloat, height: CGFloat, spacing: CGFloat = 6) -> GridLayout {
        let columns = count <= 4 ? 2 : 3
        let rows = columns
        let byWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let byHeight = (height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        return GridLayout(columns: columns, tile: max(floor(min(byWidth, byHeight)), 20), spacing: spacing,
                          scrolls: count >= 10)
    }

    var gridWidth: CGFloat { tile * CGFloat(columns) + spacing * CGFloat(columns - 1) }

    /// Top-left corner of slot `index` within the grid.
    func origin(of index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index % columns) * (tile + spacing), y: CGFloat(index / columns) * (tile + spacing))
    }

    func frame(of index: Int) -> CGRect { CGRect(origin: origin(of: index), size: CGSize(width: tile, height: tile)) }
}
