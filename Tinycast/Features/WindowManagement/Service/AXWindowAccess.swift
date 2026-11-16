// Portions adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
// `@preconcurrency` downgrades AX diagnostics: `kAX…` are mutable C globals, but constant.
@preconcurrency import ApplicationServices

/// Every `AXUIElement` call in the feature, so no two callers disagree on what a window is.
@MainActor
enum AXWindowAccess {
    /// A hung target must not stall main for the AX default. Per element, never inherited.
    static let messagingTimeout: Float = 1
    /// Slack when checking whether the app honoured the size we asked for.
    static let clampTolerance: CGFloat = 2

    static let fullScreenAttribute = "AXFullScreen" as CFString
    static let fullScreenButtonAttribute = "AXFullScreenButton" as CFString

    // MARK: - Finding windows

    static func application(for pid: pid_t, timeout: Float = messagingTimeout) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        return application
    }

    static func targetWindow(in application: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = element(application, attribute), isEligible(window) { return window }
        }
        return windows(in: application).first(where: isEligible)
    }

    /// Resolves the topmost movable window under `point` in AX space via z-order, then AX hit-test.
    static func windowAtPosition(_ point: CGPoint, timeout: Float = 0.15) -> (
        pid: pid_t, application: AXUIElement, window: AXUIElement, windowID: UInt32?
    )? {
        if let zOrdered = topmostWindow(at: point, timeout: timeout) {
            return zOrdered
        }
        return hitTestedWindow(at: point, timeout: timeout)
    }

    /// Reads the live on-screen bounds of `windowID` directly from the WindowServer without AX IPC.
    static func windowServerFrame(for windowID: UInt32) -> CGRect? {
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard
            let listing = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]],
            let entry = listing.first,
            let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            bounds.width > 0, bounds.height > 0
        else { return nil }
        return bounds
    }

    private static func topmostWindow(at point: CGPoint, timeout: Float) -> (
        pid: pid_t, application: AXUIElement, window: AXUIElement, windowID: UInt32?
    )? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        for entry in listing {
            guard entry[kCGWindowLayer as String] as? Int == 0,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                pid > 0,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict),
                bounds.width > 1, bounds.height > 1, bounds.contains(point)
            else { continue }
            guard pid != ownPID else { return nil }

            let targetID = entry[kCGWindowNumber as String] as? UInt32
            let application = Self.application(for: pid, timeout: timeout)
            var candidates = windows(in: application)
            if candidates.isEmpty {
                setManualAccessibility(true, application: application)
                defer { setManualAccessibility(false, application: application) }
                candidates = windows(in: application)
            }
            if let targetID {
                for window in candidates {
                    AXUIElementSetMessagingTimeout(window, timeout)
                    if windowID(of: window) == targetID, isEligible(window) {
                        return (pid, application, window, targetID)
                    }
                }
            }
            for window in candidates {
                AXUIElementSetMessagingTimeout(window, timeout)
                guard isEligible(window), let frame = Self.frame(of: window) else { continue }
                if abs(frame.minX - bounds.minX) <= 4 && abs(frame.minY - bounds.minY) <= 4
                    && abs(frame.width - bounds.width) <= 4
                    && abs(frame.height - bounds.height) <= 4
                {
                    return (pid, application, window, targetID ?? windowID(of: window))
                }
            }
            if let focused = targetWindow(in: application) {
                AXUIElementSetMessagingTimeout(focused, timeout)
                if let frame = Self.frame(of: focused), frame.contains(point) {
                    return (pid, application, focused, targetID ?? windowID(of: focused))
                }
            }
            return nil
        }
        return nil
    }

    private static func hitTestedWindow(at point: CGPoint, timeout: Float) -> (
        pid: pid_t, application: AXUIElement, window: AXUIElement, windowID: UInt32?
    )? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        var element: AXUIElement?
        guard
            AXUIElementCopyElementAtPosition(
                system, Float(point.x), Float(point.y), &element) == .success,
            let hit = element
        else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid > 0,
            pid != ProcessInfo.processInfo.processIdentifier
        else { return nil }

        let application = Self.application(for: pid, timeout: timeout)
        var current: AXUIElement? = hit
        for _ in 0..<12 {
            guard let candidate = current else { break }
            AXUIElementSetMessagingTimeout(candidate, timeout)
            if string(candidate, kAXRoleAttribute) == (kAXWindowRole as String),
                isEligible(candidate)
            {
                return (pid, application, candidate, windowID(of: candidate))
            }
            if let directWindow = Self.element(candidate, kAXWindowAttribute) {
                AXUIElementSetMessagingTimeout(directWindow, timeout)
                if isEligible(directWindow) {
                    return (pid, application, directWindow, windowID(of: directWindow))
                }
            }
            current = Self.element(candidate, kAXParentAttribute)
        }
        return nil
    }

    /// Every window the app reports, unfiltered and in its own order.
    static func windows(in application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
                == .success,
            let windows = value as? [AXUIElement]
        else { return [] }
        return windows
    }

    /// A real, restorable window: not a sheet, popover or minimized one, and it reports geometry.
    static func isEligible(_ window: AXUIElement) -> Bool {
        guard string(window, kAXRoleAttribute) == (kAXWindowRole as String) else { return false }
        if bool(window, kAXMinimizedAttribute) == true { return false }
        return frame(of: window) != nil
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool { fullScreenState(window) == true }

    /// AX-space bounds of the window's chosen traffic-light button, if present.
    static func trafficLightButtonFrame(
        of window: AXUIElement, kind: WindowTrafficLightButton, timeout: Float = 0.15
    ) -> CGRect? {
        let attributes: [String] =
            switch kind {
            case .green: [fullScreenButtonAttribute as String, kAXZoomButtonAttribute]
            case .yellow: [kAXMinimizeButtonAttribute]
            }
        for attribute in attributes {
            guard let button = element(window, attribute) else { continue }
            AXUIElementSetMessagingTimeout(button, timeout)
            if let rect = frame(of: button), rect.width > 0, rect.height > 0 {
                return rect
            }
        }
        return nil
    }

    /// Nil when the window does not answer, as a busy app mid-transition often does not.
    static func fullScreenState(_ window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, fullScreenAttribute, &value) == .success
        else { return nil }
        return (value as? Bool) ?? false
    }

    // MARK: - Bringing one forward

    static func unminimize(_ window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            == .success
    }

    static func minimize(_ window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            == .success
    }

    static func focus(
        _ window: AXUIElement, in application: AXUIElement, of app: NSRunningApplication
    ) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // Belt and braces with `activate()`: an agent-policy app's request can be ignored.
        AXUIElementSetAttributeValue(
            application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    /// Orders a window forward across apps: a raise alone reorders it only inside its own app.
    static func raise(_ window: AXUIElement, in application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// The fallback for an app that refuses `NSRunningApplication.hide()` or `unhide()`.
    static func setHidden(_ hidden: Bool, application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, kAXHiddenAttribute as CFString, hidden ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// Web-based apps list no windows until this is on, and draw focus rings while it stays on.
    static func setManualAccessibility(_ enabled: Bool, application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, "AXManualAccessibility" as CFString,
            enabled ? kCFBooleanTrue : kCFBooleanFalse)
    }

    // MARK: - Window identity

    /// The window server's number, which outlives any `AXUIElement`. See window-rooms.md.
    static func windowID(of window: AXUIElement) -> UInt32? {
        guard let copyWindowID else { return nil }
        var id: CGWindowID = 0
        return copyWindowID(window, &id) == .success && id != 0 ? id : nil
    }

    private typealias CopyWindowID =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// Private, so resolved at run time: a macOS without it degrades to titles, never a crash.
    private static let copyWindowID: CopyWindowID? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: CopyWindowID.self)
    }()

    // MARK: - Writing a frame

    /// The one write sequence, so a stubborn app lands the same way from any caller.
    static func write(
        _ target: CGRect, anchor: WindowPlacementEngine.Anchor, to window: AXUIElement,
        current: CGRect, canResize: Bool, canvas: CGRect?
    ) -> CGRect? {
        guard canResize else {
            var slot = anchor.place(current.size, in: target)
            if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
            guard setPosition(WindowPlacementEngine.rounded(slot).origin, on: window) else {
                return nil
            }
            return frame(of: window) ?? current
        }

        // size → position → size. See docs/features/window-management.md#applying-a-placement.
        _ = setSize(target.size, on: window)
        guard setPosition(target.origin, on: window) else {
            _ = setSize(current.size, on: window)  // Roll the shrink back; nothing visibly moved.
            return nil
        }
        _ = setSize(target.size, on: window)

        guard var actual = frame(of: window) else { return target }

        // The second resize can shift the origin: some apps anchor on a different corner.
        if abs(actual.minX - target.minX) > clampTolerance
            || abs(actual.minY - target.minY) > clampTolerance
        {
            _ = setPosition(target.origin, on: window)
            actual = frame(of: window) ?? actual
        }

        // An app-imposed minimum: re-place once per the anchor. No loop, which would jitter.
        if actual.width > target.width + clampTolerance
            || actual.height > target.height + clampTolerance
        {
            var slot = anchor.place(actual.size, in: target)
            if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
            _ = setPosition(WindowPlacementEngine.rounded(slot).origin, on: window)
            actual = frame(of: window) ?? actual
        }
        return actual
    }

    /// Cleared for the writes, never while VoiceOver runs. See docs/features/window-management.md.
    static func suppressEnhancedUserInterface(on application: AXUIElement) -> () -> Void {
        let attribute = "AXEnhancedUserInterface" as CFString
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return {} }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute, &value) == .success,
            (value as? Bool) == true
        else { return {} }
        AXUIElementSetAttributeValue(application, attribute, kCFBooleanFalse)
        return { AXUIElementSetAttributeValue(application, attribute, kCFBooleanTrue) }
    }

    // MARK: - Primitives

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute),
            let size = size(window, kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setPosition(_ origin: CGPoint, on window: AXUIElement) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            == .success
    }

    static func setSize(_ size: CGSize, on window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute, type: .cgPoint) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute, type: .cgSize) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    static func axValue(
        _ element: AXUIElement, _ attribute: String, type: AXValueType
    ) -> AXValue? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        // Type checked by CFGetTypeID above; `as?` on a CF type is a compile error.

        let axValue = value as! AXValue
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Type checked by CFGetTypeID above; `as?` on a CF type is a compile error.

        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    static func isSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }
}
