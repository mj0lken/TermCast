import SwiftUI

/// The Terminal page: every live session, running ones first.
struct NotchTerminalBodyView: View {
    let actions: NotchTerminalActions

    var body: some View {
        let sessions = NotchTerminalSession.ordered(actions.sessions())
        if sessions.isEmpty {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "apple.terminal")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text("No terminal sessions")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button("Open Terminal", action: actions.openTerminal)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(sessions) { session in
                        NotchTerminalSessionRow(session: session) {
                            actions.open(session.id)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct NotchTerminalSessionRow: View {
    let session: NotchTerminalSession
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Circle()
                    .fill(session.isRunning ? Theme.Colors.success : Theme.Colors.textTertiary)
                    .frame(width: 7, height: 7)

                Text(verbatim: session.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                Text(verbatim: session.directory)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer(minLength: Theme.Spacing.sm)

                Text(verbatim: session.isRunning ? String(localized: "Running") : String(localized: "Idle"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(session.isRunning ? Theme.Colors.success : Theme.Colors.textTertiary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovering ? Theme.Colors.controlHover : Theme.Colors.rowHover)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
