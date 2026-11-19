import CoreGraphics

/// The picker's grid: as many columns as fit, shrinking the tiles before it would overflow.
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
    private static let screenShare = CGSize(width: 0.92, height: 0.84)

    static func layout(tileCount: Int, screen: CGSize, showsHeader: Bool) -> Layout {
        let count = max(tileCount, 1)
        let chrome = footerHeight + (showsHeader ? headerHeight : 0)
        let available = CGSize(
            width: screen.width * screenShare.width - inset * 2,
            height: screen.height * screenShare.height - inset * 2 - chrome)
        let fitted = scales.lazy
            .map { grid(count: count, scale: $0, width: available.width) }
            .first { height(of: $0) <= available.height }
        let chosen =
            fitted ?? grid(count: count, scale: scales[scales.count - 1], width: available.width)
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

    private static func grid(count: Int, scale: CGFloat, width: CGFloat) -> Grid {
        let preview = CGSize(
            width: (fullPreview.width * scale).rounded(), height: (fullPreview.height * scale).rounded())
        let tile = CGSize(width: preview.width, height: preview.height + labelHeight)
        let fitting = max(Int((width + gap) / (tile.width + gap)), 1)
        let columns = min(count, fitting)
        return Grid(
            columns: columns, rows: (count + columns - 1) / columns, tile: tile, preview: preview)
    }

    private static func height(of grid: Grid) -> CGFloat {
        CGFloat(grid.rows) * (grid.tile.height + gap) - gap
    }
}
