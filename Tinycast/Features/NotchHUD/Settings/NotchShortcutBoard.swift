import SwiftUI

/// A replica of the open notch above the unused shortcuts; a drop rearranges the real header.
struct NotchShortcutBoard: View {
    @Environment(AppSettings.self) private var settings

    @State private var held: NotchShortcut?

    private static let barHeight: CGFloat = 32
    private static let trayWidth: CGFloat = 540
    private static let trayPageHeight: CGFloat = 22
    private static let cutoutWidth: CGFloat = 72
    private static let cutoutHeight: CGFloat = 18
    private static let trayCornerRadius: CGFloat = 14
    private static let zoneInset: CGFloat = 3
    private static let rowTitleWidth: CGFloat = 150
    private static let slotSize = NotchHeaderMetrics.buttonSize
    private static let dragPollInterval = Duration.milliseconds(80)

    private typealias Zone = NotchShortcutLayout.Zone

    /// Only what the tray can draw; a shortcut whose feature is off is left off the board.
    private var layout: NotchShortcutLayout {
        NotchShortcut.allCases.filter { !settings.isAvailable($0) }
            .reduce(settings.notchShortcutLayout) { $0.removing($1) }
    }

    private var unused: [NotchShortcut] { layout.unused.filter(settings.isAvailable) }

    /// True while the held shortcut can only enter `zone` by replacing one in it.
    private func swapsHeld(in zone: Zone) -> Bool {
        guard let held else { return false }
        return !layout.hasRoom(for: held, in: zone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            screen
            hiddenRow
            if Zone.allCases.contains(where: swapsHeld) {
                Label(
                    "Full places swap: drop on the one to replace, and it goes back to its list.",
                    systemImage: "arrow.left.arrow.right"
                )
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .animation(.easeOut(duration: 0.15), value: held)
        .task(id: held) {
            // SwiftUI reports no end of a drag, so the held button is the only sign of one.
            guard held != nil else { return }
            while NSEvent.pressedMouseButtons != 0 {
                guard (try? await Task.sleep(for: Self.dragPollInterval)) != nil else { return }
            }
            held = nil
        }
    }

    // MARK: - The replica

    private var screen: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Theme.Radius.row, topTrailingRadius: Theme.Radius.row, style: .continuous)
        return ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.32), Color.accentColor.opacity(0.08)],
                startPoint: .top, endPoint: .bottom)
            Rectangle().fill(.regularMaterial)
                .frame(height: Self.barHeight)
                .frame(maxHeight: .infinity, alignment: .top)
            tray
        }
        .frame(height: Self.barHeight + Self.trayPageHeight + Theme.Spacing.lg * 2)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: Theme.Size.hairline))
    }

    private var tray: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: Self.trayCornerRadius, bottomTrailingRadius: Self.trayCornerRadius,
            style: .continuous)
        return NotchShortcutDropZone(drop: add) { isLit in
            VStack(spacing: 0) {
                header
                page
            }
            .frame(maxWidth: Self.trayWidth)
            .background(shape.fill(.black))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.accentColor.opacity(isLit ? 1 : 0), lineWidth: 2))
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: NotchHeaderMetrics.tabSpacing) {
                    ForEach(["house.fill", "tray.fill", "apple.terminal.fill"], id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, NotchHeaderMetrics.tabPadding)
                            .frame(height: NotchHeaderMetrics.buttonSize)
                            .background(Capsule().fill(.white.opacity(symbol == "house.fill" ? 0.3 : 0)))
                    }
                }
                .foregroundStyle(.white.opacity(0.35))
                .padding(.leading, NotchHeaderMetrics.edgeInset)
                .accessibilityHidden(true)
                Spacer(minLength: 0)
                group(.beforeNotch)
            }
            .frame(maxWidth: .infinity)

            Capsule()
                .fill(.white.opacity(0.08))
                .frame(width: Self.cutoutWidth, height: Self.cutoutHeight)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                group(.afterNotch)
                Spacer(minLength: 0)
                group(.row).padding(.trailing, NotchHeaderMetrics.edgeInset - Theme.Spacing.xs)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: Self.barHeight)
    }

    /// One zone's shortcuts and its free places; every zone lights the same way while one is held.
    private func group(_ zone: Zone) -> some View {
        let shortcuts = layout[zone]
        let shape = Capsule()
        let isOffered = held != nil
        return NotchShortcutDropZone { place($0, in: zone, before: nil) } content: { isLit in
            HStack(spacing: 0) {
                ForEach(shortcuts, id: \.self) { tile($0, in: zone) }
                ForEach(0..<max(zone.capacity - shortcuts.count, 0), id: \.self) { _ in
                    slot(isOffered: isOffered)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .background(
                shape.fill(Color.accentColor.opacity(isLit ? 0.5 : isOffered ? 0.3 : 0))
                    .padding(.vertical, Self.zoneInset)
            )
            .overlay(
                shape.strokeBorder(Color.accentColor.opacity(isOffered ? 1 : 0), lineWidth: 1.5)
                    .padding(.vertical, Self.zoneInset)
            )
            .animation(.snappy(duration: 0.25), value: shortcuts)
        }
    }

    private func slot(isOffered: Bool) -> some View {
        Circle()
            .strokeBorder(
                isOffered ? Color.accentColor : Color.white.opacity(0.3),
                style: StrokeStyle(lineWidth: isOffered ? 1.5 : 1, dash: [3, 3])
            )
            .background(Circle().fill(Color.accentColor.opacity(isOffered ? 0.25 : 0)))
            .frame(width: Self.slotSize, height: Self.slotSize)
            .padding(.horizontal, NotchHeaderMetrics.shortcutSpacing / 2)
            .accessibilityHidden(true)
    }

    /// Two faint bars where the tray's page would be, and the name of the group above them.
    private var page: some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
        }
        .foregroundStyle(.white.opacity(0.07))
        .overlay(alignment: .trailing) {
            Text("Notch Shortcuts")
                .font(.caption2)
                .foregroundStyle(.white.opacity(held == nil ? 0.45 : 0.9))
                .padding(.trailing, Theme.Spacing.md)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Self.trayPageHeight)
    }

    // MARK: - The unused shortcuts

    private var hiddenRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Label("Hidden Shortcuts", systemImage: "square.grid.2x2")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Self.rowTitleWidth, alignment: .leading)
            NotchShortcutDropZone { shortcut in
                settings.notchShortcutLayout = layout.removing(shortcut)
                return true
            } content: { isLit in
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                HStack(spacing: 0) {
                    if unused.isEmpty {
                        Text("Drag a shortcut here to take it out of the notch.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(unused, id: \.self) { tile($0, in: nil) }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: Self.barHeight + Theme.Spacing.xs, alignment: .leading)
                .background(shape.fill(.quaternary.opacity(isLit ? 1 : 0.5)))
                .overlay(
                    shape.strokeBorder(
                        isLit || held != nil ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                        style: StrokeStyle(lineWidth: isLit ? 2 : 1, dash: [4, 3])))
            }
        }
    }

    // MARK: - Tiles

    /// `zone` is nil for a shortcut that is not in the header.
    private func tile(_ shortcut: NotchShortcut, in zone: Zone?) -> some View {
        let isOverLimit = zone == .row && !drawnRow.contains(shortcut)
        return NotchShortcutTile(
            shortcut: shortcut,
            name: isOverLimit
                ? String(localized: "\(shortcut.title) has no room in the header.") : shortcut.title,
            tint: zone == nil ? .primary : .white,
            isDimmed: isOverLimit,
            isSwapTarget: zone.map(swapsHeld) ?? false,
            ringSize: zone == nil ? nil : Self.slotSize,
            height: Self.barHeight,
            onDrag: { held = shortcut }
        ) { dropped in
            guard let zone, dropped != shortcut else { return false }
            return place(dropped, in: zone, before: shortcut)
                || apply(layout.replacing(shortcut, with: dropped))
        } menu: {
            if zone == nil {
                Button("Add") { add(shortcut) }
                    .disabled(!Zone.allCases.contains { layout.hasRoom(for: shortcut, in: $0) })
            } else {
                Button("Remove") { settings.notchShortcutLayout = layout.removing(shortcut) }
            }
        }
    }

    private func place(_ shortcut: NotchShortcut, in zone: Zone, before anchor: NotchShortcut?) -> Bool {
        apply(layout.placing(shortcut, in: zone, before: anchor))
    }

    /// Into the row while it has room, then beside the cutout.
    @discardableResult
    private func add(_ shortcut: NotchShortcut) -> Bool {
        let zones: [Zone] = [.row, .afterNotch, .beforeNotch]
        return zones.contains { place(shortcut, in: $0, before: nil) }
    }

    private func apply(_ next: NotchShortcutLayout?) -> Bool {
        guard let next else { return false }
        settings.notchShortcutLayout = next
        return true
    }

    /// The row as the tray draws it: cut to the room the battery and the cutout's side leave.
    private var drawnRow: [NotchShortcut] {
        NotchShortcut.visible(
            layout.row, showsBattery: settings.notchShowsBattery, reserved: layout.afterNotch.count,
            isAvailable: { _ in true })
    }
}

/// An area that takes a dropped shortcut and lights while one hovers.
private struct NotchShortcutDropZone<Content: View>: View {
    let drop: (NotchShortcut) -> Bool
    @ViewBuilder let content: (Bool) -> Content

    @State private var isTargeted = false

    var body: some View {
        content(isTargeted)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { dropped, _ in
                guard let shortcut = dropped.first.flatMap(NotchShortcut.init(rawValue:)) else { return false }
                return drop(shortcut)
            } isTargeted: {
                isTargeted = $0
            }
            .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

/// One draggable shortcut; another dropped on it lands before it, or replaces it in a full header.
private struct NotchShortcutTile<MenuContent: View>: View {
    let shortcut: NotchShortcut
    let name: String
    let tint: Color
    let isDimmed: Bool
    let isSwapTarget: Bool
    /// The place a header shortcut sits in, drawn so it reads as one of the board's slots.
    let ringSize: CGFloat?
    let height: CGFloat
    let onDrag: () -> Void
    let drop: (NotchShortcut) -> Bool
    @ViewBuilder let menu: MenuContent

    @State private var isHovering = false
    @State private var isTargeted = false

    private var highlightInset: CGFloat { 4 }

    private var glyph: some View {
        Image(systemName: shortcut.symbol)
            .font(.system(size: 13, weight: .medium))
            .frame(width: NotchHeaderMetrics.buttonSize + NotchHeaderMetrics.shortcutSpacing, height: height)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        glyph
            .foregroundStyle(tint)
            .background {
                if let ringSize {
                    Circle()
                        .fill(tint.opacity(isHovering ? 0.28 : 0.12))
                        .strokeBorder(tint.opacity(isHovering ? 0.7 : 0.35), lineWidth: 1)
                        .frame(width: ringSize, height: ringSize)
                } else {
                    shape.fill(tint.opacity(isHovering ? 0.16 : 0)).padding(.vertical, highlightInset)
                }
            }
            .overlay {
                shape
                    .fill(Color.accentColor.opacity(isTargeted ? 0.45 : 0))
                    .strokeBorder(
                        Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [3, 3])
                    )
                    .padding(.vertical, highlightInset)
                    .opacity(isSwapTarget ? 1 : 0)
            }
            .opacity(isDimmed ? 0.4 : 1)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onDrag {
                onDrag()
                return NSItemProvider(object: shortcut.rawValue as NSString)
            } preview: {
                glyph.background(.regularMaterial, in: shape)
            }
            .dropDestination(for: String.self) { dropped, _ in
                guard let other = dropped.first.flatMap(NotchShortcut.init(rawValue:)) else { return false }
                return drop(other)
            } isTargeted: {
                isTargeted = $0
            }
            .contextMenu {
                Text(verbatim: name)
                menu
            }
            .help(name)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.12), value: isTargeted)
            .animation(.easeOut(duration: 0.12), value: isSwapTarget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
    }
}
