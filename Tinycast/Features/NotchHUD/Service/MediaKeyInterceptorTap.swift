import AppKit
import CoreGraphics
import Synchronization

private func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<MediaKeyInterceptorTap.Session>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
        .handle(type, event)
}

/// Intercepts physical `NX_SYSDEFINED` media keys on a dedicated run loop so `OSDUIHelper` stays idle.
@MainActor
final class MediaKeyInterceptorTap {
    var onMediaKeyDown: ((MediaKeyEvent) -> Void)?

    private var session: Session?

    isolated deinit {
        tearDown()
    }

    var isEnabled: Bool {
        session?.isEnabled ?? false
    }

    @discardableResult
    func install() -> Bool {
        guard session == nil else { return true }
        session = Session { [weak self] event in
            self?.onMediaKeyDown?(event)
        }
        return session != nil
    }

    func tearDown() {
        session?.stop()
        session = nil
    }

    fileprivate final class Session: Sendable {
        private static let sysDefinedEventTypeRaw: UInt32 = 14

        // Core Foundation allows cross-thread port/run-loop wakeups while only the worker runs the loop.
        private struct Installation: @unchecked Sendable {
            let port: CFMachPort
            var source: CFRunLoopSource?
            var runLoop: CFRunLoop?
        }

        private struct State {
            var installation: Installation?
            var pendingEvents: [MediaKeyEvent] = []
            var isDraining = false
            var isRunning = true
        }

        private let state = Mutex(State())
        private let deliver: @MainActor @Sendable (MediaKeyEvent) -> Void

        init?(deliver: @escaping @MainActor @Sendable (MediaKeyEvent) -> Void) {
            self.deliver = deliver
            let mask = CGEventMask(1 << Self.sysDefinedEventTypeRaw)
            guard
                let port = CGEvent.tapCreate(
                    tap: .cghidEventTap,
                    place: .headInsertEventTap,
                    options: .defaultTap,
                    eventsOfInterest: mask,
                    callback: mediaKeyTapCallback,
                    userInfo: Unmanaged.passUnretained(self).toOpaque())
            else { return nil }

            state.withLock { $0.installation = Installation(port: port) }
            let thread = Thread { [self] in run() }
            thread.name = "com.tinycast.notch-hud-tap"
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        var isEnabled: Bool {
            state.withLock { $0.installation.map { CGEvent.tapIsEnabled(tap: $0.port) } } ?? false
        }

        func stop() {
            state.withLock { state in
                state.isRunning = false
                state.pendingEvents.removeAll()
                guard let runLoop = state.installation?.runLoop else { return }
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                    CFRunLoopStop(CFRunLoopGetCurrent())
                }
                CFRunLoopWakeUp(runLoop)
            }
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
                state.withLock { state in
                    if let port = state.installation?.port {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                }
                return unchanged
            }

            guard type.rawValue == Self.sysDefinedEventTypeRaw,
                let nsEvent = NSEvent(cgEvent: event)
            else {
                return unchanged
            }

            let flags = event.flags
            guard
                let decoded = MediaKeyEvent.decode(
                    subtype: nsEvent.subtype.rawValue,
                    data1: nsEvent.data1,
                    shift: flags.contains(.maskShift),
                    option: flags.contains(.maskAlternate),
                    control: flags.contains(.maskControl),
                    command: flags.contains(.maskCommand))
            else {
                return unchanged
            }

            if decoded.phase == .down {
                let shouldStartDrain = state.withLock { state -> Bool in
                    guard state.isRunning else { return false }
                    state.pendingEvents.append(decoded)
                    guard !state.isDraining else { return false }
                    state.isDraining = true
                    return true
                }
                if shouldStartDrain {
                    Task { @MainActor [weak self] in self?.drainPendingEvents() }
                }
            }
            return nil
        }

        @MainActor
        private func drainPendingEvents() {
            while true {
                let batch: [MediaKeyEvent] = state.withLock { state in
                    if state.pendingEvents.isEmpty {
                        state.isDraining = false
                        return []
                    }
                    let drained = state.pendingEvents
                    state.pendingEvents.removeAll(keepingCapacity: true)
                    return drained
                }
                guard !batch.isEmpty else { return }
                for item in batch {
                    deliver(item)
                }
            }
        }
    }
}
