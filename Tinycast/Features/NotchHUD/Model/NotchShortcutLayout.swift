import Foundation

/// Where every header shortcut sits: fixed places in the row and against each side of the cutout.
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

        /// The row hugs the header's edge and the left side hugs the cutout, so both end-align.
        var isTrailingAligned: Bool { self != .afterNotch }
    }

    /// One place of a zone, counted from the zone's leading end.
    struct Slot: Hashable, Sendable {
        let zone: Zone
        let index: Int
    }

    private var places: [Zone: [NotchShortcut?]]

    /// Stored lists are untrusted: a repeat keeps its first place, and a list without gaps is packed
    /// against the side its zone aligns to.
    init(beforeNotch: [NotchShortcut] = [], afterNotch: [NotchShortcut] = [], row: [NotchShortcut]) {
        var seen: Set<NotchShortcut> = []
        func claim(_ stored: [NotchShortcut], _ zone: Zone) -> [NotchShortcut?] {
            let unique = stored.map { $0 != .gap && seen.insert($0).inserted ? $0 : nil }
            let positioned = stored.contains(.gap) ? unique : unique.filter { $0 != nil }
            let kept = Array(positioned.prefix(zone.capacity))
            let padding = [NotchShortcut?](repeating: nil, count: zone.capacity - kept.count)
            return zone.isTrailingAligned ? padding + kept : kept + padding
        }
        let rowPlaces = claim(row, .row)
        let beforePlaces = claim(beforeNotch, .beforeNotch)
        places = [.row: rowPlaces, .beforeNotch: beforePlaces, .afterNotch: claim(afterNotch, .afterNotch)]
    }

    subscript(zone: Zone) -> [NotchShortcut?] { places[zone] ?? [] }

    subscript(slot: Slot) -> NotchShortcut? {
        let zonePlaces = self[slot.zone]
        return zonePlaces.indices.contains(slot.index) ? zonePlaces[slot.index] : nil
    }

    func slot(of shortcut: NotchShortcut) -> Slot? {
        for zone in Zone.allCases {
            if let index = self[zone].firstIndex(of: shortcut) { return Slot(zone: zone, index: index) }
        }
        return nil
    }

    var unused: [NotchShortcut] {
        NotchShortcut.choices.filter { slot(of: $0) == nil }
    }

    /// A zone's places without the empty ones at its far end, which is how it is stored and drawn.
    func trimmed(_ zone: Zone) -> [NotchShortcut?] {
        let all = self[zone]
        guard zone.isTrailingAligned else { return Array(all.prefix(extent(of: zone))) }
        return Array(all.suffix(extent(of: zone)))
    }

    func stored(_ zone: Zone) -> [NotchShortcut] {
        trimmed(zone).map { $0 ?? .gap }
    }

    /// The places of `zone` the header has room to draw; the cutout's right side takes its room first.
    func drawable(_ zone: Zone, showsBattery: Bool) -> Range<Int> {
        let room = NotchShortcut.slots(showsBattery: showsBattery)
        switch zone {
        case .beforeNotch:
            return 0..<zone.capacity
        case .afterNotch:
            return 0..<min(zone.capacity, room, max(room - extent(of: .row), extent(of: .afterNotch)))
        case .row:
            let count = min(NotchShortcut.limit(showsBattery: showsBattery), room - extent(of: .afterNotch))
            return (zone.capacity - max(count, 0))..<zone.capacity
        }
    }

    /// The layout as the header draws it: without the row's places it has no room for.
    func fitting(showsBattery: Bool) -> NotchShortcutLayout {
        let drawn = drawable(.row, showsBattery: showsBattery)
        return setting(.row, to: self[.row].enumerated().map { drawn.contains($0.offset) ? $0.element : nil })
    }

    func keeping(where isKept: (NotchShortcut) -> Bool) -> NotchShortcutLayout {
        Zone.allCases.reduce(self) { layout, zone in
            layout.setting(zone, to: self[zone].map { $0.flatMap { isKept($0) ? $0 : nil } })
        }
    }

    func removing(_ shortcut: NotchShortcut) -> NotchShortcutLayout {
        keeping { $0 != shortcut }
    }

    /// `shortcut` in `slot`; one already there takes the place `shortcut` left, or leaves the header.
    /// Nil when the header has no room for the result.
    func placing(_ shortcut: NotchShortcut, in slot: Slot, showsBattery: Bool) -> NotchShortcutLayout? {
        guard shortcut != .gap, self[slot.zone].indices.contains(slot.index), self[slot] != shortcut else {
            return nil
        }
        let displaced = self[slot]
        let vacated = self.slot(of: shortcut).map { removing(shortcut).setting($0, to: displaced) } ?? self
        let next = vacated.setting(slot, to: shortcut)
        return next.fits(showsBattery: showsBattery) ? next : nil
    }

    private func fits(showsBattery: Bool) -> Bool {
        extent(of: .row) <= NotchShortcut.limit(showsBattery: showsBattery)
            && extent(of: .row) + extent(of: .afterNotch) <= NotchShortcut.slots(showsBattery: showsBattery)
    }

    /// How many places `zone` spans from the side it aligns to, gaps between shortcuts included.
    private func extent(of zone: Zone) -> Int {
        let all = self[zone]
        guard zone.isTrailingAligned else { return all.lastIndex { $0 != nil }.map { $0 + 1 } ?? 0 }
        return all.firstIndex { $0 != nil }.map { all.count - $0 } ?? 0
    }

    private func setting(_ slot: Slot, to shortcut: NotchShortcut?) -> NotchShortcutLayout {
        setting(slot.zone, to: self[slot.zone].enumerated().map { $0.offset == slot.index ? shortcut : $0.element })
    }

    private func setting(_ zone: Zone, to zonePlaces: [NotchShortcut?]) -> NotchShortcutLayout {
        var next = self
        next.places[zone] = zonePlaces
        return next
    }
}
