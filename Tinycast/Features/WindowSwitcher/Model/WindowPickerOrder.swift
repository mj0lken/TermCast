import Foundation

/// The picker's order: on-screen windows front to back, then the rest, minimized ones last.
enum WindowPickerOrder {
    /// `windowRanks` is keyed by handle; a window off this Space or minimized has none.
    static func sorted(
        _ entries: [WindowSwitchEntry], windowRanks: [Int: Int]
    ) -> [WindowSwitchEntry] {
        let fallback = WindowSwitchOrder.sorted(entries)
        let position = Dictionary(
            uniqueKeysWithValues: fallback.enumerated().map { ($1.handle, $0) })
        return fallback.sorted { left, right in
            switch (windowRanks[left.handle], windowRanks[right.handle]) {
            case (let leftRank?, let rightRank?) where leftRank != rightRank:
                return leftRank < rightRank
            case (.some, nil): return true
            case (nil, .some): return false
            default: return (position[left.handle] ?? 0) < (position[right.handle] ?? 0)
            }
        }
    }
}
