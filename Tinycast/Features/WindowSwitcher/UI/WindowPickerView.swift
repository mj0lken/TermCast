import SwiftUI

struct WindowPickerView: View {
    let session: WindowPickerSession
    let onPick: (Int) -> Void

    var body: some View {
        if let board = session.board, let layout = session.layout {
            VStack(spacing: 0) {
                if let group = board.expandedGroup {
                    WindowPickerGroupHeader(group: group)
                        .frame(height: WindowPickerGeometry.headerHeight, alignment: .top)
                }
                grid(board, layout: layout)
                WindowPickerHints(board: board)
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
                    isSelected: index == board.selection
                )
                .frame(width: layout.tile.width, height: layout.tile.height)
                .contentShape(Rectangle())
                .onTapGesture { onPick(index) }
            }
        }
    }
}

private struct WindowPickerGroupHeader: View {
    let group: WindowPickerBoard.Group

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            WindowPickerAppIcon(iconURL: group.iconURL, iconStamp: group.iconStamp)
                .frame(width: 20, height: 20)
            Text(verbatim: group.appName)
                .font(Theme.Typography.panelTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("\(group.windows.count) windows")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WindowPickerHints: View {
    let board: WindowPickerBoard

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            if board.expandedGroup != nil {
                hint("Right ⇧ closes the group")
            } else if board.allowsGrouping {
                hint(board.isGrouped ? "Left ⇧ shows every window" : "Left ⇧ groups by app")
                if board.isGrouped { hint("Right ⇧ opens a group") }
            }
            hint("W closes, Q quits, H hides")
        }
        .frame(maxWidth: .infinity)
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
            .lineLimit(1)
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
    let isSelected: Bool

    private static let stackOffset: CGFloat = 5
    private static let badgeIcon: CGFloat = 26

    private var entry: WindowSwitchEntry? { tile.target }

    private var groupCount: Int? {
        if case .group(let group) = tile { return group.windows.count }
        return nil
    }

    private var title: String {
        switch tile {
        case .window(let entry): entry.displayTitle
        case .group(let group): group.appName
        }
    }

    private var accessibilityValue: String {
        switch tile {
        case .window(let entry):
            entry.isMinimized ? String(localized: "\(entry.appName) · Minimized") : entry.appName
        case .group(let group): String(localized: "\(group.windows.count) windows")
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

    private var previewStack: some View {
        let stacked = groupCount != nil
        let inset = stacked ? Self.stackOffset * 2 : 0
        return ZStack(alignment: .bottomLeading) {
            if stacked {
                card.padding(.leading, inset).padding(.bottom, inset).opacity(0.35)
                card.padding(Self.stackOffset).opacity(0.6)
            }
            card
                .overlay { content }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        isSelected ? Color.accentColor : Theme.Colors.cardStroke,
                        lineWidth: isSelected ? 3 : 1)
                }
                .padding(.trailing, inset)
                .padding(.top, inset)
            badge
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
    }

    private var card: some View {
        shape.fill(isSelected ? Theme.Colors.selection : Theme.Colors.cardFill)
    }

    @ViewBuilder
    private var content: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .scaledToFit()
                .padding(Theme.Spacing.xs)
        } else if let entry {
            WindowPickerAppIcon(iconURL: entry.iconURL, iconStamp: entry.iconStamp)
                .frame(width: preview.height * 0.5, height: preview.height * 0.5)
        }
    }

    @ViewBuilder
    private var badge: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if thumbnail != nil, let entry {
                WindowPickerAppIcon(iconURL: entry.iconURL, iconStamp: entry.iconStamp)
                    .frame(width: Self.badgeIcon, height: Self.badgeIcon)
            }
            if let groupCount {
                Text(verbatim: String(groupCount))
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
