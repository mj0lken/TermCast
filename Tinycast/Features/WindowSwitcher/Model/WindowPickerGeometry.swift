import CoreGraphics

/// The picker's grid: as many columns as fit or are allowed, shrinking tiles before it overflows.
enum WindowPickerGeometry {
    struct Layout: Equatable, Sendable {
        let columns: Int
        let rows: Int
        let tile: CGSize
        let preview: CGSize
        let panel: CGSize
    }

    static let gap: CGFloat = 12
    static let inset: CGFloat = 20
    static let labelHeight: CGFloat = 30
    static let headerHeight: CGFloat = 34
    static let footerHeight: CGFloat = 30
    static let fullPreview = CGSize(width: 208, height: 130)
    private static let scales: [CGFloat] = [1, 0.85, 0.7, 0.55, 0.42]

    /// What Settings may constrain. A column or row limit of zero is automatic.
    struct Limits: Equatable, Sendable {
        var maxColumns = 0
        var maxRows = 0
        var widthShare: CGFloat = 0.9
        var heightShare: CGFloat = 0.8
        var tileScale: CGFloat = 1
    }

    static func preview(tileScale: CGFloat) -> CGSize {
        CGSize(
            width: (fullPreview.width * tileScale).rounded(),
            height: (fullPreview.height * tileScale).rounded())
    }

    /// Rows past `maxRows` still appear when the columns run out.
    static func layout(
        tileCount: Int, screen: CGSize, showsHeader: Bool, limits: Limits = Limits()
    ) -> Layout {
        let count = max(tileCount, 1)
        let chrome = footerHeight + (showsHeader ? headerHeight : 0)
        let available = CGSize(
            width: screen.width * limits.widthShare - inset * 2,
            height: screen.height * limits.heightShare - inset * 2 - chrome)
        let grids = scales.map {
            grid(count: count, scale: $0 * limits.tileScale, width: available.width, limits: limits)
        }
        let fitting = grids.filter { height(of: $0) <= available.height }
        let chosen =
            fitting.first { limits.maxRows <= 0 || $0.rows <= limits.maxRows } ?? fitting.first
            ?? grids[grids.count - 1]
        let width = CGFloat(chosen.columns) * (chosen.tile.width + gap) - gap + inset * 2
        return Layout(
            columns: chosen.columns, rows: chosen.rows, tile: chosen.tile, preview: chosen.preview,
            panel: CGSize(width: width, height: height(of: chosen) + inset * 2 + chrome))
    }

    private struct Grid {
        let columns: Int
        let rows: Int
        let tile: CGSize
        let preview: CGSize
    }

    private static func grid(count: Int, scale: CGFloat, width: CGFloat, limits: Limits) -> Grid {
        let preview = preview(tileScale: scale)
        let tile = CGSize(width: preview.width, height: preview.height + labelHeight)
        let fitting = max(Int((width + gap) / (tile.width + gap)), 1)
        let columns = min(count, fitting, limits.maxColumns > 0 ? limits.maxColumns : .max)
        return Grid(
            columns: columns, rows: (count + columns - 1) / columns, tile: tile, preview: preview)
    }

    private static func height(of grid: Grid) -> CGFloat {
        CGFloat(grid.rows) * (grid.tile.height + gap) - gap
    }
}
