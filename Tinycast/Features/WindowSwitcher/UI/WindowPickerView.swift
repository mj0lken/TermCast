import SwiftUI

struct WindowPickerView: View {
    let session: WindowPickerSession
    let groups: WindowPickerGroupStore
    let onOpenSettings: () -> Void
    let onPick: (Int) -> Void
    let onDrop: (Int, WindowPickerBoard.Drop) -> Void
    let onMoveSection: (Int, Int) -> Void

    /// The tile or the whole outline under the pointer mid-drag, and how far it has come.
    private struct Drag: Equatable {
        var isSection = false
        let index: Int
        var translation: CGSize
        var location: CGPoint
    }

    @State private var drag: Drag?
    private static let boardSpace = "windowPickerBoard"

    var body: some View {
        if let board = session.board, let layout = session.layout {
            VStack(spacing: 0) {
                if let stack = board.expandedStack {
                    WindowPickerStackHeader(stack: stack)
                        .frame(height: WindowPickerGeometry.headerHeight, alignment: .top)
                }
                if layout.tileFrames.count == board.tiles.count, !board.sections.isEmpty {
                    groups(board, layout: layout)
                } else {
                    grid(board, layout: layout)
                }
                WindowPickerFooter(query: board.query, onOpenSettings: onOpenSettings)
                    .frame(height: WindowPickerGeometry.footerHeight, alignment: .bottom)
            }
            .padding(WindowPickerGeometry.inset)
            .frame(width: layout.panel.width, height: layout.panel.height)
            .background(Theme.Colors.panelScrim)
            .background(GlassEffectView())
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .animation(.easeOut(duration: Theme.Duration.exit), value: board.selection)
        }
    }

    private func grid(_ board: WindowPickerBoard, layout: WindowPickerGeometry.Layout) -> some View {
        let columns = Array(
            repeating: GridItem(.fixed(layout.tile.width), spacing: WindowPickerGeometry.gap),
            count: layout.columns)
        return LazyVGrid(columns: columns, spacing: WindowPickerGeometry.gap) {
            ForEach(Array(board.tiles.enumerated()), id: \.element.id) { index, tile in
                tileView(tile, at: index, board: board, layout: layout)
                    .onTapGesture { onPick(index) }
            }
        }
    }

    private func tileView(
        _ tile: WindowPickerBoard.Tile, at index: Int, board: WindowPickerBoard,
        layout: WindowPickerGeometry.Layout
    ) -> some View {
        WindowPickerTileView(
            tile: tile, preview: layout.preview,
            thumbnail: tile.target.flatMap { session.thumbnails[$0.handle] },
            stackThumbnails: stackThumbnails(of: tile),
            number: index < WindowPickerTileView.numberedTiles ? index + 1 : nil,
            isSelected: index == board.selection
        )
        .opacity(board.isDimmed(tile) ? 0.3 : 1)
        .frame(width: layout.tile.width, height: layout.tile.height)
        .contentShape(Rectangle())
    }

    // MARK: - Groups

    /// Placed by frame rather than by a grid, so a drop can be matched to what lies under it.
    private func groups(
        _ board: WindowPickerBoard, layout: WindowPickerGeometry.Layout
    ) -> some View {
        let target = dropTarget(in: layout)
        let landing = sectionTarget(in: layout)
        let owners = board.sections.enumerated().flatMap { Array(repeating: $0.offset, count: $0.element.count) }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(board.sections.enumerated()), id: \.element.group) { index, section in
                if layout.sectionFrames.indices.contains(index) {
                    let frame = layout.sectionFrames[index]
                    let moved = sectionShift(index)
                    WindowPickerSectionOutline(
                        title: groups.title(for: section.group),
                        tint: groups.book.tint(for: section.group).color,
                        isTargeted: target == .section(index) || landing == index
                    )
                    .frame(width: frame.width, height: frame.height)
                    .contentShape(Rectangle())
                    .offset(x: frame.minX + moved.width, y: frame.minY + moved.height)
                    .zIndex(moved == .zero ? 0 : 1)
                    .gesture(sectionGesture(for: index, in: layout))
                }
            }
            ForEach(Array(board.tiles.enumerated()), id: \.element.id) { index, tile in
                let frame = layout.tileFrames[index]
                let isDragged = drag?.isSection == false && drag?.index == index
                let carried = sectionShift(owners.indices.contains(index) ? owners[index] : -1)
                let moved = isDragged ? drag?.translation ?? .zero : carried
                tileView(tile, at: index, board: board, layout: layout)
                    .overlay {
                        if target == .tile(index) {
                            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))
                        }
                    }
                    .scaleEffect(isDragged ? 0.92 : 1)
                    .offset(x: frame.minX + moved.width, y: frame.minY + moved.height)
                    .zIndex(moved == .zero ? 0 : 2)
                    .onTapGesture { onPick(index) }
                    .gesture(dragGesture(for: index, in: layout))
            }
        }
        .frame(
            width: layout.panel.width - WindowPickerGeometry.inset * 2,
            height: layout.panel.height - WindowPickerGeometry.inset * 2
                - WindowPickerGeometry.footerHeight,
            alignment: .topLeading
        )
        .coordinateSpace(.named(Self.boardSpace))
    }

    private func dragGesture(
        for index: Int, in layout: WindowPickerGeometry.Layout
    ) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.boardSpace))
            .onChanged { value in
                drag = Drag(index: index, translation: value.translation, location: value.location)
            }
            .onEnded { value in
                drag = Drag(index: index, translation: value.translation, location: value.location)
                let target = dropTarget(in: layout)
                drag = nil
                if let target { onDrop(index, target) }
            }
    }

    private func sectionShift(_ index: Int) -> CGSize {
        guard let drag, drag.isSection, drag.index == index else { return .zero }
        return drag.translation
    }

    private func sectionGesture(
        for index: Int, in layout: WindowPickerGeometry.Layout
    ) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.boardSpace))
            .onChanged { value in
                drag = Drag(
                    isSection: true, index: index, translation: value.translation,
                    location: value.location)
            }
            .onEnded { value in
                drag = Drag(
                    isSection: true, index: index, translation: value.translation,
                    location: value.location)
                let landing = sectionTarget(in: layout)
                drag = nil
                if let landing { onMoveSection(index, landing) }
            }
    }

    /// The outline a dragged one would take the place of.
    private func sectionTarget(in layout: WindowPickerGeometry.Layout) -> Int? {
        guard let drag, drag.isSection else { return nil }
        return layout.sectionFrames.enumerated().first {
            $0.offset != drag.index && $0.element.contains(drag.location)
        }?.offset
    }

    /// A tile wins over the outline it sits in; past every outline the window is dragged out.
    private func dropTarget(in layout: WindowPickerGeometry.Layout) -> WindowPickerBoard.Drop? {
        guard let drag, !drag.isSection else { return nil }
        let tile = layout.tileFrames.enumerated().first {
            $0.offset != drag.index && $0.element.contains(drag.location)
        }
        if let tile { return .tile(tile.offset) }
        let section = layout.sectionFrames.firstIndex { $0.contains(drag.location) }
        return section.map { .section($0) } ?? .outside
    }

    /// The windows behind a stack's front one, so its stack shows what it actually holds.
    private func stackThumbnails(of tile: WindowPickerBoard.Tile) -> [CGImage?] {
        guard case .stack(let stack) = tile else { return [] }
        return stack.windows.dropFirst().prefix(WindowPickerTileView.stackDepth).map {
            session.thumbnails[$0.handle]
        }
    }
}

private struct WindowPickerSectionOutline: View {
    let title: String
    let tint: Color
    let isTargeted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row + 4, style: .continuous)
        shape.fill(tint.opacity(isTargeted ? 0.22 : 0.1))
            .overlay {
                shape.strokeBorder(
                    isTargeted ? Color.accentColor : tint.opacity(0.4),
                    lineWidth: isTargeted ? 2 : 1)
            }
            .overlay(alignment: .topLeading) {
                Text(verbatim: title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, WindowPickerGeometry.sectionPadding)
                    .frame(height: WindowPickerGeometry.sectionTitleHeight + 4, alignment: .bottom)
            }
            .accessibilityLabel(title)
    }
}

extension WindowPickerGroupTint {
    /// Automatic never reaches a view: the book resolves it to one of these first.
    var color: Color {
        switch self {
        case .automatic, .gray: .gray
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}

private struct WindowPickerStackHeader: View {
    let stack: WindowPickerBoard.Stack

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            WindowPickerAppIcon(iconURL: stack.iconURL, iconStamp: stack.iconStamp)
                .frame(width: 20, height: 20)
            Text(verbatim: stack.appName)
                .font(Theme.Typography.panelTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("\(stack.windows.count) windows")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The search as typed, and the way to Settings, where the keys are listed.
private struct WindowPickerFooter: View {
    let query: String
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if !query.isEmpty {
                Label {
                    Text(verbatim: query)
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "gearshape")
                .font(.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(Theme.Spacing.xs)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenSettings)
                .accessibilityLabel("Settings")
                .accessibilityAddTraits(.isButton)
        }
    }
}

private struct WindowPickerAppIcon: View {
    let iconURL: URL?
    let iconStamp: Int

    var body: some View {
        if let iconURL {
            EntryIconView(source: .file(stamp: iconStamp), fileURL: iconURL)
        } else {
            EntryIconView(source: .symbol("macwindow"))
        }
    }
}

private struct WindowPickerTileView: View {
    let tile: WindowPickerBoard.Tile
    let preview: CGSize
    let thumbnail: CGImage?
    let stackThumbnails: [CGImage?]
    let number: Int?
    let isSelected: Bool

    /// The digit row reaches nine tiles; the rest are walked to.
    static let numberedTiles = 9
    static let stackDepth = 2
    private static let stackStep: CGFloat = 9
    private static let badgeIcon: CGFloat = 26
    private static let numberSize: CGFloat = 20

    private var entry: WindowSwitchEntry? { tile.target }

    private var stackCount: Int? {
        if case .stack(let stack) = tile { return stack.windows.count }
        return nil
    }

    private var title: String {
        switch tile {
        case .window(let entry): entry.displayTitle
        case .stack(let stack): stack.appName
        }
    }

    private var accessibilityValue: String {
        switch tile {
        case .window(let entry):
            entry.isMinimized ? String(localized: "\(entry.appName) · Minimized") : entry.appName
        case .stack(let stack): String(localized: "\(stack.windows.count) windows")
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            previewStack
                .frame(width: preview.width, height: preview.height)
            Text(verbatim: title)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .opacity(entry?.isMinimized == true ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// A stack always reserves the full stack, so its front card is one size whatever it holds.
    private var previewStack: some View {
        let inset = stackCount == nil ? 0 : Self.stackStep * CGFloat(Self.stackDepth)
        let card = CGSize(width: preview.width - inset, height: preview.height - inset)
        return ZStack(alignment: .bottomLeading) {
            ForEach(Array(stackThumbnails.enumerated().reversed()), id: \.offset) { depth, image in
                let shift = Self.stackStep * CGFloat(depth + 1)
                backCard(image, depth: depth)
                    .frame(width: card.width, height: card.height)
                    .offset(x: shift, y: -shift)
            }
            frontCard
                .frame(width: card.width, height: card.height)
        }
        .frame(width: preview.width, height: preview.height, alignment: .bottomLeading)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
    }

    private var frontCard: some View {
        shape.fill(.regularMaterial)
            .overlay { shape.fill(isSelected ? Theme.Colors.selection : Theme.Colors.cardFill) }
            .overlay { content(thumbnail) }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? Color.accentColor : Theme.Colors.cardStroke,
                    lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .topLeading) { numberBadge }
            .overlay(alignment: .bottomLeading) { badge }
            .shadow(color: .black.opacity(stackCount == nil ? 0 : 0.35), radius: 5, x: 2, y: -2)
    }

    private func backCard(_ image: CGImage?, depth: Int) -> some View {
        shape.fill(.regularMaterial)
            .overlay { shape.fill(Theme.Colors.cardFill) }
            .overlay { content(image, showsIcon: false).opacity(0.7) }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1) }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: -2)
            .opacity(depth == 0 ? 0.9 : 0.7)
    }

    @ViewBuilder
    private func content(_ image: CGImage?, showsIcon: Bool = true) -> some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .padding(Theme.Spacing.xs)
        } else if showsIcon, let entry {
            WindowPickerAppIcon(iconURL: entry.iconURL, iconStamp: entry.iconStamp)
                .frame(width: preview.height * 0.5, height: preview.height * 0.5)
        }
    }

    @ViewBuilder
    private var numberBadge: some View {
        if let number {
            Text(verbatim: String(number))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Theme.Colors.textPrimary)
                .frame(width: Self.numberSize, height: Self.numberSize)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else {
                        Circle().fill(.regularMaterial)
                    }
                }
                .padding(Theme.Spacing.xs)
        }
    }

    private var badge: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if thumbnail != nil, let entry {
                WindowPickerAppIcon(iconURL: entry.iconURL, iconStamp: entry.iconStamp)
                    .frame(width: Self.badgeIcon, height: Self.badgeIcon)
            }
            if let stackCount {
                Text("\(stackCount) windows")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(Capsule().fill(.regularMaterial))
            }
        }
        .padding(Theme.Spacing.xs)
    }
}
