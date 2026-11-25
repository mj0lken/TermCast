import SwiftUI

/// The header's measures, shared with the settings board that draws a replica of it.
enum NotchHeaderMetrics {
    static let buttonSize: CGFloat = 24
    static let tabPadding: CGFloat = 12
    /// Tried widest first: the tabs give up padding before the leading half outgrows its room.
    static let tabPaddings: [CGFloat] = [tabPadding, 8, 5]
    static let tabSpacing = Theme.Spacing.xs
    static let shortcutSpacing = Theme.Spacing.sm
    static let edgeInset = Theme.Spacing.lg
}

/// The tray's top band: tabs before the cutout, the battery readout after it, shortcuts on both sides.
struct NotchOpenHeaderBar: View {
    let state: NotchOpenTrayState
    let shelfCount: Int
    let runningTerminalCount: Int
    let battery: BatteryStatusService
    let timer: NotchTimer
    let shortcuts: NotchShortcutActions

    /// Each side of the cutout gets exactly its room, so a crowded side never pushes the other out.
    private var halfWidth: CGFloat {
        let cutout = state.layout.isNotched ? state.layout.notchWidth : 0
        return max((state.layout.trayWidth - cutout) / 2, 0)
    }

    var body: some View {
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                ForEach(NotchHeaderMetrics.tabPaddings, id: \.self) { leadingHalf(tabPadding: $0) }
            }
            .frame(width: halfWidth, alignment: .leading)

            if state.layout.isNotched {
                ZStack {
                    Color.clear
                        .frame(width: state.layout.notchWidth, height: state.layout.headerHeight)
                }
            }

            HStack(spacing: NotchHeaderMetrics.shortcutSpacing) {
                if let metric = state.inlineHUDMetric {
                    Spacer(minLength: 0)
                    NotchInlineOpenHUDChip(metric: metric)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    shortcutButtons(state.shortcutsAfterNotch)
                    Spacer(minLength: 0)
                    shortcutButtons(state.shortcuts)

                    if state.showsBattery, battery.status.hasBattery {
                        NotchBatteryBadge(status: battery.status)
                    }
                }
            }
            .padding(.leading, NotchHeaderMetrics.shortcutSpacing)
            .padding(.trailing, NotchHeaderMetrics.edgeInset)
            .frame(width: halfWidth, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.16), value: state.inlineHUDMetric)
    }

    /// The tabs' capsule lines up with the page below, which sits a step further in than the header.
    private func leadingHalf(tabPadding: CGFloat) -> some View {
        HStack(spacing: NotchHeaderMetrics.tabSpacing) {
            NotchTabButton(
                symbol: "house.fill", label: String(localized: "Home"), isSelected: state.tab == .home,
                badgeCount: 0, padding: tabPadding
            ) {
                state.tab = .home
            }
            NotchTabButton(
                symbol: "tray.fill", label: String(localized: "Shelf"), isSelected: state.tab == .shelf,
                badgeCount: shelfCount, padding: tabPadding
            ) {
                state.tab = .shelf
            }
            if state.showsTerminal {
                NotchTabButton(
                    symbol: "apple.terminal.fill", label: String(localized: "Terminal Sessions"),
                    isSelected: state.tab == .terminal, badgeCount: runningTerminalCount, padding: tabPadding
                ) {
                    state.tab = .terminal
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: NotchHeaderMetrics.shortcutSpacing) { shortcutButtons(state.shortcutsBeforeNotch) }
        }
        .padding(.leading, NotchHeaderMetrics.edgeInset + Theme.Spacing.xs)
        .padding(.trailing, NotchHeaderMetrics.shortcutSpacing)
    }

    /// A nil place is a gap the user left, drawn as the room a button would take.
    private func shortcutButtons(_ places: [NotchShortcut?]) -> some View {
        ForEach(Array(places.enumerated()), id: \.offset) { place in
            if let shortcut = place.element {
                NotchShortcutButton(shortcut: shortcut, timer: timer, actions: shortcuts)
            } else {
                Color.clear
                    .frame(width: NotchHeaderMetrics.buttonSize, height: NotchHeaderMetrics.buttonSize)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A header shortcut's face, shared by the plain buttons and the menus so every one reads alike.
private struct NotchHeaderIcon: View {
    let symbol: String
    let isHovering: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isHovering ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .frame(width: NotchHeaderMetrics.buttonSize, height: NotchHeaderMetrics.buttonSize)
            .background(Circle().fill(isHovering ? Theme.Colors.controlHover : .clear))
            .contentShape(Rectangle())
    }
}

private struct NotchTabButton: View {
    let symbol: String
    let label: String
    let isSelected: Bool
    let badgeCount: Int
    let padding: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                if badgeCount > 0 {
                    Text(verbatim: "\(badgeCount)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .padding(.horizontal, padding)
            .frame(height: NotchHeaderMetrics.buttonSize)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.Colors.controlHover : .clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct NotchBatteryBadge: View {
    let status: BatteryStatusService.Status

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: "\(status.percentage)%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)

            Image(systemName: status.isPluggedIn ? "battery.100percent.bolt" : "battery.100percent")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    status.isPluggedIn ? Theme.Colors.success : Theme.Colors.textPrimary,
                    Theme.Colors.textSecondary)
        }
    }
}

private struct NotchInlineOpenHUDChip: View {
    @Environment(\.notchHUDStyle) private var style
    let metric: NotchHUDMetric

    var body: some View {
        HStack(spacing: 6) {
            SymbolImage(name: metric.symbol, size: 12, monochrome: true)
                .foregroundStyle(Theme.Colors.textPrimary)
            if case .notice(_, let text) = metric {
                Text(verbatim: text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            } else {
                Capsule()
                    .fill(Theme.Colors.controlSurface)
                    .frame(width: 56, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(style.fill)
                            .frame(width: 56 * CGFloat(metric.effectiveLevel), height: 4)
                    }
                if style.showsPercentage {
                    Text(verbatim: metric.percentageText())
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Capsule().fill(Theme.Colors.controlSurface))
    }
}

/// One slot of the header's shortcut row: a plain button, or a menu for the two that offer choices.
private struct NotchShortcutButton: View {
    let shortcut: NotchShortcut
    let timer: NotchTimer
    let actions: NotchShortcutActions

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private static let windowGroups: Set<WindowCommand.Group> = [.halves, .quarters, .sizing]

    private var icon: NotchHeaderIcon { NotchHeaderIcon(symbol: shortcut.symbol, isHovering: isHovering) }

    var body: some View {
        control
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(shortcut.title)
            .accessibilityLabel(shortcut.title)
    }

    @ViewBuilder
    private var control: some View {
        switch shortcut {
        case .clipboard, .notebook, .camera, .emoji, .settings, .gap:
            Button {
                actions.open(shortcut)
            } label: {
                icon
            }
        case .windowManagement:
            menu { windowCommands }
        case .timer:
            menu { timerPresets }
        case .snippets:
            Button {
                NotchSnippetMenu.present(
                    actions.snippets(), at: NSEvent.mouseLocation, isDark: colorScheme == .dark,
                    expand: actions.expandSnippet)
            } label: {
                icon
            }
        }
    }

    /// A binding a menu cannot draw as a key equivalent, spelled out; nil when the menu draws it.
    private func spelled(_ binding: HotKeyBinding?) -> String? {
        guard let binding, binding.menuShortcut == nil else { return nil }
        return binding.keycaps.joined(separator: " ")
    }

    private func title(_ name: String, binding: HotKeyBinding?) -> String {
        spelled(binding).map { name + "  " + $0 } ?? name
    }

    private func menu(@ViewBuilder _ content: () -> some View) -> some View {
        Menu(content: content) { icon }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
    }

    /// The placements worth a click; the rest of the catalog stays on its shortcuts and the launcher.
    @ViewBuilder
    private var windowCommands: some View {
        let groups = WindowCommandCatalog.grouped().filter { Self.windowGroups.contains($0.group) }
        ForEach(groups, id: \.group) { entry in
            Section(entry.group.title) {
                ForEach(entry.commands) { command in
                    let binding = actions.windowCommandBinding(command.id)
                    Button {
                        actions.runWindowCommand(command.id)
                    } label: {
                        Label(title(command.name, binding: binding), systemImage: command.sfSymbol)
                    }
                    .keyboardShortcut(binding?.menuShortcut)
                }
            }
        }
    }

    @ViewBuilder
    private var timerPresets: some View {
        ForEach(NotchTimerPreset.minutes, id: \.self) { minutes in
            Button {
                timer.start(minutes: minutes)
            } label: {
                Text(Duration.seconds(minutes * 60), format: .units(allowed: [.minutes], width: .wide))
            }
        }
        Button("Custom…") { actions.askTimerLength() }
        if timer.end != nil {
            Divider()
            Button("Cancel Timer") { timer.cancel() }
        }
    }
}
