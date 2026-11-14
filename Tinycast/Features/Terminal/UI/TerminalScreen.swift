import SwiftUI

struct TerminalScreen: PaletteScreen {
    let store: TerminalStore
    let coordinator: TerminalCoordinator
    let core: AppCore
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let openActions: () -> Void

    struct Row: Identifiable {
        let id = "terminal-session"
    }

    let rows = [Row()]

    private var selectedTab: TerminalTab? { store.selectedTab }
    private var trimmedQuery: String { vm.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var primaryActionTitle: String {
        if selectedTab?.isRunning == true {
            return vm.query.isEmpty ? String(localized: "Stop") : String(localized: "Send Input")
        }
        return String(localized: "Run Command")
    }

    func isPrimaryActionEnabled(at selection: Int) -> Bool {
        if selectedTab?.isRunning == true { return true }
        return !trimmedQuery.isEmpty
    }

    func activate(at selection: Int) {
        coordinator.submitInTerminalScreen()
    }

    func secondary(at selection: Int) -> Bool {
        guard !trimmedQuery.isEmpty else {
            coordinator.newTab()
            return true
        }
        return coordinator.handleShiftReturn()
    }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        if backwards {
            return coordinator.handleShiftTab()
        }
        if store.tabs.count > 1 {
            store.cycleSelectedTab()
            return true
        }
        return false
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .newItem:
            coordinator.newTab()
            return true
        case .delete:
            coordinator.closeSelectedTab()
            return true
        case .deleteAll:
            coordinator.closeAllTabs()
            return true
        case .commandDelete:
            coordinator.clearSelectedTab()
            return true
        case .pin:
            guard selectedTab?.isRunning == true else { return false }
            coordinator.stopSelectedTab()
            return true
        case .restart:
            coordinator.rerunSelectedTab()
            return true
        case .copyFile, .copyText:
            coordinator.copySelectedOutput()
            return true
        case .copyPath:
            coordinator.copyActiveDirectory()
            return true
        case .showInFinder:
            coordinator.showActiveDirectoryInFinder()
            return true
        case .openInApp:
            coordinator.openActiveDirectoryInTerminalApp()
            return true
        case .settings:
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            core.settingsCoordinator.showSettings(tab: .terminal)
            return true
        case .favoriteSlot(let slot):
            let index = slot == 0 ? 9 : slot - 1
            guard store.tabs.indices.contains(index) else { return false }
            store.selectTab(at: index)
            return true
        default:
            return false
        }
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        var items: [PopoverMenuItem] = []

        if !trimmedQuery.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Run Command"),
                    systemImage: "play.fill",
                    shortcut: "↵"
                ) {
                    coordinator.submitInTerminalScreen()
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Run in New Tab"),
                    systemImage: "plus.rectangle.on.rectangle",
                    shortcut: "⇧↵"
                ) {
                    _ = coordinator.handleShiftReturn()
                })
        }

        if selectedTab?.isRunning == true {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Stop Command"),
                    systemImage: "stop.fill",
                    startsSection: !items.isEmpty,
                    shortcut: "⌘."
                ) {
                    coordinator.stopSelectedTab()
                })
        } else if selectedTab?.lastCommand != nil {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Rerun Last Command"),
                    systemImage: "arrow.clockwise",
                    startsSection: !items.isEmpty,
                    shortcut: "⌘R"
                ) {
                    coordinator.rerunSelectedTab()
                })
        }

        items.append(
            PopoverMenuItem(
                title: String(localized: "New Tab"),
                systemImage: "plus",
                startsSection: !items.isEmpty,
                shortcut: "⌘N"
            ) {
                coordinator.newTab()
            })

        if selectedTab?.log.isEmpty == false {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy Output"),
                    systemImage: "doc.on.doc",
                    shortcut: "⇧⌘C"
                ) {
                    coordinator.copySelectedOutput()
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Clear Output"),
                    systemImage: "eraser",
                    shortcut: "⌘⌫"
                ) {
                    coordinator.clearSelectedTab()
                })
        }

        items.append(
            PopoverMenuItem(
                title: String(localized: "Cycle Recent Folder"),
                systemImage: "folder",
                startsSection: true,
                shortcut: "⇧⇥"
            ) {
                _ = coordinator.handleShiftTab()
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Open Folder in Terminal"),
                systemImage: "apple.terminal",
                shortcut: "⌘O"
            ) {
                coordinator.openActiveDirectoryInTerminalApp()
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Show Folder in Finder"),
                systemImage: "finder",
                shortcut: "⌘F"
            ) {
                coordinator.showActiveDirectoryInFinder()
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Copy Folder Path"),
                systemImage: "link",
                shortcut: "⌃⌘C"
            ) {
                coordinator.copyActiveDirectory()
            })

        if !store.tabs.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Close Tab"),
                    systemImage: "xmark",
                    startsSection: true,
                    shortcut: "⌃X",
                    isDestructive: true
                ) {
                    coordinator.closeSelectedTab()
                })
            if store.tabs.count > 1 {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Close All Tabs"),
                        systemImage: "xmark.circle",
                        shortcut: "⌃⇧X",
                        isDestructive: true
                    ) {
                        coordinator.closeAllTabs()
                    })
            }
        }

        items.append(
            PopoverMenuItem(
                title: String(localized: "Terminal Settings"),
                systemImage: "gearshape",
                startsSection: true,
                shortcut: "⌥⌘,"
            ) {
                core.paletteCoordinator.hidePalette(restoreFocus: false)
                core.settingsCoordinator.showSettings(tab: .terminal)
            })

        return PopoverMenuContent(items: items)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            TerminalPanelContentView(
                store: store,
                coordinator: coordinator,
                metrics: metrics))
    }
}

private struct TerminalPanelContentView: View {
    let store: TerminalStore
    let coordinator: TerminalCoordinator
    let metrics: InterfaceMetrics

    @State private var newTabHovered = false

    var body: some View {
        VStack(spacing: 0) {
            if !store.tabs.isEmpty {
                tabBar
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
            }

            if let tab = store.selectedTab {
                if tab.log.isEmpty && !tab.isRunning {
                    emptyState(for: tab)
                } else {
                    TerminalOutputView(
                        tab: tab,
                        horizontalInset: metrics.spacing.md * 2,
                        bottomClearance: metrics.size.bottomBarHeight + metrics.spacing.md)
                }
            } else {
                emptyNoTabState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: metrics.spacing.xs) {
                ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                    TerminalTabChip(
                        tab: tab,
                        index: index,
                        isSelected: store.selectedTab?.id == tab.id,
                        homeDirectory: store.homeDirectory,
                        metrics: metrics,
                        onSelect: { store.selectTab(id: tab.id) },
                        onClose: { coordinator.closeTab(id: tab.id) })
                }

                Button {
                    coordinator.newTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: metrics.scaled(11), weight: .semibold))
                        .foregroundStyle(
                            newTabHovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .frame(width: metrics.scaled(24), height: metrics.scaled(24))
                        .background(
                            RoundedRectangle(
                                cornerRadius: metrics.radius.barControl, style: .continuous
                            )
                            .fill(newTabHovered ? Theme.Colors.controlHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { newTabHovered = $0 }
                .help(String(localized: "New Tab  ⌘N"))
            }
            .padding(.horizontal, metrics.spacing.md * 2)
            .padding(.vertical, metrics.spacing.xs)
        }
    }

    private func emptyState(for tab: TerminalTab) -> some View {
        VStack(spacing: metrics.spacing.lg) {
            Image(systemName: "apple.terminal")
                .font(.system(size: metrics.scaled(28), weight: .light))
                .foregroundStyle(Theme.Colors.textTertiary)

            Text(
                RecentFolders.displayPath(
                    tab.workingDirectory, homeDirectory: store.homeDirectory)
            )
            .font(.system(size: metrics.scaled(13), weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: metrics.spacing.xl) {
                shortcutHint(label: String(localized: "Run"), keys: "↵")
                shortcutHint(label: String(localized: "New Tab"), keys: "⇧↵")
                shortcutHint(label: String(localized: "Folder"), keys: "⇧⇥")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, metrics.size.bottomBarHeight)
    }

    private var emptyNoTabState: some View {
        VStack(spacing: metrics.spacing.md) {
            Image(systemName: "apple.terminal")
                .font(.system(size: metrics.scaled(28), weight: .light))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("Type a shell command above to start a terminal tab.")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, metrics.size.bottomBarHeight)
    }

    private func shortcutHint(label: String, keys: String) -> some View {
        HStack(spacing: metrics.spacing.xs) {
            Text(label)
                .font(.system(size: metrics.scaled(11)))
                .foregroundStyle(Theme.Colors.textTertiary)
            KeyCapChip(text: keys, style: .outline)
                .accessibilityHidden(true)
        }
    }
}

private struct TerminalTabChip: View {
    let tab: TerminalTab
    let index: Int
    let isSelected: Bool
    let homeDirectory: String
    let metrics: InterfaceMetrics
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovered = false
    @State private var closeHovered = false

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
                        .foregroundStyle(
                            isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary
                        )
                        .lineLimit(1)
                    if index < 9 {
                        Text(verbatim: "⌘\(index + 1)")
                            .font(.system(size: metrics.scaled(10)))
                            .foregroundStyle(Theme.Colors.textTertiary)
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
                    .foregroundStyle(
                        closeHovered ? Theme.Colors.textPrimary : Theme.Colors.textTertiary
                    )
                    .frame(width: metrics.scaled(16), height: metrics.scaled(16))
                    .background(
                        Circle()
                            .fill(closeHovered ? Theme.Colors.controlHover : Color.clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovered || isSelected ? 1 : 0.45)
            .onHover { closeHovered = $0 }
            .padding(.trailing, metrics.spacing.xs)
            .help(String(localized: "Close Tab  ⌃X"))
        }
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.Colors.border : Color.clear,
                    lineWidth: 1)
        )
        .onHover { hovered = $0 }
    }

    private var backgroundFill: Color {
        if isSelected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Color.clear
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if tab.isRunning {
            Circle()
                .fill(Theme.Colors.success)
                .frame(width: metrics.scaled(6), height: metrics.scaled(6))
        } else if let termination = tab.lastTermination, !termination.succeeded {
            Circle()
                .fill(Theme.Colors.destructive)
                .frame(width: metrics.scaled(6), height: metrics.scaled(6))
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: metrics.scaled(8.5), weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}
