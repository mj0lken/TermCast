import AppKit
import SwiftUI

struct TerminalActiveSessionsBadge: View {
    @Environment(TerminalStore.self) private var store
    @Environment(TerminalCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @State private var hovered = false
    @State private var showTooltip = false

    private var summary: TerminalSessionSummary? {
        guard settings.terminalEnabled else { return nil }
        let current = store.sessionSummary
        return current.showsBadge ? current : nil
    }

    var body: some View {
        if let summary {
            let label = summary.tooltipText
            let activeNumber = summary.displayedNumber
            Button {
                hovered = false
                showTooltip = false
                coordinator.openFromActiveSessionsBadge()
            } label: {
                HStack(spacing: metrics.spacing.xs) {
                    statusDot(isActive: activeNumber != nil)
                    if let activeNumber {
                        Text(verbatim: "\(activeNumber)")
                            .font(metrics.typography.keyCap.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(
                                hovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    }
                }
                .padding(.leading, activeNumber != nil ? metrics.spacing.sm : 0)
                .padding(.trailing, activeNumber != nil ? metrics.spacing.md : 0)
                .frame(
                    minWidth: metrics.scaled(24),
                    minHeight: metrics.scaled(24)
                )
                .frame(height: metrics.scaled(24))
                .background(
                    Capsule()
                        .fill(hovered ? Theme.Colors.controlHover : Theme.Colors.controlSurface)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            hovered ? Theme.Colors.border : Theme.Colors.border.opacity(0.5),
                            lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { isHovering in
                hovered = isHovering
                if !isHovering { showTooltip = false }
            }
            .task(id: HoverKey(hovered: hovered, paletteVisible: palette.isVisible)) {
                guard hovered, palette.isVisible else {
                    showTooltip = false
                    return
                }
                try? await Task.sleep(for: .seconds(Motion.duration(Theme.Duration.tooltipDelay)))
                guard !Task.isCancelled, hovered, palette.isVisible else { return }
                showTooltip = true
            }
            .onDisappear {
                hovered = false
                showTooltip = false
            }
            .background(
                FloatingTooltipAnchor(
                    text: label,
                    isPresented: showTooltip && palette.isVisible,
                    metrics: metrics)
            )
            .accessibilityLabel(label.replacingOccurrences(of: "\n", with: ", "))
        }
    }

    @ViewBuilder
    private func statusDot(isActive: Bool) -> some View {
        if isActive {
            ZStack {
                Circle()
                    .fill(Theme.Colors.success.opacity(0.32))
                    .frame(width: metrics.scaled(12), height: metrics.scaled(12))
                    .blur(radius: metrics.scaled(2.2))
                Circle()
                    .fill(Theme.Colors.success)
                    .frame(width: metrics.scaled(6.5), height: metrics.scaled(6.5))
                    .shadow(color: Theme.Colors.success.opacity(0.85), radius: metrics.scaled(3.5))
            }
            .frame(width: metrics.scaled(12), height: metrics.scaled(12))
        } else {
            Circle()
                .fill(hovered ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                .frame(width: metrics.scaled(6), height: metrics.scaled(6))
        }
    }
}

private struct HoverKey: Equatable {
    let hovered: Bool
    let paletteVisible: Bool
}

private struct FloatingTooltipTile: View {
    let text: String
    let metrics: InterfaceMetrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.tooltip, style: .continuous)
        Text(text)
            .font(metrics.typography.keyCap)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.leading)
            .lineSpacing(metrics.spacing.xxs)
            .padding(.horizontal, metrics.spacing.xs)
            .padding(.vertical, metrics.spacing.xxs)
            .frame(minHeight: metrics.size.keyCap)
            .padding(metrics.spacing.xs)
            .background {
                shape.fill(Color(nsColor: .windowBackgroundColor))
                shape.fill(Theme.Colors.controlSurface)
            }
            .overlay(
                shape.strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 0.5)
            )
            .clipShape(shape)
            .fixedSize()
    }
}

private struct FloatingTooltipAnchor: NSViewRepresentable {
    let text: String
    let isPresented: Bool
    let metrics: InterfaceMetrics

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.postsFrameChangedNotifications = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            anchorView: nsView,
            text: text,
            isPresented: isPresented,
            metrics: metrics)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hide()
    }

    @MainActor
    final class Coordinator {
        private var panel: NSPanel?
        private var hosting: NSHostingView<FloatingTooltipTile>?

        isolated deinit {
            panel?.orderOut(nil)
        }

        func update(
            anchorView: NSView,
            text: String,
            isPresented: Bool,
            metrics: InterfaceMetrics
        ) {
            guard isPresented, let parentWindow = anchorView.window, parentWindow.isVisible else {
                hide()
                return
            }

            let tile = FloatingTooltipTile(text: text, metrics: metrics)
            let panel = ensurePanel()
            panel.appearance = anchorView.effectiveAppearance

            if let hosting {
                hosting.rootView = tile
            } else {
                let created = NSHostingView(rootView: tile)
                panel.contentView = created
                hosting = created
            }

            guard let hosting else { return }
            hosting.layoutSubtreeIfNeeded()
            let size = hosting.fittingSize
            guard size.width > 0, size.height > 0 else { return }

            let rectInWindow = anchorView.convert(anchorView.bounds, to: nil)
            let rectOnScreen = parentWindow.convertToScreen(rectInWindow)
            let gap = metrics.spacing.sm
            var x = (rectOnScreen.midX - size.width / 2).rounded()
            let y = (rectOnScreen.minY - gap - size.height).rounded()

            if let screenFrame = parentWindow.screen?.visibleFrame {
                x = min(
                    max(x, screenFrame.minX + gap),
                    screenFrame.maxX - size.width - gap)
            }

            panel.level = NSWindow.Level(rawValue: parentWindow.level.rawValue + 1)
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
            if !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                panel.invalidateShadow()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Motion.duration(Theme.Duration.tooltip)
                    panel.animator().alphaValue = 1
                }
            }
        }

        func hide() {
            guard let panel, panel.isVisible else { return }
            panel.orderOut(nil)
        }

        private func ensurePanel() -> NSPanel {
            if let panel { return panel }
            let created = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            created.isFloatingPanel = true
            created.backgroundColor = .clear
            created.isOpaque = false
            created.hasShadow = true
            created.ignoresMouseEvents = true
            created.hidesOnDeactivate = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel = created
            return created
        }
    }
}
