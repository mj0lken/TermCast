import AppKit
import Carbon.HIToolbox
@preconcurrency import IOKit.hidsystem
import Synchronization

// Snapshot the mutable C global `mach_task_self_`, so actor code never reads it raw.
private let machTaskSelf = mach_task_self_

private func hyperKeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HyperKeyTap.Session>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}

@MainActor
final class HyperKeyTap {
    /// Marker on events this tap posts, so it never reacts to its own synthetics.
    nonisolated static let syntheticTag: Int64 = 0x5459_4354

    var onUnmappedCapsLock: (() -> Void)?
    var onScrollAdjustment: ((HyperScrollEngine.Adjustment) -> Void)?
    var onHoldEnded: (() -> Void)?

    private var route: HyperKeyRoute?
    private var includesShift = true
    private var quickPress: HyperKeyQuickPress = .none
    private var trackpadSliders = false
    private var session: Session?
    private var hidConnect: io_connect_t = IO_OBJECT_NULL

    // Isolated so teardown can release the main-actor IOKit connection.
    isolated deinit {
        tearDown()
        if hidConnect != IO_OBJECT_NULL { IOServiceClose(hidConnect) }
    }

    var isEnabled: Bool? { session?.isEnabled }
    var runLoopSourceIsValid: Bool? { session?.runLoopSourceIsValid }

    func configure(
        route: HyperKeyRoute?,
        includesShift: Bool,
        quickPress: HyperKeyQuickPress,
        trackpadSliders: Bool
    ) {
        self.quickPress = quickPress
        if trackpadSliders != self.trackpadSliders {
            self.trackpadSliders = trackpadSliders
            self.route = route
            self.includesShift = includesShift
            if session != nil {
                tearDown()
                _ = install()
            }
            return
        }
        guard route != self.route || includesShift != self.includesShift else { return }
        self.route = route
        self.includesShift = includesShift
        guard session?.configure(route: route, includesShift: includesShift) == true else { return }
        Self.postModifierRelease()
    }

    func cancelHold() {
        guard session?.cancelHold() == true else { return }
        Self.postModifierRelease()
    }

    // MARK: - Tap lifecycle

    /// Created here, so a refused grant fails synchronously; the session's thread then serves it.
    @discardableResult
    func install() -> Bool {
        guard session == nil else { return true }
        let engine = HyperKeyEngine(route: route, includesShift: includesShift)
        session = Session(
            engine: engine,
            trackpadSliders: trackpadSliders,
            deliver: { [weak self] route, effect in
                self?.handle(effect, from: route)
            },
            deliverScroll: { [weak self] adjustment in
                self?.onScrollAdjustment?(adjustment)
            },
            deliverHoldEnded: { [weak self] in
                self?.onHoldEnded?()
            })
        return session != nil
    }

    func tearDown() {
        cancelHold()
        session?.stop()
        session = nil
    }

    // MARK: - Effects

    private func handle(_ effect: HyperKeyEngine.Effect, from route: HyperKeyRoute) {
        guard session != nil, route == self.route else { return }
        switch effect {
        case .unmappedCapsLock:
            onUnmappedCapsLock?()
        case .unusedPress(let duration):
            performQuickPress(heldFor: duration)
        }
    }

    private func performQuickPress(heldFor duration: TimeInterval) {
        // Secure Input hides the key that made this press a chord, so a short hold proves nothing.
        guard !IsSecureEventInputEnabled(),
            let effect = quickPress.effect(
                heldFor: duration, capsLockOn: capsLockState(),
                switchesInputSource: UserDefaults.standard.bool(forKey: "TISRomanSwitchState"))
        else { return }
        switch effect {
        case .escape:
            postKey(CGKeyCode(kVK_Escape))
        case .setCapsLock(let on):
            setCapsLockState(on)
        case .switchInputSource:
            InputSourceSwitcher.toggleCapsLockInputSource()
        }
    }

    // MARK: - Synthetics & caps state

    nonisolated static func postModifierRelease() {
        guard let event = CGEvent(source: nil) else { return }
        event.type = .flagsChanged
        event.flags = []
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Command))
        event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        event.post(tap: .cghidEventTap)
    }

    /// Synthesize a bare key press for Quick Press, tagged so the tap ignores it.
    private func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        for event in [down, up] {
            // The session source still carries our injected chord, and a modified Escape is eaten.
            event?.flags = []
            event?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Remapping takes Caps Lock's own function away, so a latched lock would stay stuck on.
    func unlatchCapsLock() {
        setCapsLockState(false)
    }

    /// The IOHIDSystem connection for the Caps Lock LED and lock state.
    private func hidConnection() -> io_connect_t {
        if hidConnect != IO_OBJECT_NULL { return hidConnect }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != IO_OBJECT_NULL else { return IO_OBJECT_NULL }
        var connect: io_connect_t = IO_OBJECT_NULL
        IOServiceOpen(service, machTaskSelf, UInt32(kIOHIDParamConnectType), &connect)
        IOObjectRelease(service)
        hidConnect = connect
        return connect
    }

    private func capsLockState() -> Bool {
        let connect = hidConnection()
        guard connect != IO_OBJECT_NULL else { return false }
        var on = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on)
        return on
    }

    private func setCapsLockState(_ on: Bool) {
        let connect = hidConnection()
        guard connect != IO_OBJECT_NULL else { return }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on)
    }

    // MARK: - Session

    /// One installed tap and the thread that serves it, so a busy main thread never stalls typing.
    fileprivate final class Session: Sendable {
        private static let directionInvertedField = CGEventField(rawValue: 137)

        // Core Foundation allows cross-thread port and run-loop calls; only the worker runs the loop.
        private struct Installation: @unchecked Sendable {
            let port: CFMachPort
            var source: CFRunLoopSource?
            var runLoop: CFRunLoop?
        }

        private struct WeakTarget {
            weak var session: Session?
        }

        private struct State {
            var engine: HyperKeyEngine
            var scrollEngine = HyperScrollEngine()
            var pendingScrolls: [HyperScrollEngine.Adjustment] = []
            var isDrainingScrolls = false
            var installation: Installation?
            var isRunning = true
        }

        private let state: Mutex<State>
        private let touchMonitor: TrackpadTouchMonitor?
        private let deliver: @MainActor @Sendable (HyperKeyRoute, HyperKeyEngine.Effect) -> Void
        private let deliverScroll: @MainActor @Sendable (HyperScrollEngine.Adjustment) -> Void
        private let deliverHoldEnded: @MainActor @Sendable () -> Void

        init?(
            engine: HyperKeyEngine,
            trackpadSliders: Bool,
            deliver: @escaping @MainActor @Sendable (HyperKeyRoute, HyperKeyEngine.Effect) -> Void,
            deliverScroll: @escaping @MainActor @Sendable (HyperScrollEngine.Adjustment) -> Void,
            deliverHoldEnded: @escaping @MainActor @Sendable () -> Void
        ) {
            state = Mutex(State(engine: engine))
            self.deliver = deliver
            self.deliverScroll = deliverScroll
            self.deliverHoldEnded = deliverHoldEnded

            let target = Mutex(WeakTarget())
            touchMonitor =
                trackpadSliders
                ? TrackpadTouchMonitor { xs in
                    target.withLock { $0.session }?.updateTouches(xs)
                } : nil

            var events: CGEventMask =
                (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
            if trackpadSliders {
                events |= (1 << CGEventType.scrollWheel.rawValue)
            }
            guard
                let port = CGEvent.tapCreate(
                    tap: .cghidEventTap,
                    place: .headInsertEventTap,
                    options: .defaultTap,
                    eventsOfInterest: events,
                    callback: hyperKeyTapCallback,
                    userInfo: Unmanaged.passUnretained(self).toOpaque())
            else { return nil }
            target.withLock { $0.session = self }
            state.withLock { $0.installation = Installation(port: port) }
            let thread = Thread { [self] in run() }
            thread.name = "com.tinycast.hyper-key"
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        var isEnabled: Bool {
            state.withLock { $0.installation.map { CGEvent.tapIsEnabled(tap: $0.port) } } ?? false
        }

        var runLoopSourceIsValid: Bool {
            state.withLock { $0.installation?.source.map(CFRunLoopSourceIsValid) } ?? false
        }

        /// Swaps the route and drops any hold, which the old route's release would no longer end.
        func configure(route: HyperKeyRoute?, includesShift: Bool) -> Bool {
            let needsRelease = state.withLock { state in
                let needsRelease = state.engine.reset()
                state.scrollEngine.reset()
                state.engine.route = route
                state.engine.includesShift = includesShift
                return needsRelease
            }
            touchMonitor?.stop()
            return needsRelease
        }

        func cancelHold() -> Bool {
            let needsRelease = state.withLock { state in
                state.scrollEngine.reset()
                return state.engine.reset()
            }
            touchMonitor?.stop()
            return needsRelease
        }

        func stop() {
            touchMonitor?.stop()
            state.withLock { state in
                state.isRunning = false
                state.scrollEngine.reset()
                guard let runLoop = state.installation?.runLoop else { return }
                // A queued stop also covers closing before the worker enters its run loop.
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                    CFRunLoopStop(CFRunLoopGetCurrent())
                }
                CFRunLoopWakeUp(runLoop)
            }
        }

        private func updateTouches(_ normalizedXs: [Double]) {
            state.withLock { $0.scrollEngine.updateTouches(normalizedXs: normalizedXs) }
        }

        private func run() {
            autoreleasepool {
                guard let port = state.withLock({ $0.installation })?.port else { return }
                defer {
                    CGEvent.tapEnable(tap: port, enable: false)
                    CFMachPortInvalidate(port)
                }
                guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0),
                    let runLoop = CFRunLoopGetCurrent()
                else { return }
                CFRunLoopAddSource(runLoop, source, .defaultMode)
                defer { CFRunLoopRemoveSource(runLoop, source, .defaultMode) }
                let shouldRun = state.withLock { state in
                    guard state.isRunning else { return false }
                    state.installation = Installation(port: port, source: source, runLoop: runLoop)
                    return true
                }
                guard shouldRun else { return }
                CFRunLoopRun()
            }
        }

        func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
            let unchanged = Unmanaged.passUnretained(event)
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // Whatever was held went unseen while disabled, so the hold is stale.
                let needsRelease = state.withLock { state in
                    if let port = state.installation?.port { CGEvent.tapEnable(tap: port, enable: true) }
                    state.scrollEngine.reset()
                    return state.engine.reset()
                }
                touchMonitor?.stop()
                if needsRelease { HyperKeyTap.postModifierRelease() }
                return unchanged
            }
            guard event.getIntegerValueField(.eventSourceUserData) != HyperKeyTap.syntheticTag else {
                return unchanged
            }
            if type == .scrollWheel {
                return handleScroll(event)
            }
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags.rawValue
            let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let now = ProcessInfo.processInfo.systemUptime
            let (route, result, wasActive, nowActive) = state.withLock { state in
                let wasActive = state.engine.isActive
                let route = state.engine.route
                let insideSecureInput = keyCode == route?.tapKeyCode && IsSecureEventInputEnabled()
                let result = state.engine.handle(
                    type: type, keyCode: keyCode, flags: flags, isAutorepeat: isAutorepeat, at: now,
                    insideSecureInput: insideSecureInput)
                let nowActive = state.engine.isActive
                if wasActive, !nowActive { state.scrollEngine.endHyperHold() }
                return (route, result, wasActive, nowActive)
            }
            if nowActive != wasActive {
                if nowActive {
                    touchMonitor?.start()
                } else {
                    touchMonitor?.stop()
                    Task { @MainActor [deliverHoldEnded] in deliverHoldEnded() }
                }
            }
            if let route, let effect = result.effect {
                Task { @MainActor [deliver] in deliver(route, effect) }
            }
            switch result.decision {
            case .pass:
                return unchanged
            case .suppress:
                return nil
            case .rewrite(let flags, let keyCode, let asFlagsChanged):
                if asFlagsChanged { event.type = .flagsChanged }
                if let keyCode { event.setIntegerValueField(.keyboardEventKeycode, value: keyCode) }
                event.flags = CGEventFlags(rawValue: flags)
                return unchanged
            }
        }

        private func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
            let unchanged = Unmanaged.passUnretained(event)
            let isInterested = state.withLock {
                $0.engine.isActive || $0.scrollEngine.isSuppressingMomentum
            }
            guard isInterested else { return unchanged }

            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let scrollPhase = UInt32(
                bitPattern: Int32(truncatingIfNeeded: event.getIntegerValueField(.scrollWheelEventScrollPhase)))
            let momentumPhase = UInt32(
                bitPattern: Int32(
                    truncatingIfNeeded: event.getIntegerValueField(.scrollWheelEventMomentumPhase)))
            let pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let lineDeltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let isDirectionInverted =
                Self.directionInvertedField.map { event.getIntegerValueField($0) != 0 } ?? false

            let (result, shouldStartDrain) = state.withLock { state -> (HyperScrollEngine.Result, Bool) in
                let result = state.scrollEngine.handleScroll(
                    isHyperActive: state.engine.isActive,
                    isContinuous: isContinuous,
                    scrollPhase: scrollPhase,
                    momentumPhase: momentumPhase,
                    pointDeltaY: pointDeltaY,
                    lineDeltaY: lineDeltaY,
                    isDirectionInverted: isDirectionInverted)
                if result.marksHyperUsed { state.engine.markUsed() }
                var shouldStartDrain = false
                if result.gestureEnded {
                    state.pendingScrolls.removeAll(keepingCapacity: true)
                } else if let adjustment = result.adjustment {
                    if let last = state.pendingScrolls.last, last.zone == adjustment.zone {
                        state.pendingScrolls[state.pendingScrolls.count - 1].delta += adjustment.delta
                    } else {
                        state.pendingScrolls.append(adjustment)
                    }
                    if !state.isDrainingScrolls {
                        state.isDrainingScrolls = true
                        shouldStartDrain = true
                    }
                }
                return (result, shouldStartDrain)
            }

            if result.gestureEnded {
                Task { @MainActor [deliverHoldEnded] in deliverHoldEnded() }
            }
            if shouldStartDrain {
                Task { @MainActor [weak self] in self?.drainPendingScrolls() }
            }
            return result.decision == .suppress ? nil : unchanged
        }

        @MainActor
        private func drainPendingScrolls() {
            while true {
                let batch: [HyperScrollEngine.Adjustment] = state.withLock { state in
                    if state.pendingScrolls.isEmpty {
                        state.isDrainingScrolls = false
                        return []
                    }
                    let drained = state.pendingScrolls
                    state.pendingScrolls.removeAll(keepingCapacity: true)
                    return drained
                }
                guard !batch.isEmpty else { return }
                for adjustment in batch { deliverScroll(adjustment) }
            }
        }
    }
}
