import SwiftUI

/// A replica of the open notch above the unused shortcuts; a drop rearranges the real header.
struct NotchShortcutBoard: View {
    @Environment(AppSettings.self) private var settings

    @State private var held: NotchShortcut?
    @State private var pointer: CGPoint?
    @State private var slotFrames: [Slot: CGRect] = [:]
    @State private var trayFrame = CGRect.zero
    @State private var hiddenFrame = CGRect.zero
    @State private var probe = NotchBoardProbeView()
    @State private var hasBattery = BatteryStatusService.hasInternalBattery

    private static let barHeight: CGFloat = 32
    private static let trayWidth: CGFloat = 540
    private static let trayPageHeight: CGFloat = 22
    private static let cutoutWidth: CGFloat = 72
    private static let cutoutHeight: CGFloat = 18
    private static let trayCornerRadius: CGFloat = 14
    private static let zoneInset: CGFloat = 3
    private static let rowTitleWidth: CGFloat = 150
    private static let slotSize = NotchHeaderMetrics.buttonSize
    private static let dragPollInterval = Duration.milliseconds(16)
    private nonisolated static let boardSpace = "NotchShortcutBoard"

    private typealias Zone = NotchShortcutLayout.Zone
    private typealias Slot = NotchShortcutLayout.Slot

    private var showsBattery: Bool { settings.notchShowsBattery && hasBattery }

    /// Only what the tray draws; a shortcut that is off or has no room is left off the board.
    private var layout: NotchShortcutLayout {
        settings.notchShortcutLayout.keeping(where: settings.isAvailable).fitting(showsBattery: showsBattery)
    }

    private var unused: [NotchShortcut] { layout.unused.filter(settings.isAvailable) }

    private func placing(_ shortcut: NotchShortcut, in slot: Slot) -> NotchShortcutLayout? {
        layout.placing(shortcut, in: slot, showsBattery: showsBattery)
    }

    /// The mouse in the board's own space, read from AppKit because it is exact throughout a drag.
    private var mouseLocation: CGPoint? {
        probe.window.map { probe.convert($0.mouseLocationOutsideOfEventStream, from: nil) }
    }

    private var isHiddenTargeted: Bool {
        held != nil && pointer.map(hiddenFrame.contains) ?? false
    }

    /// The place under the pointer, when the held shortcut can go there.
    private var landing: Slot? {
        guard let held, let pointer, trayFrame.contains(pointer) else { return nil }
        return slot(at: pointer).flatMap { placing(held, in: $0) == nil ? nil : $0 }
    }

    private func drop(_ shortcut: NotchShortcut, at point: CGPoint) {
        if hiddenFrame.contains(point) {
            hide(shortcut)
        } else if trayFrame.contains(point) {
            apply(slot(at: point).flatMap { placing(shortcut, in: $0) })
        }
    }

    /// The drawn place nearest the pointer, so every point of the tray names exactly one.
    private func slot(at point: CGPoint) -> Slot? {
        let drawn = Zone.allCases.flatMap { zone in
            layout.drawable(zone, showsBattery: showsBattery).map { Slot(zone: zone, index: $0) }
        }
        let framed = drawn.compactMap { slot in slotFrames[slot].map { (slot, abs($0.midX - point.x)) } }
        return framed.min { $0.1 < $1.1 }?.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            screen
            hiddenRow
        }
        .padding(.vertical, Theme.Spacing.xs)
        .background(NotchBoardProbe(view: probe))
        .coordinateSpace(.named(Self.boardSpace))
        .dropDestination(for: String.self) { _, _ in }
        .animation(.easeOut(duration: 0.15), value: held)
        .animation(.easeOut(duration: 0.12), value: landing)
        .task(id: held) {
            // A drop session reported places shifted from the tray, so the mouse itself decides.
            guard let held else { return }
            while NSEvent.pressedMouseButtons != 0 {
                let next = mouseLocation
                if next != pointer { pointer = next }
                guard (try? await Task.sleep(for: Self.dragPollInterval)) != nil else { return }
            }
            if let point = pointer ?? mouseLocation { drop(held, at: point) }
            self.held = nil
            pointer = nil
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
        return VStack(spacing: 0) {
            header
            page
        }
        .frame(maxWidth: Self.trayWidth)
        .background(shape.fill(.black))
        .clipShape(shape)
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(Self.boardSpace))
        } action: {
            trayFrame = $0
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

    /// One zone's places in order, each a shortcut or a free place a drop can take.
    private func group(_ zone: Zone) -> some View {
        let shape = Capsule()
        let isOffered = held != nil
        let places = layout[zone]
        return HStack(spacing: 0) {
            ForEach(Array(layout.drawable(zone, showsBattery: showsBattery)), id: \.self) { index in
                let slot = Slot(zone: zone, index: index)
                Group {
                    if let shortcut = places[index] {
                        tile(shortcut, isInHeader: true, isLanding: landing == slot)
                    } else {
                        free(isOffered: isOffered, landing: landing == slot ? held : nil)
                    }
                }
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(Self.boardSpace))
                } action: {
                    slotFrames[slot] = $0
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .overlay(
            shape.strokeBorder(Color.accentColor.opacity(isOffered ? 0.35 : 0), lineWidth: 1)
                .padding(.vertical, Self.zoneInset)
        )
        .animation(.snappy(duration: 0.25), value: places)
    }

    /// A free place; `landing` is the shortcut a drop would put in it.
    private func free(isOffered: Bool, landing: NotchShortcut?) -> some View {
        let isLanding = landing != nil
        return Circle()
            .strokeBorder(
                isOffered ? Color.accentColor : Color.white.opacity(0.3),
                style: StrokeStyle(lineWidth: isLanding ? 2 : 1, dash: isLanding ? [] : [3, 3])
            )
            .background(Circle().fill(Color.accentColor.opacity(isLanding ? 0.85 : 0)))
            .overlay {
                if let landing {
                    Image(systemName: landing.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: Self.slotSize, height: Self.slotSize)
            .scaleEffect(isLanding ? 1.12 : 1)
            .frame(width: Self.slotSize + NotchHeaderMetrics.shortcutSpacing, height: Self.barHeight)
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
            hiddenList
        }
    }

    private var hiddenList: some View {
        let isLit = isHiddenTargeted
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        return HStack(spacing: 0) {
            if unused.isEmpty {
                Text("Drag a shortcut here to take it out of the notch.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(unused, id: \.self) { tile($0, isInHeader: false, isLanding: false) }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: Self.barHeight + Theme.Spacing.xs, alignment: .leading)
        .background(shape.fill(.quaternary.opacity(isLit ? 1 : 0.5)))
        .overlay(
            shape.strokeBorder(
                isLit || held != nil ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                style: StrokeStyle(lineWidth: isLit ? 2 : 1, dash: [4, 3]))
        )
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(Self.boardSpace))
        } action: {
            hiddenFrame = $0
        }
    }

    // MARK: - Tiles

    /// `isLanding` marks the header shortcut a drop would trade places with.
    private func tile(_ shortcut: NotchShortcut, isInHeader: Bool, isLanding: Bool) -> some View {
        NotchShortcutTile(
            shortcut: shortcut,
            tint: isInHeader ? .white : .primary,
            isLanding: isLanding,
            isHeld: held == shortcut,
            ringSize: isInHeader ? Self.slotSize : nil,
            height: Self.barHeight,
            onDrag: { held = shortcut },
            menu: {
                if isInHeader {
                    Button("Remove") { hide(shortcut) }
                } else {
                    let added = layout.adding(shortcut, showsBattery: showsBattery)
                    Button("Add") { apply(added) }
                        .disabled(added == nil)
                }
            }
        )
    }

    private func hide(_ shortcut: NotchShortcut) {
        apply(layout.removing(shortcut))
    }

    private func apply(_ next: NotchShortcutLayout?) {
        guard let next else { return }
        let shown = layout
        // The board edits a filtered view, so what it left out goes back before the layout is stored.
        settings.notchShortcutLayout = next.restoring(from: settings.notchShortcutLayout) {
            shown.slot(of: $0) == nil
        }
    }
}

/// An AppKit view under the board, there only to convert the mouse into the board's coordinates.
private final class NotchBoardProbeView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct NotchBoardProbe: NSViewRepresentable {
    let view: NotchBoardProbeView

    func makeNSView(context: Context) -> NotchBoardProbeView { view }

    func updateNSView(_ nsView: NotchBoardProbeView, context: Context) {}
}

/// One draggable shortcut; in the header it fills while a drop would trade places with it.
private struct NotchShortcutTile<MenuContent: View>: View {
    let shortcut: NotchShortcut
    let tint: Color
    let isLanding: Bool
    let isHeld: Bool
    /// The place a header shortcut sits in, drawn so it reads as one of the board's slots.
    let ringSize: CGFloat?
    let height: CGFloat
    let onDrag: () -> Void
    @ViewBuilder let menu: MenuContent

    @State private var isHovering = false

    private static var highlightInset: CGFloat { 4 }

    private var name: String { shortcut.title }

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
                        .fill(isLanding ? Color.accentColor.opacity(0.85) : tint.opacity(isHovering ? 0.28 : 0.12))
                        .strokeBorder(
                            isLanding ? Color.accentColor : tint.opacity(isHovering ? 0.7 : 0.35),
                            lineWidth: isLanding ? 2 : 1
                        )
                        .frame(width: ringSize, height: ringSize)
                        .scaleEffect(isLanding ? 1.12 : 1)
                } else {
                    shape.fill(tint.opacity(isHovering ? 0.16 : 0)).padding(.vertical, Self.highlightInset)
                }
            }
            .opacity(isHeld ? 0.35 : 1)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onDrag {
                onDrag()
                return NSItemProvider(object: shortcut.rawValue as NSString)
            } preview: {
                glyph.background(.regularMaterial, in: shape)
            }
            .contextMenu {
                Text(verbatim: name)
                menu
            }
            .help(name)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.12), value: isLanding)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
    }
}
