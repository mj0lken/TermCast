import SwiftUI

struct WindowPickerView: View {
    let session: WindowPickerSession
    let onOpenSettings: () -> Void
    let onPick: (Int) -> Void

    var body: some View {
        if let board = session.board, let layout = session.layout {
            VStack(spacing: 0) {
                if let stack = board.expandedStack {
                    WindowPickerStackHeader(stack: stack)
                        .frame(height: WindowPickerGeometry.headerHeight, alignment: .top)
                }
                grid(board, layout: layout)
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
                .onTapGesture { onPick(index) }
            }
        }
    }

    /// The windows behind a stack's front one, so its stack shows what it actually holds.
    private func stackThumbnails(of tile: WindowPickerBoard.Tile) -> [CGImage?] {
        guard case .stack(let stack) = tile else { return [] }
        return stack.windows.dropFirst().prefix(WindowPickerTileView.stackDepth).map {
            session.thumbnails[$0.handle]
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
