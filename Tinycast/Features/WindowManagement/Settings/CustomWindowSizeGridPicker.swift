import SwiftUI

/// Interactive Magnet-style cell matrix for dragging out exact fractional window tiles.
struct CustomWindowSizeGridPicker: View {
    enum Preset: String, CaseIterable, Identifiable {
        case sixByFour = "6×4"
        case twelveByEight = "12×8"
        case twentyFourByTwelve = "24×12"

        var id: String { rawValue }

        var columns: Int {
            switch self {
            case .sixByFour: 6
            case .twelveByEight: 12
            case .twentyFourByTwelve: 24
            }
        }

        var rows: Int {
            switch self {
            case .sixByFour: 4
            case .twelveByEight: 8
            case .twentyFourByTwelve: 12
            }
        }

        static func matching(columns: Int, rows: Int) -> Self {
            allCases.first { $0.columns == columns && $0.rows == rows } ?? .twelveByEight
        }
    }

    @Binding var selection: CustomWindowSize.GridCell
    @State private var preset: Preset
    @State private var dragStart: (col: Int, row: Int)?
    @State private var dragCurrent: (col: Int, row: Int)?

    private static let matrixHeight: CGFloat = 168
    private static let cellSpacing: CGFloat = 3

    init(selection: Binding<CustomWindowSize.GridCell>) {
        _selection = selection
        _preset = State(
            initialValue: Preset.matching(
                columns: selection.wrappedValue.gridColumns,
                rows: selection.wrappedValue.gridRows))
    }

    var body: some View {
        let active = activeCell

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Text(verbatim: "\(active.label) · \(active.positionLabel)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer(minLength: Theme.Spacing.sm)

                Picker("Grid density", selection: presetBinding) {
                    ForEach(Preset.allCases) { option in
                        Text(verbatim: option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }

            GeometryReader { proxy in
                let cols = preset.columns
                let rows = preset.rows
                let spacing = Self.cellSpacing
                let inset: CGFloat = 8
                let innerWidth = max(1, proxy.size.width - inset * 2 - spacing * CGFloat(cols - 1))
                let innerHeight = max(1, proxy.size.height - inset * 2 - spacing * CGFloat(rows - 1))
                let cellWidth = innerWidth / CGFloat(cols)
                let cellHeight = innerHeight / CGFloat(rows)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.layoutPreviewGround)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline)
                        }

                    ForEach(0..<rows, id: \.self) { row in
                        ForEach(0..<cols, id: \.self) { col in
                            let filled = isInside(col: col, row: row, cell: active)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(
                                    filled
                                        ? Color.accentColor
                                        : Theme.Colors.layoutPreviewWindow.opacity(0.32)
                                )
                                .frame(width: max(2, cellWidth), height: max(2, cellHeight))
                                .offset(
                                    x: inset + CGFloat(col) * (cellWidth + spacing),
                                    y: inset + CGFloat(row) * (cellHeight + spacing))
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let hit = cellIndex(
                                at: value.location, in: proxy.size, inset: inset,
                                columns: cols, rows: rows)
                            if dragStart == nil { dragStart = hit }
                            dragCurrent = hit
                        }
                        .onEnded { value in
                            let end = cellIndex(
                                at: value.location, in: proxy.size, inset: inset,
                                columns: cols, rows: rows)
                            let start = dragStart ?? end
                            selection = Self.makeCell(from: start, to: end, preset: preset)
                            dragStart = nil
                            dragCurrent = nil
                        }
                )
            }
            .frame(height: Self.matrixHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fractional grid")
            .accessibilityValue(Text(verbatim: "\(active.label), \(active.positionLabel)"))
        }
    }

    private var presetBinding: Binding<Preset> {
        Binding(
            get: { preset },
            set: { next in
                guard next != preset else { return }
                let old = selection
                let startCol = Int(
                    (Double(old.column) / Double(max(1, old.gridColumns)) * Double(next.columns))
                        .rounded())
                let endCol = Int(
                    (Double(old.column + old.columns) / Double(max(1, old.gridColumns))
                        * Double(next.columns)).rounded())
                let startRow = Int(
                    (Double(old.row) / Double(max(1, old.gridRows)) * Double(next.rows)).rounded())
                let endRow = Int(
                    (Double(old.row + old.rows) / Double(max(1, old.gridRows))
                        * Double(next.rows)).rounded())
                preset = next
                selection = CustomWindowSize.GridCell(
                    column: startCol, columns: max(1, endCol - startCol),
                    row: startRow, rows: max(1, endRow - startRow),
                    gridColumns: next.columns, gridRows: next.rows)
            })
    }

    private var activeCell: CustomWindowSize.GridCell {
        if let dragStart, let dragCurrent {
            return Self.makeCell(from: dragStart, to: dragCurrent, preset: preset)
        }
        return selection
    }

    private func isInside(
        col: Int, row: Int, cell: CustomWindowSize.GridCell
    ) -> Bool {
        col >= cell.column && col < cell.column + cell.columns
            && row >= cell.row && row < cell.row + cell.rows
    }

    private func cellIndex(
        at point: CGPoint, in container: CGSize, inset: CGFloat, columns: Int, rows: Int
    ) -> (col: Int, row: Int) {
        let usableWidth = max(1, container.width - inset * 2)
        let usableHeight = max(1, container.height - inset * 2)
        let fx = min(max((point.x - inset) / usableWidth, 0), 0.9999)
        let fy = min(max((point.y - inset) / usableHeight, 0), 0.9999)
        return (Int(fx * CGFloat(columns)), Int(fy * CGFloat(rows)))
    }

    private static func makeCell(
        from a: (col: Int, row: Int), to b: (col: Int, row: Int), preset: Preset
    ) -> CustomWindowSize.GridCell {
        let minCol = min(a.col, b.col)
        let maxCol = max(a.col, b.col)
        let minRow = min(a.row, b.row)
        let maxRow = max(a.row, b.row)
        return CustomWindowSize.GridCell(
            column: minCol, columns: maxCol - minCol + 1,
            row: minRow, rows: maxRow - minRow + 1,
            gridColumns: preset.columns, gridRows: preset.rows)
    }
}
