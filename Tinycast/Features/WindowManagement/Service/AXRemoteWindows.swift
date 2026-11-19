import AppKit
@preconcurrency import ApplicationServices

/// Windows `kAXWindows` leaves out: it lists the current Space only, so a full-screen window is
/// invisible from anywhere else. The window server still knows them, and AX can still address them.
extension AXWindowAccess {
    /// Smaller than any window worth switching to; drops the helper windows apps keep off screen.
    private static let minimumRemoteSide: CGFloat = 100
    /// Element IDs are handed out from zero per process; real windows sit low in the range.
    private static let remoteElementIDs: Range<UInt64> = 0..<1000
    private static let remoteTokenMagic: Int32 = 0x636f_636f

    /// Window numbers the server holds off screen, per owning process.
    static func offScreenWindowIDs() -> [pid_t: Set<UInt32>] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var ids: [pid_t: Set<UInt32>] = [:]
        for info in listing {
            guard
                info[kCGWindowLayer as String] as? Int == 0,
                info[kCGWindowIsOnscreen as String] as? Bool != true,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let id = info[kCGWindowNumber as String] as? UInt32,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                bounds["Width"] ?? 0 >= minimumRemoteSide, bounds["Height"] ?? 0 >= minimumRemoteSide
            else { continue }
            ids[pid, default: []].insert(id)
        }
        return ids
    }

    /// The AX elements behind `ids`. `isComplete` is false when the deadline cut the walk short.
    static func remoteWindows(
        in pid: pid_t, numbered ids: Set<UInt32>, timeout: Float, deadline: ContinuousClock.Instant
    ) -> (windows: [AXUIElement], isComplete: Bool) {
        guard let createWithRemoteToken, !ids.isEmpty else { return ([], true) }
        var remaining = ids
        var windows: [AXUIElement] = []
        for elementID in remoteElementIDs {
            guard ContinuousClock.now < deadline else { return (windows, false) }
            var token = Data()
            withUnsafeBytes(of: pid) { token.append(contentsOf: $0) }
            withUnsafeBytes(of: Int32(0)) { token.append(contentsOf: $0) }
            withUnsafeBytes(of: remoteTokenMagic) { token.append(contentsOf: $0) }
            withUnsafeBytes(of: elementID) { token.append(contentsOf: $0) }
            guard let element = createWithRemoteToken(token as CFData)?.takeRetainedValue() else {
                continue
            }
            AXUIElementSetMessagingTimeout(element, timeout)
            guard let id = windowID(of: element), remaining.remove(id) != nil else { continue }
            windows.append(element)
            if remaining.isEmpty { break }
        }
        return (windows, true)
    }

    private typealias CreateWithRemoteToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    /// Private, so resolved at run time: a macOS without it lists the current Space only.
    private static let createWithRemoteToken: CreateWithRemoteToken? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementCreateWithRemoteToken") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CreateWithRemoteToken.self)
    }()
}
