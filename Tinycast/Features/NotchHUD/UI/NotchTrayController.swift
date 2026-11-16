import AppKit
import SwiftUI

/// Coordinates the passive `NotchSensorPanel` and the interactive expanded `NotchTrayPanel`.
@MainActor
final class NotchTrayController {
    private static let collapseSettleDuration: TimeInterval = 0.26
    private static let hoverExitGrace: TimeInterval = 0.22

    var refreshCalendarState: (() -> (enabled: Bool, hasAccess: Bool, events: [MeetingEvent]))?
    var onOpenClipboard: (() -> Void)?
    var onOpenCamera: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onEnableCalendar: (() -> Void)?
    var onJoinMeeting: ((MeetingEvent) -> Void)?

    private let state = NotchOpenTrayState()
    private let settings: AppSettings
    private let nowPlaying: NowPlayingService
    private let shelfStore: NotchShelfStore
    private let battery: BatteryStatusService

    private var sensorPanel: NotchSensorPanel?
    private var trayPanel: NotchTrayPanel?
    private var screenObserver: NotificationToken?
    private var hoverOpenTask: Task<Void, Never>?
    private var hoverExitTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var inlineHUDTask: Task<Void, Never>?
    private var globalClickMonitor: Any?

    init(
        settings: AppSettings,
        nowPlaying: NowPlayingService,
        shelfStore: NotchShelfStore,
        battery: BatteryStatusService
    ) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.shelfStore = shelfStore
        self.battery = battery
    }

    var isOpen: Bool {
        state.isExpanded && (trayPanel?.isVisible == true)
    }

    func startSensor() {
        updateSensorPlacement()
        guard screenObserver == nil else { return }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSensorPlacement()
            }
        }
        screenObserver = NotificationToken(token, center: center)
    }

    func stopAll() {
        hoverOpenTask?.cancel()
        hoverOpenTask = nil
        hoverExitTask?.cancel()
        hoverExitTask = nil
        collapseTask?.cancel()
        collapseTask = nil
        inlineHUDTask?.cancel()
        inlineHUDTask = nil
        removeGlobalClickMonitor()
        screenObserver = nil
        state.isExpanded = false
        sensorPanel?.orderOut(nil)
        trayPanel?.orderOut(nil)
    }

    func open(preferredTab: NotchTab? = nil) {
        hoverOpenTask?.cancel()
        hoverOpenTask = nil
        hoverExitTask?.cancel()
        hoverExitTask = nil
        collapseTask?.cancel()
        collapseTask = nil

        guard let screen = targetScreen() else { return }
        let metrics = Self.metrics(for: screen)
        let layout = NotchHUDGeometry.resolveOpenTray(screen: metrics)

        if let preferredTab {
            state.tab = preferredTab
        } else if !settings.notchRemembersLastTab {
            state.tab = .home
        }

        state.showsMedia = settings.notchShowsMedia
        state.showsCalendar = settings.notchShowsCalendar
        state.showsBattery = settings.notchShowsBattery
        state.showsClipboard = settings.notchShowsClipboard && settings.clipboardEnabled
        state.hidesAllDayEvents = settings.notchHidesAllDayEvents
        state.style = NotchHUDStyle(
            showsPercentage: settings.notchShowsPercentage,
            tintsAccent: settings.notchTintsAccent)
        if state.showsCalendar { syncCalendarData() }
        if state.showsMedia { nowPlaying.resume() }

        let panel = ensureTrayPanel()
        panel.hasShadow = !layout.isNotched
        panel.setFrame(layout.panelFrame, display: true)
        panel.installTracking()
        state.layout = layout

        sensorPanel?.orderOut(nil)

        let wasHidden = !panel.isVisible
        if wasHidden {
            state.isExpanded = false
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            panel.orderFrontRegardless()
        }
        if settings.notchHapticsEnabled, !state.isExpanded {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        installGlobalClickMonitor()
        guard wasHidden else {
            withAnimation(Theme.NotchMotion.wing) { state.isExpanded = true }
            return
        }
        // Let the collapsed frame commit first, or the spring starts from a half-drawn state.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.trayPanel?.isVisible == true else { return }
            withAnimation(Theme.NotchMotion.wing) { self.state.isExpanded = true }
        }
    }

    func close() {
        hoverOpenTask?.cancel()
        hoverOpenTask = nil
        hoverExitTask?.cancel()
        hoverExitTask = nil
        removeGlobalClickMonitor()

        guard let panel = trayPanel, panel.isVisible else {
            updateSensorPlacement()
            return
        }

        withAnimation(Theme.NotchMotion.wing) {
            state.isExpanded = false
        }
        let settle = Motion.duration(Self.collapseSettleDuration)
        guard settle > 0 else {
            panel.orderOut(nil)
            updateSensorPlacement()
            return
        }
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(settle))
            guard !Task.isCancelled, let self, !self.state.isExpanded else { return }
            self.trayPanel?.orderOut(nil)
            self.updateSensorPlacement()
        }
    }

    func showInlineHUD(metric: NotchHUDMetric) {
        state.inlineHUDMetric = metric
        inlineHUDTask?.cancel()
        inlineHUDTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(metric.dwell))
            guard !Task.isCancelled else { return }
            self?.state.inlineHUDMetric = nil
        }
    }

    func syncCalendarData() {
        guard let refreshed = refreshCalendarState?() else { return }
        state.isCalendarEnabled = refreshed.enabled
        state.hasCalendarAccess = refreshed.hasAccess
        state.weekEvents = refreshed.events
    }

    // MARK: - Sensor & Hover Handling

    private func updateSensorPlacement() {
        guard settings.notchShelfEnabled, !isOpen, let screen = targetScreen() else {
            sensorPanel?.orderOut(nil)
            return
        }
        let sensor = ensureSensorPanel()
        let frame = NotchHUDGeometry.sensorFrame(for: Self.metrics(for: screen))
        sensor.setFrame(frame, display: false)
        if !sensor.isVisible {
            sensor.orderFrontRegardless()
        }
    }

    private func ensureSensorPanel() -> NotchSensorPanel {
        if let sensorPanel { return sensorPanel }
        let created = NotchSensorPanel()
        created.onHoverChanged = { [weak self] hovering in
            self?.handleSensorHover(hovering)
        }
        created.onClicked = { [weak self] in
            self?.open()
        }
        created.onSwipeDown = { [weak self] in
            self?.open()
        }
        created.onDragEntered = { [weak self] in
            self?.open(preferredTab: .shelf)
        }
        sensorPanel = created
        return created
    }

    private func ensureTrayPanel() -> NotchTrayPanel {
        if let trayPanel { return trayPanel }
        let created = NotchTrayPanel()
        let view = NotchOpenTrayView(
            state: state,
            nowPlaying: nowPlaying,
            shelfStore: shelfStore,
            battery: battery,
            onOpenClipboard: { [weak self] in
                self?.close()
                self?.onOpenClipboard?()
            },
            onOpenCamera: { [weak self] in
                self?.close()
                self?.onOpenCamera?()
            },
            menu: NotchAppMenuActions(
                openNotchSettings: { [weak self] in
                    self?.close()
                    self?.onOpenSettings?()
                }),
            onEnableCalendar: { [weak self] in
                self?.close()
                self?.onEnableCalendar?()
            },
            onJoinMeeting: { [weak self] meeting in
                self?.close()
                self?.onJoinMeeting?(meeting)
            })
        let host = NSHostingView(rootView: view.motionScope())
        host.sizingOptions = []
        created.contentView = host
        created.onPointerHoverChanged = { [weak self] inside in
            self?.handleTrayHover(inside)
        }
        created.onSwipeUp = { [weak self] in
            self?.close()
        }
        created.onEscape = { [weak self] in
            self?.close()
        }
        trayPanel = created
        return created
    }

    private func handleSensorHover(_ hovering: Bool) {
        hoverOpenTask?.cancel()
        hoverOpenTask = nil
        guard hovering, settings.notchOpenOnHover else { return }
        let delay = max(settings.notchHoverDelay, 0.08)
        hoverOpenTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            guard let sensor = self.sensorPanel,
                NSMouseInRect(NSEvent.mouseLocation, sensor.frame, false)
            else { return }
            self.open()
        }
    }

    private func handleTrayHover(_ inside: Bool) {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        guard !inside else { return }
        hoverExitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.hoverExitGrace))
            guard !Task.isCancelled, let self, self.isOpen else { return }
            if NSEvent.pressedMouseButtons != 0 { return }
            guard let panel = self.trayPanel,
                !NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
            else { return }
            self.close()
        }
    }

    private func installGlobalClickMonitor() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isOpen, let panel = self.trayPanel else { return }
                if !NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) {
                    self.close()
                }
            }
        }
    }

    private func removeGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    private func targetScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.primary ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func metrics(for screen: NSScreen) -> NotchHUDGeometry.ScreenMetrics {
        NotchHUDGeometry.ScreenMetrics(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea)
    }
}
