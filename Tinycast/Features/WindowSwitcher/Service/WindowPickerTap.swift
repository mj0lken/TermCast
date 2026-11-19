import CoreGraphics
import Foundation
import Synchronization

private func windowPickerTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<WindowPickerTap.Session>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
        .handle(type, event)
}

/// The switcher's keys, read on their own run loop: ⌘⇥ has to be swallowed before the Dock sees it.
@MainActor
final class WindowPickerTap {
    var onCommand: ((WindowPickerKeyEngine.Command) -> Void)?

    private var session: Session?

    isolated deinit {
        tearDown()
    }

    var isInstalled: Bool { session != nil }

    var isEnabled: Bool { session?.isEnabled ?? false }

    /// False without the Accessibility grant, which an active key tap needs.
    @discardableResult
    func install(engine: WindowPickerKeyEngine) -> Bool {
        if let session {
            session.configure(engine)
            return true
        }
        session = Session(engine: engine) { [weak self] command in
            self?.onCommand?(command)
        }
        return session != nil
    }

    func tearDown() {
        session?.stop()
        session = nil
    }

    /// Closes the engine from the main actor: a click, or an open that found no windows.
    func reset() {
        session?.reset()
    }

    fileprivate final class Session: Sendable {
        private static let leftShiftDeviceMask: UInt64 = 0x2
        private static let rightShiftDeviceMask: UInt64 = 0x4

        // Core Foundation allows cross-thread port/run-loop wakeups while only the worker runs the loop.
        private struct Installation: @unchecked Sendable {
            let port: CFMachPort
            var runLoop: CFRunLoop?
        }

        private struct State {
            var engine: WindowPickerKeyEngine
            var installation: Installation?
            var pending: [WindowPickerKeyEngine.Command] = []
            var isDraining = false
            var isRunning = true
        }

        private let state: Mutex<State>
        private let deliver: @MainActor @Sendable (WindowPickerKeyEngine.Command) -> Void

        init?(
            engine: WindowPickerKeyEngine,
            deliver: @escaping @MainActor @Sendable (WindowPickerKeyEngine.Command) -> Void
        ) {
            self.deliver = deliver
            state = Mutex(State(engine: engine))
            let mask =
                CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            guard
                let port = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .defaultTap,
                    eventsOfInterest: mask,
                    callback: windowPickerTapCallback,
                    userInfo: Unmanaged.passUnretained(self).toOpaque())
            else { return nil }

            state.withLock { $0.installation = Installation(port: port) }
            let thread = Thread { [self] in run() }
            thread.name = "com.tinycast.window-picker-tap"
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        var isEnabled: Bool {
            state.withLock { $0.installation.map { CGEvent.tapIsEnabled(tap: $0.port) } } ?? false
        }

        /// Only the configuration moves over, so a change mid-show cannot strand the picker open.
        func configure(_ engine: WindowPickerKeyEngine) {
            state.withLock { state in
                state.engine.triggers = engine.triggers
                state.engine.actionKeys = engine.actionKeys
                state.engine.characters = engine.characters
            }
        }

        func reset() {
            state.withLock { $0.engine.reset() }
        }

        func stop() {
            state.withLock { state in
                state.isRunning = false
                state.pending.removeAll()
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
                    state.installation = Installation(port: port, runLoop: runLoop)
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
            guard type == .keyDown || type == .flagsChanged else { return unchanged }

            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let modifiers = Self.modifiers(from: flags)
            let (swallows, shouldStartDrain) = state.withLock { state -> (Bool, Bool) in
                guard state.isRunning else { return (false, false) }
                var outcome = WindowPickerKeyEngine.Outcome.passed
                if type == .keyDown {
                    outcome = state.engine.keyDown(keyCode, modifiers: modifiers)
                } else {
                    outcome.command = state.engine.modifiersChanged(
                        keyCode: keyCode, isDown: Self.isDown(keyCode, in: flags),
                        modifiers: modifiers)
                }
                guard let command = outcome.command else { return (outcome.swallows, false) }
                state.pending.append(command)
                guard !state.isDraining else { return (outcome.swallows, false) }
                state.isDraining = true
                return (outcome.swallows, true)
            }
            if shouldStartDrain {
                Task { @MainActor [weak self] in self?.drain() }
            }
            return swallows ? nil : unchanged
        }

        /// One drain at a time, so commands reach the main actor in the order they were typed.
        @MainActor
        private func drain() {
            while true {
                let batch: [WindowPickerKeyEngine.Command] = state.withLock { state in
                    if state.pending.isEmpty {
                        state.isDraining = false
                        return []
                    }
                    let drained = state.pending
                    state.pending.removeAll(keepingCapacity: true)
                    return drained
                }
                guard !batch.isEmpty else { return }
                for command in batch { deliver(command) }
            }
        }

        private static func modifiers(from flags: CGEventFlags) -> WindowPickerKeyEngine.Modifiers {
            var modifiers: WindowPickerKeyEngine.Modifiers = []
            if flags.contains(.maskCommand) { modifiers.insert(.command) }
            if flags.contains(.maskAlternate) { modifiers.insert(.option) }
            if flags.contains(.maskControl) { modifiers.insert(.control) }
            if flags.contains(.maskShift) { modifiers.insert(.shift) }
            return modifiers
        }

        /// The device bits tell the two Shift keys apart; the shared flag cannot.
        private static func isDown(_ keyCode: UInt16, in flags: CGEventFlags) -> Bool {
            switch keyCode {
            case WindowPickerKeyEngine.KeyCode.leftShift:
                flags.rawValue & leftShiftDeviceMask != 0
            case WindowPickerKeyEngine.KeyCode.rightShift:
                flags.rawValue & rightShiftDeviceMask != 0
            default: false
            }
        }
    }
}
