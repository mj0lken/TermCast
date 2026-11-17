import SwiftUI

/// The tray's top band: tabs before the cutout, the shortcut row and battery readout after it.
struct NotchOpenHeaderBar: View {
    let state: NotchOpenTrayState
    let shelfCount: Int
    let runningTerminalCount: Int
    let battery: BatteryStatusService
    let timer: NotchTimer
    let shortcuts: NotchShortcutActions

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.xs) {
                NotchTabButton(
                    symbol: "house.fill",
                    label: String(localized: "Home"),
                    isSelected: state.tab == .home,
                    badgeCount: 0
                ) {
                    state.tab = .home
                }

                NotchTabButton(
                    symbol: "tray.fill",
                    label: String(localized: "Shelf"),
                    isSelected: state.tab == .shelf,
                    badgeCount: shelfCount
                ) {
                    state.tab = .shelf
                }

                if state.showsTerminal {
                    NotchTabButton(
                        symbol: "apple.terminal.fill",
                        label: String(localized: "Terminal Sessions"),
                        isSelected: state.tab == .terminal,
                        badgeCount: runningTerminalCount
                    ) {
                        state.tab = .terminal
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.layout.isNotched {
                ZStack {
                    Color.clear
                        .frame(width: state.layout.notchWidth, height: state.layout.headerHeight)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Spacer(minLength: 0)

                if let metric = state.inlineHUDMetric {
                    NotchInlineOpenHUDChip(metric: metric)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    ForEach(state.shortcuts, id: \.self) { shortcut in
                        NotchShortcutButton(shortcut: shortcut, timer: timer, actions: shortcuts)
                    }

                    if state.showsBattery, battery.status.hasBattery {
                        NotchBatteryBadge(status: battery.status)
                    }
                }
            }
            .padding(.trailing, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.16), value: state.inlineHUDMetric)
    }
}

private struct NotchHeaderIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHovering ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isHovering ? Theme.Colors.controlHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct NotchTabButton: View {
    let symbol: String
    let label: String
    let isSelected: Bool
    let badgeCount: Int
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
            .padding(.horizontal, 12)
            .frame(height: 24)
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

    private static let windowGroups: Set<WindowCommand.Group> = [.halves, .quarters, .sizing]

    var body: some View {
        switch shortcut {
        case .clipboard, .notebook, .camera, .settings:
            NotchHeaderIconButton(symbol: shortcut.symbol, label: shortcut.title) {
                actions.open(shortcut)
            }
        case .windowManagement:
            menu { windowCommands }
        case .timer:
            menu { timerPresets }
        }
    }

    private func menu(@ViewBuilder _ content: () -> some View) -> some View {
        Menu(content: content) {
            Image(systemName: shortcut.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 24, height: 24)
        .help(shortcut.title)
        .accessibilityLabel(shortcut.title)
    }

    /// The placements worth a click; the rest of the catalog stays on its shortcuts and the launcher.
    @ViewBuilder
    private var windowCommands: some View {
        let groups = WindowCommandCatalog.grouped().filter { Self.windowGroups.contains($0.group) }
        ForEach(groups, id: \.group) { entry in
            Section(entry.group.title) {
                ForEach(entry.commands) { command in
                    Button {
                        actions.runWindowCommand(command.id)
                    } label: {
                        Label(command.name, systemImage: command.sfSymbol)
                    }
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
        if timer.end != nil {
            Divider()
            Button("Cancel Timer") { timer.cancel() }
        }
    }
}
