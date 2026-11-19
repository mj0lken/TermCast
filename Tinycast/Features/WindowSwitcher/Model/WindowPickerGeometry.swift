import CoreGraphics

/// The picker's grid: as many columns as fit or are allowed, shrinking tiles before it overflows.
enum WindowPickerGeometry {
    struct Layout: Equatable, Sendable {
        let columns: Int
        let rows: Int
        let tile: CGSize
        let preview: CGSize
        let panel: CGSize
        /// Groups mode only, relative to the grid's own corner; empty when the grid is uniform.
        var tileFrames: [CGRect] = []
        var sectionFrames: [CGRect] = []
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

    // MARK: - Groups

    static let sectionPadding: CGFloat = 10
    static let sectionTitleHeight: CGFloat = 20
    static let sectionGap: CGFloat = 14

    /// Each section is an outlined box of its own tiles; boxes flow left to right and wrap.
    static func groupLayout(
        sectionSizes: [Int], screen: CGSize, limits: Limits = Limits()
    ) -> Layout {
        let available = CGSize(
            width: screen.width * limits.widthShare - inset * 2,
            height: screen.height * limits.heightShare - inset * 2 - footerHeight)
        let flows = scales.map {
            flow(sectionSizes, scale: $0 * limits.tileScale, width: available.width, limits: limits)
        }
        let chosen = flows.first { $0.size.height <= available.height } ?? flows[flows.count - 1]
        return Layout(
            columns: 1, rows: 1, tile: chosen.tile, preview: chosen.preview,
            panel: CGSize(
                width: chosen.size.width + inset * 2,
                height: chosen.size.height + inset * 2 + footerHeight),
            tileFrames: chosen.tiles, sectionFrames: chosen.sections)
    }

    private struct Flow {
        let tile: CGSize
        let preview: CGSize
        var size: CGSize = .zero
        var tiles: [CGRect] = []
        var sections: [CGRect] = []
    }

    private static func flow(
        _ sizes: [Int], scale: CGFloat, width: CGFloat, limits: Limits
    ) -> Flow {
        let preview = preview(tileScale: scale)
        let tile = CGSize(width: preview.width, height: preview.height + labelHeight)
        var flow = Flow(tile: tile, preview: preview)
        let widest = max(Int((width - sectionPadding * 2 + gap) / (tile.width + gap)), 1)
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var lines: [[Int]] = [[]]
        var tileRanges: [Range<Int>] = []
        for count in sizes.map({ max($0, 1) }) {
            // Near-square by default, so a big group does not become one long ribbon.
            let square = Int(Double(count).squareRoot().rounded(.up))
            let columns = min(count, limits.maxColumns > 0 ? limits.maxColumns : square, widest)
            let rows = (count + columns - 1) / columns
            let box = CGSize(
                width: CGFloat(columns) * (tile.width + gap) - gap + sectionPadding * 2,
                height: CGFloat(rows) * (tile.height + gap) - gap + sectionPadding * 2
                    + sectionTitleHeight)
            if origin.x > 0, origin.x + box.width > width {
                origin = CGPoint(x: 0, y: origin.y + lineHeight + sectionGap)
                lineHeight = 0
                lines.append([])
            }
            lines[lines.count - 1].append(flow.sections.count)
            flow.sections.append(CGRect(origin: origin, size: box))
            let first = flow.tiles.count
            for index in 0..<count {
                flow.tiles.append(
                    CGRect(
                        x: origin.x + sectionPadding + CGFloat(index % columns) * (tile.width + gap),
                        y: origin.y + sectionPadding + sectionTitleHeight
                            + CGFloat(index / columns) * (tile.height + gap),
                        width: tile.width, height: tile.height))
            }
            tileRanges.append(first..<flow.tiles.count)
            flow.size.width = max(flow.size.width, origin.x + box.width)
            lineHeight = max(lineHeight, box.height)
            flow.size.height = origin.y + lineHeight
            origin.x += box.width + sectionGap
        }
        level(&flow, lines: lines, tileRanges: tileRanges)
        return flow
    }

    /// Boxes on one line share its height, and a short line sits centred under the widest.
    private static func level(_ flow: inout Flow, lines: [[Int]], tileRanges: [Range<Int>]) {
        for line in lines {
            guard let last = line.last else { continue }
            let height = line.map { flow.sections[$0].height }.max() ?? 0
            let shift = ((flow.size.width - flow.sections[last].maxX) / 2).rounded()
            for section in line {
                flow.sections[section].size.height = height
                flow.sections[section].origin.x += shift
                for tile in tileRanges[section] { flow.tiles[tile].origin.x += shift }
            }
        }
    }

    /// The nearest tile lying in a direction, for arrows over boxes that share no grid.
    static func neighbor(
        of index: Int, _ direction: WindowPickerKeyEngine.Direction, in frames: [CGRect]
    ) -> Int? {
        guard frames.indices.contains(index) else { return nil }
        let from = CGPoint(x: frames[index].midX, y: frames[index].midY)
        let candidates = frames.enumerated().compactMap { other, frame -> (Int, CGFloat)? in
            let along: CGFloat
            let across: CGFloat
            switch direction {
            case .left: (along, across) = (from.x - frame.midX, abs(frame.midY - from.y))
            case .right: (along, across) = (frame.midX - from.x, abs(frame.midY - from.y))
            case .up: (along, across) = (from.y - frame.midY, abs(frame.midX - from.x))
            case .down: (along, across) = (frame.midY - from.y, abs(frame.midX - from.x))
            }
            // Sideways distance counts double, so a tile straight ahead beats a nearer diagonal.
            return other != index && along > 1 ? (other, along + across * 2) : nil
        }
        return candidates.min { $0.1 < $1.1 }?.0
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
