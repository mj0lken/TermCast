import AppKit
import CoreGraphics
import SwiftUI

/// Presents, extends, rubber-bands and retracts the hardware-blended `NotchHUDPanel`.
@MainActor
final class NotchHUDController {
    private static let collapseSettleDuration: TimeInterval = 0.28

    private let state = NotchHUDState()

    var style: NotchHUDStyle {
        get { state.style }
        set { if state.style != newValue { state.style = newValue } }
    }
    private var panel: NotchHUDPanel?
    private var activeScreenFrame: CGRect?
    private var dismissTask: Task<Void, Never>?
    private var overshootTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    func present(
        metric: NotchHUDMetric,
        overshoot: Double = 0,
        preferredDisplayID: CGDirectDisplayID? = nil
    ) {
        guard let screen = resolveScreen(preferredDisplayID: preferredDisplayID) else { return }
        let screenMetrics = Self.metrics(for: screen)
        let layout = NotchHUDGeometry.resolve(
            screen: screenMetrics,
            isToast: metric.isToast,
            overshoot: overshoot)

        collapseTask?.cancel()
        collapseTask = nil
        overshootTask?.cancel()
        overshootTask = nil

        let panel = ensurePanel()
        panel.hasShadow = !layout.isNotched

        let frameChanged = panel.frame != layout.panelFrame || activeScreenFrame != screen.frame
        if !panel.isVisible || frameChanged {
            panel.setFrame(layout.panelFrame, display: true)
            activeScreenFrame = screen.frame
        }

        state.metric = metric
        state.layout = layout

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        withAnimation(Theme.NotchMotion.wing) {
            state.isExpanded = true
        }

        if abs(overshoot) > 0.001 {
            scheduleOvershootSnapBack(screenMetrics: screenMetrics, isToast: metric.isToast)
        }

        scheduleDismiss(after: metric.dwell)
    }

    func dismissImmediately() {
        dismissTask?.cancel()
        dismissTask = nil
        overshootTask?.cancel()
        overshootTask = nil
        collapseTask?.cancel()
        collapseTask = nil
        state.isExpanded = false
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NotchHUDPanel {
        if let panel { return panel }
        let created = NotchHUDPanel()
        let host = NSHostingView(rootView: NotchHUDView(state: state).motionScope())
        host.sizingOptions = []
        created.contentView = host
        panel = created
        return created
    }

    private func scheduleOvershootSnapBack(
        screenMetrics: NotchHUDGeometry.ScreenMetrics,
        isToast: Bool
    ) {
        overshootTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NotchHUDMetric.overshootResetDelay))
            guard !Task.isCancelled, let self else { return }
            self.state.layout = NotchHUDGeometry.resolve(
                screen: screenMetrics,
                isToast: isToast,
                overshoot: 0)
        }
    }

    private func scheduleDismiss(after dwell: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled, let self else { return }
            self.retractAndOrderOut()
        }
    }

    private func retractAndOrderOut() {
        guard let panel, panel.isVisible else { return }
        withAnimation(Theme.NotchMotion.wing) {
            state.isExpanded = false
        }
        let settle = Motion.duration(Self.collapseSettleDuration)
        guard settle > 0 else {
            panel.orderOut(nil)
            return
        }
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(settle))
            guard !Task.isCancelled, let self, !self.state.isExpanded else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func resolveScreen(preferredDisplayID: CGDirectDisplayID?) -> NSScreen? {
        if let preferredDisplayID,
            let matched = NSScreen.screens.first(where: { $0.displayID == preferredDisplayID })
        {
            return matched
        }
        return NSScreen.underCursor ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func metrics(for screen: NSScreen) -> NotchHUDGeometry.ScreenMetrics {
        NotchHUDGeometry.ScreenMetrics(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea)
    }
}
