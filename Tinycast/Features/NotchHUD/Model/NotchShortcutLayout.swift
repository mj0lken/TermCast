import Foundation

/// Where every header shortcut sits: the row at the trailing edge, and the places beside the cutout.
struct NotchShortcutLayout: Equatable, Sendable {
    enum Zone: CaseIterable, Sendable {
        case beforeNotch
        case afterNotch
        case row

        var capacity: Int {
            switch self {
            case .beforeNotch, .afterNotch: 2
            case .row: NotchShortcut.limit(showsBattery: false)
            }
        }
    }

    private(set) var beforeNotch: [NotchShortcut]
    private(set) var afterNotch: [NotchShortcut]
    private(set) var row: [NotchShortcut]

    /// Stored lists are untrusted: a repeat keeps its first place, and a zone is cut to what it holds.
    init(beforeNotch: [NotchShortcut] = [], afterNotch: [NotchShortcut] = [], row: [NotchShortcut]) {
        var seen: Set<NotchShortcut> = []
        func claim(_ shortcuts: [NotchShortcut], _ zone: Zone) -> [NotchShortcut] {
            Array(shortcuts.filter { seen.insert($0).inserted }.prefix(zone.capacity))
        }
        self.row = claim(row, .row)
        self.beforeNotch = claim(beforeNotch, .beforeNotch)
        self.afterNotch = claim(afterNotch, .afterNotch)
    }

    subscript(zone: Zone) -> [NotchShortcut] {
        switch zone {
        case .beforeNotch: beforeNotch
        case .afterNotch: afterNotch
        case .row: row
        }
    }

    var unused: [NotchShortcut] {
        NotchShortcut.allCases.filter { zone(of: $0) == nil }
    }

    func zone(of shortcut: NotchShortcut) -> Zone? {
        Zone.allCases.first { self[$0].contains(shortcut) }
    }

    func hasRoom(for shortcut: NotchShortcut, in zone: Zone) -> Bool {
        self[zone].filter { $0 != shortcut }.count < zone.capacity
    }

    func removing(_ shortcut: NotchShortcut) -> NotchShortcutLayout {
        setting { $0.filter { $0 != shortcut } }
    }

    /// `shortcut` in `zone` before `anchor`, or last there; nil when the zone has no room for it.
    func placing(
        _ shortcut: NotchShortcut, in zone: Zone, before anchor: NotchShortcut? = nil
    ) -> NotchShortcutLayout? {
        guard hasRoom(for: shortcut, in: zone) else { return nil }
        let cleared = removing(shortcut)
        let list = cleared[zone]
        let index = anchor.flatMap { list.firstIndex(of: $0) } ?? list.endIndex
        return cleared.setting(zone, to: Array(list[..<index]) + [shortcut] + list[index...])
    }

    /// `shortcut` in `displaced`'s place, which leaves the header; nil when `displaced` is not in it.
    func replacing(_ displaced: NotchShortcut, with shortcut: NotchShortcut) -> NotchShortcutLayout? {
        guard shortcut != displaced, let zone = zone(of: displaced) else { return nil }
        let cleared = removing(shortcut)
        return cleared.setting(zone, to: cleared[zone].map { $0 == displaced ? shortcut : $0 })
    }

    private func setting(_ zone: Zone, to list: [NotchShortcut]) -> NotchShortcutLayout {
        NotchShortcutLayout(
            beforeNotch: zone == .beforeNotch ? list : beforeNotch,
            afterNotch: zone == .afterNotch ? list : afterNotch,
            row: zone == .row ? list : row)
    }

    private func setting(_ transform: ([NotchShortcut]) -> [NotchShortcut]) -> NotchShortcutLayout {
        NotchShortcutLayout(
            beforeNotch: transform(beforeNotch), afterNotch: transform(afterNotch), row: transform(row))
    }
}
