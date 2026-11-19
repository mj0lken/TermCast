import AppKit
@preconcurrency import ApplicationServices

/// Reads every switchable window over AX, once. Shallow enough to stay synchronous: unlike the
/// menu walk it visits apps and their windows, never a tree.
@MainActor
enum WindowSwitchSweep {
    /// A sweep walks every app, so one hung process must not cost the full messaging timeout.
    private static let sweepTimeout: Float = 0.2
    /// Finding another Space's windows walks element IDs, so it is capped per app and per sweep.
    private static let remoteAppBudget: Duration = .milliseconds(120)
    private static let remoteSweepBudget: Duration = .milliseconds(400)

    /// Live AX handles for one window. Never `Sendable`: these do not leave the main actor.
    struct Element {
        let app: NSRunningApplication
        let application: AXUIElement
        let window: AXUIElement
    }

    struct Snapshot {
        var entries: [WindowSwitchEntry]
        var elements: [Int: Element]
    }

    /// `phantoms` are off-screen window numbers already proven unswitchable, so no sweep pays twice.
    static func snapshot(ranks: [pid_t: Int], phantoms: inout Set<UInt32>) -> Snapshot {
        var entries: [WindowSwitchEntry] = []
        var elements: [Int: Element] = [:]
        let offScreen = AXWindowAccess.offScreenWindowIDs()
        phantoms.formIntersection(offScreen.values.reduce(into: Set()) { $0.formUnion($1) })
        let sweepDeadline = ContinuousClock.now + remoteSweepBudget

        for app in WindowInventory.candidates() {
            guard let bundleID = app.bundleIdentifier else { continue }
            let pid = app.processIdentifier
            let application = AXWindowAccess.application(for: pid, timeout: sweepTimeout)
            let iconURL = app.bundleURL
            let iconStamp = iconURL.map(FileIconStamp.value(for:)) ?? 0
            let listed = AXWindowAccess.windows(in: application)
            for window in listed { AXUIElementSetMessagingTimeout(window, sweepTimeout) }
            let wanted = (offScreen[pid] ?? [])
                .subtracting(listed.compactMap(AXWindowAccess.windowID(of:))).subtracting(phantoms)
            let remote = AXWindowAccess.remoteWindows(
                in: pid, numbered: wanted, timeout: sweepTimeout,
                deadline: min(sweepDeadline, ContinuousClock.now + remoteAppBudget))
            var unswitchable = wanted
            for window in listed + remote.windows {
                let minimized = AXWindowAccess.bool(window, kAXMinimizedAttribute) == true
                guard isSwitchable(window, minimized: minimized) else { continue }
                if let id = AXWindowAccess.windowID(of: window) { unswitchable.remove(id) }
                let handle = entries.count
                entries.append(
                    WindowSwitchEntry(
                        handle: handle, appName: app.localizedName ?? bundleID,
                        bundleID: bundleID, iconURL: iconURL, iconStamp: iconStamp,
                        title: AXWindowAccess.string(window, kAXTitleAttribute) ?? "",
                        isMinimized: minimized,
                        isFullScreen: AXWindowAccess.isFullScreen(window),
                        appRank: ranks[pid] ?? .max))
                elements[handle] = Element(app: app, application: application, window: window)
            }
            if remote.isComplete { phantoms.formUnion(unswitchable) }
        }
        return Snapshot(entries: entries, elements: elements)
    }

    /// Looser than the layout inventory's rule: a minimized window is exactly what a switcher is
    /// for, and a window on another Space reports no frame until it is raised.
    private static func isSwitchable(_ window: AXUIElement, minimized: Bool) -> Bool {
        WindowSwitchPolicy.isSwitchable(
            isStandardWindow: AXWindowAccess.string(window, kAXSubroleAttribute)
                == (kAXStandardWindowSubrole as String),
            isMinimized: minimized,
            canMinimize: AXWindowAccess.element(window, kAXMinimizeButtonAttribute) != nil)
    }
}
