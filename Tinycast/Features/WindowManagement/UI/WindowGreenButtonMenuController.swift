import AppKit
import SwiftUI

/// Floating Magnet-style tiling popover anchored under a window's traffic-light button.
@MainActor
final class WindowGreenButtonMenuController {
    private static let landscapeGroups: [[WindowCommand.ID]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter],
        [.firstThird, .centerThird, .lastThird],
        [.firstTwoThirds, .centerTwoThirds, .lastTwoThirds],
        [.maximize, .center, .restore, .toggleFullscreen]
    ]

    private static let portraitGroups: [[WindowCommand.ID]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter],
        [.topThird, .middleThird, .bottomThird],
        [.topTwoThirds, .middleTwoThirds, .bottomTwoThirds],
        [.maximize, .center, .restore, .toggleFullscreen]
    ]

    private var panel: WindowGreenButtonPanel?
    private var hosting: NSHostingView<AnyView>?
    private(set) var activeButtonFrame: CGRect?

    var isShowing: Bool { panel?.isVisible == true }

    /// Menu bounds in AX space, or `.null` while hidden.
    var menuFrameInAX: CGRect {
        guard let panel, panel.isVisible else { return .null }
        let geometry = AXGeometry(screens: NSScreen.screens)
        return geometry.flip(panel.frame)
    }

    func show(
        for target: WindowMover.GreenButtonTarget,
        customSizes: [CustomWindowSize],
        hotKeys: HotKeyManager,
        onButtonClick: @escaping () -> Void,
        onCommand: @escaping (WindowCommand.ID) -> Void,
        onCustomSize: @escaping (CustomWindowSize) -> Void
    ) {
        let isPortrait = target.hostScreen.visibleFrame.height > target.hostScreen.visibleFrame.width
        let groups = isPortrait ? Self.portraitGroups : Self.landscapeGroups

        let visible = target.hostScreen.visibleFrame
        let menuWidth = WindowGreenButtonMenuView.menuWidth
        let rawX = target.buttonFrame.minX - 8
        let clampedX = min(
            max(rawX, visible.minX + 6), max(visible.minX + 6, visible.maxX - menuWidth - 6)
        ).rounded()

        let shieldHeight = max(18, target.buttonFrame.height + 6).rounded(.up)
        let shieldOffsetX = max(0, target.buttonFrame.minX - 2 - clampedX)
        let shieldWidth = max(18, target.buttonFrame.width + 4)

        let root = AnyView(
            WindowGreenButtonMenuView(
                groups: groups,
                customSizes: customSizes,
                hotKeys: hotKeys,
                shieldRect: CGRect(
                    x: shieldOffsetX, y: 0, width: shieldWidth, height: shieldHeight),
                onButtonClick: { [weak self] in
                    self?.hide()
                    onButtonClick()
                },
                onCommand: { [weak self] id in
                    self?.hide()
                    onCommand(id)
                },
                onCustomSize: { [weak self] size in
                    self?.hide()
                    onCustomSize(size)
                }
            )
            .motionScope())

        let panel = ensurePanel()
        setContent(root, in: panel)
        guard let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let contentSize = hosting.fittingSize
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        let topWithShield = (target.buttonFrame.minY - 2).rounded()
        let fitsBelow = topWithShield + contentSize.height <= visible.maxY - 6
        let axOriginY =
            fitsBelow
            ? topWithShield
            : max(visible.minY + 6, target.buttonFrame.minY - contentSize.height - 6).rounded()
        let axMenuRect = CGRect(
            x: clampedX, y: axOriginY,
            width: contentSize.width.rounded(.up), height: contentSize.height.rounded(.up))
        let cocoaRect = target.geometry.flip(axMenuRect)

        activeButtonFrame = target.buttonFrame
        panel.setFrame(cocoaRect, display: true)
        hosting.frame = NSRect(origin: .zero, size: cocoaRect.size)
        panel.invalidateShadow()

        if !panel.isVisible {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if reduceMotion {
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            } else {
                panel.fadeIn(duration: Theme.Duration.enter) { panel.orderFrontRegardless() }
            }
        }
    }

    func hide() {
        activeButtonFrame = nil
        guard let panel, panel.isVisible else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.orderOut(nil)
        } else {
            panel.fadeOut(duration: Theme.Duration.exit)
        }
    }

    private func ensurePanel() -> WindowGreenButtonPanel {
        if let panel { return panel }
        let created = WindowGreenButtonPanel()
        panel = created
        return created
    }

    private func setContent(_ root: AnyView, in panel: WindowGreenButtonPanel) {
        if let hosting {
            hosting.rootView = root
            return
        }
        let view = NSHostingView(rootView: root)
        view.sizingOptions = [.intrinsicContentSize]
        let container = NSView(frame: .zero)
        container.addSubview(view)
        panel.contentView = container
        panel.displayIfNeeded()
        hosting = view
    }
}

private struct WindowGreenButtonMenuView: View {
    static let menuWidth: CGFloat = 232

    let groups: [[WindowCommand.ID]]
    let customSizes: [CustomWindowSize]
    let hotKeys: HotKeyManager
    let shieldRect: CGRect
    let onButtonClick: () -> Void
    let onCommand: (WindowCommand.ID) -> Void
    let onCustomSize: (CustomWindowSize) -> Void

    @State private var hoveredID: String?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: Self.menuWidth, height: shieldRect.height + 4)
                    .allowsHitTesting(false)

                Button(action: onButtonClick) {
                    Theme.Colors.hitTestShield
                        .frame(width: shieldRect.width, height: shieldRect.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: shieldRect.minX, y: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, ids in
                    if groupIndex > 0 { separator }
                    ForEach(ids, id: \.self) { id in
                        if let command = WindowCommandCatalog.command(id: id) {
                            row(
                                rowID: command.entryID,
                                title: command.name,
                                shortcut: shortcutString(for: .windowCommand(id: id)),
                                icon: { WindowCommandIcon(command: command) }
                            ) {
                                onCommand(id)
                            }
                        }
                    }
                }

                if !customSizes.isEmpty {
                    separator
                    ForEach(customSizes.prefix(6)) { size in
                        row(
                            rowID: size.entryID,
                            title: size.name,
                            shortcut: shortcutString(for: .customWindowSize(id: size.id)),
                            icon: { WindowCommandIcon(size: size) }
                        ) {
                            onCustomSize(size)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .frame(width: Self.menuWidth)
            .glassEffect(.regular, in: shape)
            .clipShape(shape)
        }
        .frame(width: Self.menuWidth)
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1 / displayScale)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 3)
    }

    private func row<Icon: View>(
        rowID: String, title: String, shortcut: String?, @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredID == rowID
        return Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                icon()
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.menuSymbol)
                    .frame(width: 18, height: 18)

                Text(verbatim: title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Spacer(minLength: Theme.Spacing.sm)

                if let shortcut {
                    Text(verbatim: shortcut)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(isHovered ? Theme.Colors.menuHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hoveredID = rowID
            } else if hoveredID == rowID {
                hoveredID = nil
            }
        }
    }

    private func shortcutString(for action: HotKeyAction) -> String? {
        guard let caps = hotKeys.binding(for: action)?.keycaps, !caps.isEmpty else { return nil }
        return caps.joined()
    }
}

private final class WindowGreenButtonPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
