import CoreGraphics

/// How recently each app was in front, read off the window server's own front-to-back list.
@MainActor
enum WindowZOrder {
    /// Layer 0 is the normal window band; anything above it is a menu bar, Dock or overlay panel.
    private static let normalLayer = 0

    struct Ranks {
        var apps: [pid_t: Int] = [:]
        var windows: [CGWindowID: Int] = [:]
    }

    static func appRanks() -> [pid_t: Int] { ranks().apps }

    /// An app's rank is where its frontmost window sits; `kCGWindowName` is never read, so the
    /// list needs no Screen Recording grant.
    static func ranks() -> Ranks {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return Ranks() }
        var ranks = Ranks()
        for window in listing {
            guard window[kCGWindowLayer as String] as? Int == normalLayer,
                let pid = window[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            if ranks.apps[pid] == nil { ranks.apps[pid] = ranks.apps.count }
            if let id = window[kCGWindowNumber as String] as? CGWindowID {
                ranks.windows[id] = ranks.windows.count
            }
        }
        return ranks
    }
}
