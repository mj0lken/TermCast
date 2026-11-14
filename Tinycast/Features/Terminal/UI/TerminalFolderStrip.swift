import SwiftUI

struct TerminalFolderStrip: View {
    @Environment(TerminalStore.self) private var store
    @Environment(TerminalCoordinator.self) private var coordinator
    @Environment(PaletteState.self) private var vm
    @Environment(\.metrics) private var metrics

    let openFolderMenu: (CGRect) -> Void

    @State private var folderButtonFrame: CGRect = .zero
    @State private var folderHovered = false
    @State private var tabsHovered = false
    @State private var cycleHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)

            HStack(spacing: metrics.spacing.md) {
                Button {
                    openFolderMenu(folderButtonFrame)
                } label: {
                    HStack(spacing: metrics.spacing.sm) {
                        Image(systemName: "folder")
                            .font(.system(size: metrics.scaled(11), weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(store.displayActiveDirectory)
                            .font(
                                .system(
                                    size: metrics.scaled(11.5), weight: .medium,
                                    design: .monospaced)
                            )
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: metrics.scaled(9), weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(.horizontal, metrics.spacing.md)
                    .padding(.vertical, metrics.spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous)
                            .fill(folderHovered ? Theme.Colors.controlHover : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { folderHovered = $0 }
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    folderButtonFrame = $0
                }
                .help(String(localized: "Choose working directory"))

                if vm.mode == .launcher, !store.tabs.isEmpty {
                    Button {
                        coordinator.navigateToTerminal()
                    } label: {
                        HStack(spacing: metrics.spacing.xs) {
                            Circle()
                                .fill(
                                    store.tabs.contains(where: \.isRunning)
                                        ? Theme.Colors.success : Theme.Colors.textTertiary
                                )
                                .frame(width: metrics.scaled(6), height: metrics.scaled(6))
                            Text(tabsBadgeText)
                                .font(.system(size: metrics.scaled(11), weight: .medium))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(.horizontal, metrics.spacing.md)
                        .padding(.vertical, metrics.spacing.xxs)
                        .background(
                            Capsule()
                                .fill(
                                    tabsHovered
                                        ? Theme.Colors.controlHover : Theme.Colors.controlSurface)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { tabsHovered = $0 }
                    .help(String(localized: "Open Terminal tabs  >"))
                }

                Spacer(minLength: 0)

                if store.recentFolders.count > 1 {
                    Button {
                        _ = coordinator.handleShiftTab()
                    } label: {
                        HStack(spacing: metrics.spacing.xs) {
                            Text("Recent Folder")
                                .font(.system(size: metrics.scaled(11), weight: .regular))
                                .foregroundStyle(
                                    cycleHovered
                                        ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                            KeyCapChip(text: "⇧⇥", style: .outline)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, metrics.spacing.xs)
                        .padding(.vertical, metrics.spacing.xxs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { cycleHovered = $0 }
                    .help(String(localized: "Cycle recent folders  ⇧⇥"))
                }
            }
            .padding(.horizontal, metrics.spacing.md * 2)
            .padding(.vertical, metrics.spacing.xs)

            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)
        }
    }

    private var tabsBadgeText: String {
        let count = store.tabs.count
        return count == 1
            ? String(localized: "1 tab")
            : String(localized: "\(count) tabs")
    }
}
