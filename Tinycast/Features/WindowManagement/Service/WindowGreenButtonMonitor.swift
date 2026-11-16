import AppKit
import Carbon.HIToolbox

/// Observes pointer hover over window green traffic-light buttons to present a tiling popover.
@MainActor
@Observable
final class WindowGreenButtonMonitor: HealthCheckable {
    private static let checkInterval: TimeInterval = 0.08
    private static let dismissalPadding: CGFloat = 18

    private(set) var needsAccessibility = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let windowMover: WindowMover
    @ObservationIgnored private let customSizes: CustomWindowSizeStore
    @ObservationIgnored private let hotKeys: HotKeyManager
    @ObservationIgnored private let menu = WindowGreenButtonMenuController()

    @ObservationIgnored private var eventMonitors: [Any] = []
    @ObservationIgnored private var sessionTokens: [NotificationToken] = []
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var pendingButtonRect: CGRect?
    @ObservationIgnored private var activeTarget: WindowMover.GreenButtonTarget?
    @ObservationIgnored private var lastProbeTime: TimeInterval = 0
    @ObservationIgnored private var sessionActive = true

    @ObservationIgnored weak var healthTicker: HealthTicker?

    init(
        settings: AppSettings, windowMover: WindowMover, customSizes: CustomWindowSizeStore,
        hotKeys: HotKeyManager
    ) {
        self.settings = settings
        self.windowMover = windowMover
        self.customSizes = customSizes
        self.hotKeys = hotKeys
    }

    isolated deinit {
        tearDownMonitors()
    }

    func start() {
        installObserversIfNeeded()
        sync()
    }

    func sync() {
        guard isWanted, sessionActive else {
            tearDownMonitors()
            dismissAll()
            healthTicker?.unsubscribe(self)
            needsAccessibility = false
            return
        }
        healthTicker?.subscribe(self)
        needsAccessibility = !Permissions.isAccessibilityTrusted()
        installMonitorsIfNeeded()
    }

    func prepareForTermination() {
        tearDownMonitors()
        dismissAll()
        healthTicker?.unsubscribe(self)
    }

    func healthCheck() {
        guard isWanted, sessionActive else { return }
        needsAccessibility = !Permissions.isAccessibilityTrusted()
    }

    // MARK: - Event handling

    private func handleEvent(_ event: NSEvent) {
        let cursor = AXScreens.cursorPosition()

        switch event.type {
        case .mouseMoved:
            handleMouseMoved(at: cursor)

        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            if menu.isShowing {
                if !menu.menuFrameInAX.contains(cursor) {
                    dismissAll()
                }
            } else {
                cancelPendingHover()
            }

        case .keyDown:
            if Int(event.keyCode) == kVK_Escape {
                dismissAll()
            }

        default:
            break
        }
    }

    private func handleMouseMoved(at cursor: CGPoint) {
        if menu.isShowing, let buttonFrame = menu.activeButtonFrame {
            let safeMenu = menu.menuFrameInAX.insetBy(
                dx: -Self.dismissalPadding, dy: -Self.dismissalPadding)
            let safeButton = buttonFrame.insetBy(dx: -12, dy: -12)
            let bridge = CGRect(
                x: min(buttonFrame.minX, safeMenu.minX),
                y: buttonFrame.minY,
                width: max(buttonFrame.width, 120),
                height: max(12, safeMenu.minY - buttonFrame.minY + 12))
            if safeMenu.contains(cursor) || safeButton.contains(cursor) || bridge.contains(cursor) {
                return
            }
            dismissAll()
        }

        if let pending = pendingButtonRect {
            if pending.insetBy(dx: -6, dy: -6).contains(cursor) {
                return
            }
            cancelPendingHover()
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProbeTime >= Self.checkInterval else { return }
        lastProbeTime = now

        guard
            let target = windowMover.greenButtonTarget(
                at: cursor, kind: settings.windowGreenButtonTarget)
        else { return }
        pendingButtonRect = target.buttonFrame
        let rawDelay = WindowTrafficLightButton.sanitizedHoverDelay(
            settings.windowGreenButtonHoverDelay)
        let delayMs = settings.windowGreenButtonTarget == .green ? min(rawDelay, 380) : rawDelay
        hoverTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delayMs))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.presentMenuIfStillHovered()
        }
    }

    private func presentMenuIfStillHovered() {
        let cursor = AXScreens.cursorPosition()
        guard
            let target = windowMover.greenButtonTarget(
                at: cursor, kind: settings.windowGreenButtonTarget)
        else {
            cancelPendingHover()
            return
        }
        pendingButtonRect = nil
        hoverTask = nil
        activeTarget = target
        menu.show(
            for: target,
            customSizes: customSizes.sizes,
            hotKeys: hotKeys,
            onButtonClick: { [weak self] in
                guard let self, let active = self.activeTarget else { return }
                self.activeTarget = nil
                self.windowMover.clickTrafficLightButton(active)
            },
            onCommand: { [weak self] command in
                guard let self, let active = self.activeTarget else { return }
                self.activeTarget = nil
                _ = self.windowMover.perform(
                    command, on: active, gap: CGFloat(self.settings.windowGap),
                    cycle: self.settings.windowCycle,
                    wrapsDisplays: self.settings.windowWrapsDisplays,
                    keepsProportions: self.settings.windowKeepsProportions,
                    fitTightlyToEdges: self.settings.windowFitTightlyToEdges)
            },
            onCustomSize: { [weak self] size in
                guard let self, let active = self.activeTarget else { return }
                self.activeTarget = nil
                _ = self.windowMover.perform(
                    size, on: active, gap: CGFloat(self.settings.windowGap),
                    fitTightlyToEdges: self.settings.windowFitTightlyToEdges)
            })
    }

    private func cancelPendingHover() {
        hoverTask?.cancel()
        hoverTask = nil
        pendingButtonRect = nil
    }

    private func dismissAll() {
        cancelPendingHover()
        activeTarget = nil
        menu.hide()
    }

    // MARK: - Lifecycle

    private var isWanted: Bool {
        settings.windowManagementEnabled && settings.windowGreenButtonMenu
    }

    private func installObserversIfNeeded() {
        guard sessionTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.sessionDidChange(active: false) }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.sessionDidChange(active: true) }
                }, center: center)
        ]
    }

    private func sessionDidChange(active: Bool) {
        sessionActive = active
        sync()
    }

    private func installMonitorsIfNeeded() {
        guard eventMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown
        ]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
        eventMonitors = [global, local].compactMap { $0 }
    }

    private func tearDownMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
    }
}
