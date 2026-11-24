import SwiftUI

struct NotchOpenTrayView: View {
    let state: NotchOpenTrayState
    let nowPlaying: NowPlayingService
    let shelfStore: NotchShelfStore
    let battery: BatteryStatusService
    let timer: NotchTimer
    let terminal: NotchTerminalActions
    let shortcuts: NotchShortcutActions
    let onEnableCalendar: () -> Void
    let onJoinMeeting: (MeetingEvent) -> Void

    private var layout: NotchHUDGeometry.OpenTrayLayout { state.layout }

    private var targetLeftExt: CGFloat {
        guard layout.isNotched else { return 0 }
        let trayStart = layout.earRadius
        return max(layout.notchOriginX - trayStart, 0)
    }

    private var targetRightExt: CGFloat {
        guard layout.isNotched else { return 0 }
        let trayEnd = layout.earRadius + layout.trayWidth
        return max(trayEnd - (layout.notchOriginX + layout.notchWidth), 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            trayBackdrop
                .frame(
                    width: layout.panelFrame.width,
                    height: state.isExpanded ? layout.trayHeight : layout.headerHeight,
                    alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 0) {
                NotchOpenHeaderBar(
                    state: state,
                    shelfCount: shelfStore.items.count,
                    runningTerminalCount: state.showsTerminal
                        ? NotchTerminalSession.runningCount(in: terminal.sessions()) : 0,
                    battery: battery,
                    timer: timer,
                    shortcuts: shortcuts
                )
                .frame(width: layout.trayWidth, height: layout.headerHeight)

                Group {
                    switch state.tab {
                    case .home:
                        NotchHomeBodyView(
                            state: state,
                            nowPlaying: nowPlaying,
                            onEnableCalendar: onEnableCalendar,
                            onJoinMeeting: onJoinMeeting)
                    case .shelf:
                        NotchShelfBodyView(shelfStore: shelfStore)
                    case .terminal:
                        NotchTerminalBodyView(actions: terminal)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.lg)
                .frame(
                    width: layout.trayWidth,
                    height: max(layout.trayHeight - layout.headerHeight, 0))
            }
            .opacity(state.isExpanded ? 1 : 0)
            .blur(radius: state.isExpanded ? 0 : 6)
        }
        .frame(
            width: layout.panelFrame.width,
            height: layout.panelFrame.height,
            alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.notchHUDStyle, state.style)
        .animation(Theme.NotchMotion.wing, value: state.isExpanded)
        .animation(Theme.NotchMotion.wing, value: state.tab)
    }

    @ViewBuilder
    private var trayBackdrop: some View {
        if layout.isNotched {
            let shape = NotchWingShape(
                notchOriginX: layout.notchOriginX,
                notchWidth: layout.notchWidth,
                leftExtension: state.isExpanded ? targetLeftExt : 0,
                rightExtension: state.isExpanded ? targetRightExt : 0,
                earRadius: layout.earRadius,
                innerCornerRadius: layout.cornerRadius)
            // No rim: any stroke beside the cutout reads as a seam against the bezel.
            shape.fill(Theme.Colors.notchHardwareBlack)
        } else {
            let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
            shape
                .fill(Theme.Colors.notchHardwareBlack)
                .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: Theme.Size.hairline))
                .frame(width: layout.trayWidth)
                .scaleEffect(
                    x: state.isExpanded ? 1 : 0.72,
                    y: state.isExpanded ? 1 : 0.4,
                    anchor: .top)
                .opacity(state.isExpanded ? 1 : 0)
        }
    }
}

struct NotchShortcutActions {
    /// A button that only opens something; the tray closes before it runs.
    let open: (NotchShortcut) -> Void
    let runWindowCommand: (WindowCommand.ID) -> Void
    let snippets: () -> [NotchSnippetChoice]
    let expandSnippet: (NotchSnippetChoice.ID) -> Void
}

/// One line of the Snippets shortcut's menu.
struct NotchSnippetChoice: Identifiable {
    let id: String
    let name: String
}

struct NotchTerminalActions {
    let sessions: () -> [NotchTerminalSession]
    let open: (NotchTerminalSession.ID) -> Void
    let openTerminal: () -> Void
}
