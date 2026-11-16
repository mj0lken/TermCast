import AppKit
import Carbon.HIToolbox
import os

private func windowDragEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<WindowDragMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { monitor.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }

    let location = event.location
    let keyCode =
        type == .keyDown ? Int(event.getIntegerValueField(.keyboardEventKeycode)) : -1
    MainActor.assumeIsolated {
        monitor.process(type: type, location: location, keyCode: keyCode)
    }
    return Unmanaged.passUnretained(event)
}

/// Observes mouse drags for edge/corner drag-to-snap and drag-away unsnap restore.
@MainActor
@Observable
final class WindowDragMonitor: HealthCheckable {
    private enum Phase {
        case idle
        case pressed(down: CGPoint, attempts: Int)
        case probing(down: CGPoint, candidate: WindowMover.DragCandidate, lastCheck: TimeInterval)
        case dragging(
            down: CGPoint, candidate: WindowMover.DragCandidate, pills: [WindowDragSnap.Pill],
            snapCancelled: Bool, unsnapped: Bool, activeTarget: WindowDragSnap.Target?)
        case ignored
    }

    private static let logger = Logger(subsystem: "com.tinycast", category: "WindowDrag")
    private static let candidateDragThreshold: CGFloat = 5
    private static let rejectDragThreshold: CGFloat = 200
    private static let maxCandidateAttempts = 3
    private static let probeInterval: TimeInterval = 0.016

    private(set) var needsAccessibility = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let windowMover: WindowMover
    @ObservationIgnored private let preview = WindowSnapPreviewController()

    @ObservationIgnored private var phase: Phase = .idle
    @ObservationIgnored private var tapPort: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var eventMonitors: [Any] = []
    @ObservationIgnored private var sessionTokens: [NotificationToken] = []
    @ObservationIgnored private var sessionActive = true
    @ObservationIgnored private var loggedTapFailure = false

    @ObservationIgnored weak var healthTicker: HealthTicker?

    init(settings: AppSettings, windowMover: WindowMover) {
        self.settings = settings
        self.windowMover = windowMover
    }

    isolated deinit {
        tearDownMonitors()
    }

    func start() {
        installObserversIfNeeded()
        syncTapPresence()
    }

    func sync() {
        syncTapPresence()
    }

    func prepareForTermination() {
        tearDownMonitors()
        healthTicker?.unsubscribe(self)
    }

    // MARK: - Event processing

    fileprivate func process(type: CGEventType, location: CGPoint, keyCode: Int) {
        switch type {
        case .leftMouseDown:
            if case .dragging(_, let candidate, _, let snapCancelled, _, _) = phase {
                commitIfTargeted(at: location, candidate: candidate, snapCancelled: snapCancelled)
            }
            resetDrag()
            phase = .pressed(down: location, attempts: 0)

        case .leftMouseDragged:
            if case .idle = phase {
                phase = .pressed(down: location, attempts: 0)
            }
            handleDrag(at: location)

        case .leftMouseUp:
            handleMouseUp(at: location)

        case .rightMouseDown:
            cancelActiveSnap()

        case .keyDown:
            if keyCode == kVK_Escape { cancelActiveSnap() }

        default:
            break
        }
    }

    private func handleNSEvent(_ event: NSEvent) {
        let cursor = AXScreens.cursorPosition()
        switch event.type {
        case .leftMouseDown:
            process(type: .leftMouseDown, location: cursor, keyCode: -1)
        case .leftMouseDragged:
            process(type: .leftMouseDragged, location: cursor, keyCode: -1)
        case .leftMouseUp:
            process(type: .leftMouseUp, location: cursor, keyCode: -1)
        case .rightMouseDown:
            process(type: .rightMouseDown, location: cursor, keyCode: -1)
        case .keyDown:
            process(type: .keyDown, location: cursor, keyCode: Int(event.keyCode))
        default:
            break
        }
    }

    private func handleDrag(at cursor: CGPoint) {
        switch phase {
        case .idle, .ignored:
            return

        case .pressed(let down, let attempts):
            guard hypot(cursor.x - down.x, cursor.y - down.y) >= Self.candidateDragThreshold else {
                return
            }
            let probePoint = attempts == 0 ? down : cursor
            guard
                let candidate = windowMover.dragCandidate(
                    at: probePoint, fallback: WindowTarget.current())
            else {
                let next = attempts + 1
                phase =
                    next < Self.maxCandidateAttempts
                    ? .pressed(down: down, attempts: next) : .ignored
                return
            }
            phase = .probing(down: down, candidate: candidate, lastCheck: 0)
            evaluateProbe(down: down, candidate: candidate, cursor: cursor)

        case .probing(let down, let candidate, let lastCheck):
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastCheck >= Self.probeInterval else { return }
            phase = .probing(down: down, candidate: candidate, lastCheck: now)
            evaluateProbe(down: down, candidate: candidate, cursor: cursor)

        case .dragging(let down, let candidate, let pills, let snapCancelled, var unsnapped, _):
            if !unsnapped, settings.windowRestoreOnDrag, let restore = candidate.restoreFrame,
                let current = windowMover.currentFrame(of: candidate),
                let restored = WindowDragSnap.unsnapFrame(
                    initialWindowFrame: candidate.initialFrame, initialCursor: down,
                    currentWindowFrame: current, currentCursor: cursor, restoreSize: restore.size,
                    in: candidate.screens)
            {
                _ = windowMover.unsnapDraggedWindow(candidate, to: restored)
                unsnapped = true
            }

            let target = resolveSnapTarget(
                at: cursor, candidate: candidate, cancelled: snapCancelled)
            updateOverlay(target: target, pills: pills, cancelled: snapCancelled, candidate: candidate)
            phase = .dragging(
                down: down, candidate: candidate, pills: pills, snapCancelled: snapCancelled,
                unsnapped: unsnapped, activeTarget: target)
        }
    }

    private func evaluateProbe(
        down: CGPoint, candidate: WindowMover.DragCandidate, cursor: CGPoint
    ) {
        guard let current = windowMover.currentFrame(of: candidate) else {
            phase = .ignored
            return
        }
        let tolerance = WindowActionMemory<Int>.tolerance
        let resized =
            abs(current.width - candidate.initialFrame.width) > tolerance
            || abs(current.height - candidate.initialFrame.height) > tolerance
        if resized {
            phase = .ignored
            return
        }
        let moved =
            hypot(
                current.minX - candidate.initialFrame.minX,
                current.minY - candidate.initialFrame.minY) >= 2
        guard moved else {
            if hypot(cursor.x - down.x, cursor.y - down.y) >= Self.rejectDragThreshold {
                phase = .ignored
            }
            return
        }

        var unsnapped = false
        if settings.windowRestoreOnDrag, let restore = candidate.restoreFrame,
            let restored = WindowDragSnap.unsnapFrame(
                initialWindowFrame: candidate.initialFrame, initialCursor: down,
                currentWindowFrame: current, currentCursor: cursor, restoreSize: restore.size,
                in: candidate.screens)
        {
            _ = windowMover.unsnapDraggedWindow(candidate, to: restored)
            unsnapped = true
        }

        let options = snapOptions
        let pills = WindowDragSnap.activationPills(in: candidate.screens, options: options)
        let target = resolveSnapTarget(at: cursor, candidate: candidate, cancelled: false)
        updateOverlay(target: target, pills: pills, cancelled: false, candidate: candidate)
        phase = .dragging(
            down: down, candidate: candidate, pills: pills, snapCancelled: false,
            unsnapped: unsnapped, activeTarget: target)
    }

    private func handleMouseUp(at cursor: CGPoint) {
        defer { resetDrag() }
        guard case .dragging(_, let candidate, _, let snapCancelled, _, _) = phase else { return }
        commitIfTargeted(at: cursor, candidate: candidate, snapCancelled: snapCancelled)
    }

    private func commitIfTargeted(
        at cursor: CGPoint, candidate: WindowMover.DragCandidate, snapCancelled: Bool
    ) {
        guard !snapCancelled, settings.windowSnapByDragging else { return }
        let target = resolveSnapTarget(at: cursor, candidate: candidate, cancelled: false)
        preview.hide()
        guard let target else { return }
        _ = windowMover.commitDragSnap(
            target, for: candidate, gap: CGFloat(settings.windowGap),
            fitTightlyToEdges: settings.windowFitTightlyToEdges)
    }

    private func cancelActiveSnap() {
        guard
            case .dragging(let down, let candidate, let pills, _, let unsnapped, _) = phase
        else { return }
        preview.hide()
        phase = .dragging(
            down: down, candidate: candidate, pills: pills, snapCancelled: true,
            unsnapped: unsnapped, activeTarget: nil)
    }

    private var snapOptions: WindowDragSnap.Options {
        WindowDragSnap.Options(
            edgeWidth: settings.windowActivationEdgeWidth,
            areaScale: settings.windowActivationAreaScale,
            disabledZones: Set(
                settings.windowDisabledActivationAreas.compactMap(WindowActivationZone.init(rawValue:)))
        )
    }

    private func resolveSnapTarget(
        at cursor: CGPoint, candidate: WindowMover.DragCandidate, cancelled: Bool
    ) -> WindowDragSnap.Target? {
        guard !cancelled, settings.windowSnapByDragging else { return nil }
        return WindowDragSnap.target(
            at: cursor, in: candidate.screens, gap: CGFloat(settings.windowGap),
            fitTightlyToEdges: settings.windowFitTightlyToEdges, options: snapOptions)
    }

    private func updateOverlay(
        target: WindowDragSnap.Target?, pills: [WindowDragSnap.Pill], cancelled: Bool,
        candidate: WindowMover.DragCandidate
    ) {
        let showsPills =
            !cancelled && settings.windowSnapByDragging && settings.windowHighlightActivationAreas
        preview.update(
            target: target, pills: pills, showsPills: showsPills, screens: candidate.screens,
            geometry: candidate.geometry)
    }

    private func resetDrag() {
        phase = .idle
        preview.hide()
    }

    // MARK: - Monitor lifecycle

    private var isWanted: Bool {
        settings.windowManagementEnabled
            && (settings.windowSnapByDragging || settings.windowRestoreOnDrag)
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
        resetDrag()
        syncTapPresence()
    }

    private func syncTapPresence() {
        guard isWanted, sessionActive else {
            tearDownMonitors()
            healthTicker?.unsubscribe(self)
            needsAccessibility = false
            return
        }
        healthTicker?.subscribe(self)
        needsAccessibility = !Permissions.isAccessibilityTrusted()
        if Permissions.isAccessibilityTrusted() {
            installTapIfNeeded()
        } else {
            tearDownTap()
        }
        if tapPort == nil {
            installFallbackMonitorsIfNeeded()
        } else {
            tearDownFallbackMonitors()
        }
    }

    private func installTapIfNeeded() {
        guard tapPort == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap,
                place: .tailAppendEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: windowDragEventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
                ?? CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .tailAppendEventTap,
                    options: .listenOnly,
                    eventsOfInterest: mask,
                    callback: windowDragEventTapCallback,
                    userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            if !loggedTapFailure {
                Self.logger.notice("Falling back to NSEvent monitor for window drag snapping")
                loggedTapFailure = true
            }
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return
        }
        loggedTapFailure = false
        tapPort = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func installFallbackMonitorsIfNeeded() {
        guard eventMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .keyDown
        ]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleNSEvent(event)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }
        eventMonitors = [global, local].compactMap { $0 }
    }

    private func tearDownMonitors() {
        tearDownTap()
        tearDownFallbackMonitors()
    }

    private func tearDownTap() {
        resetDrag()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
    }

    private func tearDownFallbackMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
    }

    fileprivate func tapWasDisabled() {
        resetDrag()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    func healthCheck() {
        guard isWanted, sessionActive else { return }
        let trusted = Permissions.isAccessibilityTrusted()
        needsAccessibility = !trusted
        if trusted {
            if tapPort == nil {
                installTapIfNeeded()
                if tapPort != nil { tearDownFallbackMonitors() }
            } else if let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) {
                resetDrag()
                CGEvent.tapEnable(tap: tapPort, enable: true)
            }
        } else {
            if tapPort != nil { tearDownTap() }
            installFallbackMonitorsIfNeeded()
        }
    }
}
