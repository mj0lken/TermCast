import SwiftUI

struct TerminalScreen: PaletteScreen {
    let store: TerminalStore
    let coordinator: TerminalCoordinator
    let vm: PaletteState
    let metrics: InterfaceMetrics

    struct Row: Identifiable {
        let id = "terminal-session"
    }

    let rows: [Row] = []
    let hidesSearchField = true
    let actsWithoutRows = true

    private var selectedTab: TerminalTab? { store.selectedTab }

    var primaryActionTitle: String {
        String(localized: "Actions")
    }

    func hasPrimaryAction(at selection: Int) -> Bool { true }
    func isPrimaryActionEnabled(at selection: Int) -> Bool { true }
    func hasActions(at selection: Int) -> Bool { true }
    func ownsVerticalKeys(at selection: Int) -> Bool { true }

    func activate(at selection: Int) {
        if selectedTab?.isSessionAlive == false {
            coordinator.restartSelectedTab()
        } else {
            selectedTab?.requestFocus()
        }
    }

    func secondary(at selection: Int) -> Bool {
        coordinator.newTab()
        return true
    }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        coordinator.performPaletteShortcut(shortcut, focusTerminal: true)
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        coordinator.terminalModeActions()
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            TerminalPanelContentView(
                store: store,
                coordinator: coordinator,
                vm: vm,
                metrics: metrics,
                interactiveFocusEnabled: true))
    }
}

struct TerminalPanelContentView: View {
    let store: TerminalStore
    let coordinator: TerminalCoordinator
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let interactiveFocusEnabled: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @State private var newTabHovered = false
    @State private var restartHovered = false

    var body: some View {
        let theme = settings.terminalColorTheme
        let chrome = theme.chromeColors
        return VStack(spacing: 0) {
            if !store.tabs.isEmpty {
                tabBar(chrome: chrome)
                    .background {
                        if let tabBarRGB = theme.tabBarBackground {
                            Canvas { context, size in
                                context.fill(
                                    Path(CGRect(origin: .zero, size: size)),
                                    with: .color(Self.color(from: tabBarRGB)))
                            }
                            .allowsHitTesting(false)
                        }
                    }
                Rectangle()
                    .fill(
                        chrome.map {
                            Self.color(from: $0.selectionFill, opacity: $0.separatorOpacity)
                        } ?? Theme.Colors.separator
                    )
                    .frame(height: 1)
            }

            if let tab = store.selectedTab {
                ZStack(alignment: .bottom) {
                    InteractiveTerminalView(
                        tab: tab,
                        theme: theme,
                        isDark: colorScheme == .dark,
                        interactiveFocusEnabled: interactiveFocusEnabled,
                        shouldAutoFocus:
                            interactiveFocusEnabled && vm.mode == .terminal && !vm.menuOpen,
                        fontSize: metrics.scaled(12.5),
                        horizontalInset: metrics.spacing.md * 2,
                        bottomClearance: metrics.spacing.sm,
                        onCopyFeedback: { coordinator.showCopiedSelectionFeedback() })

                    if !tab.isSessionAlive && tab.launchFailureMessage == nil {
                        exitedBanner(chrome: chrome)
                            .padding(.bottom, metrics.spacing.md)
                    }
                }
                .background {
                    if let surfaceRGB = theme.surfaceBackground {
                        Canvas { context, size in
                            context.fill(
                                Path(CGRect(origin: .zero, size: size)),
                                with: .color(Self.color(from: surfaceRGB)))
                        }
                        .padding(.bottom, -metrics.size.bottomBarHeight)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if store.tabs.isEmpty {
                _ = coordinator.ensureActiveInteractiveTab(focus: interactiveFocusEnabled)
            }
        }
    }

    fileprivate static func color(from rgb: TerminalRGB, opacity: Double = 1.0) -> Color {
        Color(
            .sRGB,
            red: Double(rgb.r) / 255.0,
            green: Double(rgb.g) / 255.0,
            blue: Double(rgb.b) / 255.0,
            opacity: opacity)
    }

    private func exitedBanner(chrome: TerminalChromeColors?) -> some View {
        let fgColor = chrome.map { Self.color(from: $0.textPrimary) } ?? Theme.Colors.textPrimary
        let fillColor: Color =
            if let chrome {
                Self.color(
                    from: chrome.selectionFill,
                    opacity: restartHovered ? chrome.selectionOpacity : chrome.hoverOpacity)
            } else {
                restartHovered ? Theme.Colors.controlHover : Theme.Colors.controlSurface
            }
        let strokeColor =
            chrome.map { Self.color(from: $0.selectionFill, opacity: $0.borderOpacity) }
            ?? Theme.Colors.border
        return Button {
            coordinator.restartSelectedTab(focus: interactiveFocusEnabled)
        } label: {
            HStack(spacing: metrics.spacing.sm) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: metrics.scaled(11), weight: .semibold))
                Text("Restart Shell")
                    .font(metrics.typography.bar)
            }
            .foregroundStyle(fgColor)
            .padding(.horizontal, metrics.spacing.md)
            .padding(.vertical, metrics.spacing.xs)
            .background(Capsule().fill(fillColor))
            .overlay(Capsule().strokeBorder(strokeColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { restartHovered = $0 }
    }

    private func tabBar(chrome: TerminalChromeColors?) -> some View {
        let plusPrimary = chrome.map { Self.color(from: $0.textPrimary) } ?? Theme.Colors.textPrimary
        let plusSecondary =
            chrome.map { Self.color(from: $0.textSecondary) } ?? Theme.Colors.textSecondary
        let plusHover =
            chrome.map { Self.color(from: $0.selectionFill, opacity: $0.hoverOpacity) }
            ?? Theme.Colors.controlHover
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: metrics.spacing.xs) {
                ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                    TerminalTabChip(
                        tab: tab,
                        index: index,
                        isSelected: store.selectedTab?.id == tab.id,
                        homeDirectory: store.homeDirectory,
                        closeShortcut: coordinator.shortcutDisplay(for: .closeTab),
                        chrome: chrome,
                        metrics: metrics,
                        onSelect: { store.selectTab(id: tab.id, focus: interactiveFocusEnabled) },
                        onClose: { coordinator.closeTab(id: tab.id) })
                }

                Button {
                    coordinator.newTab(focus: interactiveFocusEnabled)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: metrics.scaled(11), weight: .semibold))
                        .foregroundStyle(newTabHovered ? plusPrimary : plusSecondary)
                        .frame(width: metrics.scaled(24), height: metrics.scaled(24))
                        .background(
                            RoundedRectangle(
                                cornerRadius: metrics.radius.barControl, style: .continuous
                            )
                            .fill(newTabHovered ? plusHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { newTabHovered = $0 }
                .tooltip(newTabHelpText, alignment: .trailing, edge: .bottom, dismissOnPress: true)
            }
            .padding(.horizontal, metrics.spacing.md * 2)
            .padding(.vertical, metrics.spacing.xs)
        }
    }

    private var newTabHelpText: String {
        if let keys = coordinator.shortcutDisplay(for: .newTab) {
            return String(localized: "New Tab") + "  " + keys
        }
        return String(localized: "New Tab")
    }
}

private struct TerminalTabChip: View {
    let tab: TerminalTab
    let index: Int
    let isSelected: Bool
    let homeDirectory: String
    let closeShortcut: String?
    let chrome: TerminalChromeColors?
    let metrics: InterfaceMetrics
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovered = false
    @State private var closeHovered = false

    private var textPrimaryColor: Color {
        chrome.map { TerminalPanelContentView.color(from: $0.textPrimary) }
            ?? Theme.Colors.textPrimary
    }

    private var textSecondaryColor: Color {
        chrome.map { TerminalPanelContentView.color(from: $0.textSecondary) }
            ?? Theme.Colors.textSecondary
    }

    private var textTertiaryColor: Color {
        chrome.map { TerminalPanelContentView.color(from: $0.textTertiary) }
            ?? Theme.Colors.textTertiary
    }

    private var closeHoverFill: Color {
        chrome.map { TerminalPanelContentView.color(from: $0.selectionFill, opacity: $0.hoverOpacity) }
            ?? Theme.Colors.controlHover
    }

    private var borderColor: Color {
        chrome.map { TerminalPanelContentView.color(from: $0.selectionFill, opacity: $0.borderOpacity) }
            ?? Theme.Colors.border
    }

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            Button(action: onSelect) {
                HStack(spacing: metrics.spacing.sm) {
                    statusIndicator
                    Text(tab.title(homeDirectory: homeDirectory))
                        .font(
                            .system(
                                size: metrics.scaled(11.5),
                                weight: isSelected ? .medium : .regular,
                                design: .monospaced)
                        )
                        .foregroundStyle(isSelected ? textPrimaryColor : textSecondaryColor)
                        .lineLimit(1)
                    if index < 9 {
                        Text(verbatim: "⌘\(index + 1)")
                            .font(.system(size: metrics.scaled(10)))
                            .foregroundStyle(textTertiaryColor)
                    }
                }
                .padding(.leading, metrics.spacing.md)
                .padding(.trailing, metrics.spacing.xxs)
                .padding(.vertical, metrics.spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: metrics.scaled(8.5), weight: .bold))
                    .foregroundStyle(closeHovered ? textPrimaryColor : textTertiaryColor)
                    .frame(width: metrics.scaled(16), height: metrics.scaled(16))
                    .background(
                        Circle()
                            .fill(closeHovered ? closeHoverFill : Color.clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovered || isSelected ? 1 : 0.45)
            .onHover { closeHovered = $0 }
            .padding(.trailing, metrics.spacing.xs)
            .tooltip(
                closeShortcut.map { String(localized: "Close Tab") + "  " + $0 }
                    ?? String(localized: "Close Tab"),
                edge: .bottom,
                dismissOnPress: true)
        }
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous)
                .strokeBorder(
                    isSelected ? borderColor : Color.clear,
                    lineWidth: 1)
        )
        .onHover { hovered = $0 }
    }

    private var backgroundFill: Color {
        if isSelected {
            return chrome.map {
                TerminalPanelContentView.color(from: $0.selectionFill, opacity: $0.selectionOpacity)
            } ?? Theme.Colors.selection
        }
        if hovered {
            return chrome.map {
                TerminalPanelContentView.color(from: $0.selectionFill, opacity: $0.hoverOpacity)
            } ?? Theme.Colors.rowHover
        }
        return Color.clear
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if tab.isRunning {
            Circle()
                .fill(Theme.Colors.success)
                .frame(width: metrics.scaled(6), height: metrics.scaled(6))
                .shadow(color: Theme.Colors.success.opacity(0.8), radius: metrics.scaled(3))
        } else if !tab.isSessionAlive {
            Circle()
                .fill(textTertiaryColor)
                .frame(width: metrics.scaled(6), height: metrics.scaled(6))
        } else if tab.lastExitStatus != 0 {
            Circle()
                .fill(Theme.Colors.destructive)
                .frame(width: metrics.scaled(6), height: metrics.scaled(6))
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: metrics.scaled(8.5), weight: .bold))
                .foregroundStyle(textTertiaryColor)
        }
    }
}
