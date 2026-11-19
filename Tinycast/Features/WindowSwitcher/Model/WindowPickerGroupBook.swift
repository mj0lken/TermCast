import Foundation

/// Everything remembered about groups: which app was moved where, their order, names and shades.
struct WindowPickerGroupBook: Codable, Equatable, Sendable {
    typealias Group = WindowPickerBoard.Group

    struct Style: Codable, Equatable, Sendable {
        /// Empty keeps the group's own name: its kind of app, or "Group N".
        var name = ""
        var tint = WindowPickerGroupTint.automatic
    }

    struct Entry: Codable, Equatable, Sendable, Identifiable {
        let group: Group
        var style = Style()

        var id: Group { group }
    }

    /// Bundle ID to the group its app was dragged into.
    var apps: [String: Group] = [:]
    /// Every group seen so far, in the order the picker lays them out.
    private(set) var entries: [Entry] = []

    var order: [Group] { entries.map(\.group) }

    func style(for group: Group) -> Style {
        entries.first { $0.group == group }?.style ?? Style()
    }

    /// Automatic resolves by position, so a group keeps its shade until the order changes.
    func tint(for group: Group) -> WindowPickerGroupTint {
        let index = entries.firstIndex { $0.group == group }
        let chosen = index.map { entries[$0].style.tint } ?? .automatic
        guard chosen == .automatic else { return chosen }
        let palette = WindowPickerGroupTint.palette
        return palette[(index ?? 0) % palette.count]
    }

    mutating func setStyle(_ style: Style, for group: Group) {
        guard let index = entries.firstIndex(where: { $0.group == group }) else { return }
        entries[index].style = style
    }

    /// Takes a complete order, keeping each group's style and dropping none it does not name.
    mutating func setOrder(_ order: [Group]) {
        let known = Dictionary(entries.map { ($0.group, $0) }, uniquingKeysWith: { first, _ in first })
        let named = Set(order)
        entries =
            order.map { known[$0] ?? Entry(group: $0) } + entries.filter { !named.contains($0.group) }
    }

    /// The groups on screen take a new order among themselves; the rest keep their slots.
    static func reordered(_ order: [Group], visible: [Group]) -> [Group] {
        let shown = Set(visible)
        var next = visible.makeIterator()
        return order.map { shown.contains($0) ? next.next() ?? $0 : $0 }
    }
}
