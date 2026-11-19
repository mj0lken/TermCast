import Foundation

/// What the picker shows and where its selection is: flat, stacked by app, inside one stack, or
/// laid out in outlined groups.
struct WindowPickerBoard: Equatable, Sendable {
    struct Stack: Identifiable, Hashable, Sendable {
        let bundleID: String
        let appName: String
        let iconURL: URL?
        let iconStamp: Int
        let windows: [WindowSwitchEntry]

        var id: String { "stack:" + bundleID }
    }

    enum Tile: Identifiable, Hashable, Sendable {
        case window(WindowSwitchEntry)
        case stack(Stack)

        var id: String {
            switch self {
            case .window(let entry): "window:" + entry.id
            case .stack(let stack): stack.id
            }
        }

        /// The window a switch lands on: a stack stands for its frontmost one.
        var target: WindowSwitchEntry? {
            switch self {
            case .window(let entry): entry
            case .stack(let stack): stack.windows.first
            }
        }
    }

    /// An outline in groups mode: a kind of app, by the system's name for it, or one made by hand.
    enum Group: Hashable, Codable, Sendable {
        case appType(String)
        case custom(Int)
    }

    struct Section: Equatable, Sendable {
        let group: Group
        let count: Int
    }

    /// Where a dragged tile was let go: on another tile, on a section's background, or in the gap
    /// before the section with that index, where a group of its own would be put.
    enum Drop: Equatable, Sendable {
        case tile(Int)
        case section(Int)
        case slot(Int)
    }

    private(set) var entries: [WindowSwitchEntry]
    private(set) var tiles: [Tile] = []
    private(set) var selection = 0
    private(set) var mode: WindowPickerMode
    /// Groups mode only, in tile order: each section's tiles follow the one before.
    private(set) var sections: [Section] = []
    /// Bundle ID to the group its app was dragged into; every other app sits with its own kind.
    private(set) var appGroups: [String: Group]
    /// Every group known, in layout order; one first seen here joins after the ones placed before.
    private(set) var groupOrder: [Group]
    private let appTypes: [Int: String]
    private(set) var expandedBundleID: String?
    /// What has been typed. It reorders the tiles, matches first, and never removes one.
    private(set) var query = ""
    /// The handles the query leaves out; their tiles stay in place, dimmed.
    private(set) var unmatched: Set<Int> = []
    /// The stack just stepped out of: it must not reopen by itself while still selected.
    private var leftBundleID: String?
    /// False for one app's windows, where a single stack would be the whole board.
    let allowsStacking: Bool

    init(
        entries: [WindowSwitchEntry], mode: WindowPickerMode, allowsStacking: Bool = true,
        backwards: Bool = false, appTypes: [Int: String] = [:], appGroups: [String: Group] = [:],
        groupOrder: [Group] = []
    ) {
        self.groupOrder = groupOrder
        self.entries = entries
        self.allowsStacking = allowsStacking
        self.mode = allowsStacking ? mode : .windows
        self.appTypes = appTypes
        self.appGroups = appGroups
        rebuild()
        guard tiles.count > 1 else { return }
        // The first window is where the user already is, so a press lands on the one behind it.
        if self.mode == .groups {
            let behind = backwards ? entries[entries.count - 1] : entries[1]
            selection = index(holding: behind) ?? 0
        } else {
            selection = backwards ? tiles.count - 1 : 1
        }
    }

    var isStacked: Bool { mode == .stacks }

    var selectedTile: Tile? { tiles.indices.contains(selection) ? tiles[selection] : nil }

    var target: WindowSwitchEntry? { selectedTile?.target }

    var expandedStack: Stack? {
        expandedBundleID.flatMap { stack(for: $0, in: entries) }
    }

    var showsHeader: Bool { expandedBundleID != nil }

    /// A stack counts as a match while any window in it does.
    func isDimmed(_ tile: Tile) -> Bool {
        switch tile {
        case .window(let entry): unmatched.contains(entry.handle)
        case .stack(let stack): stack.windows.allSatisfy { unmatched.contains($0.handle) }
        }
    }

    var canExpandSelection: Bool {
        guard expandedBundleID == nil, case .stack = selectedTile else { return false }
        return true
    }

    /// What the dwell delay asks; right ⇧ and a number still open a stack just left.
    var canAutoExpandSelection: Bool {
        guard canExpandSelection, case .stack(let stack) = selectedTile else { return false }
        return stack.bundleID != leftBundleID
    }

    mutating func step(by offset: Int) {
        guard !tiles.isEmpty else { return }
        selection = ((selection + offset) % tiles.count + tiles.count) % tiles.count
        forgetLeftStackIfMoved()
    }

    private mutating func forgetLeftStackIfMoved() {
        guard case .stack(let stack) = selectedTile, stack.bundleID == leftBundleID else {
            leftBundleID = nil
            return
        }
    }

    /// Rows do not wrap: past the first or last one the selection stays where it is.
    mutating func move(_ direction: WindowPickerKeyEngine.Direction, columns: Int) {
        switch direction {
        case .left: step(by: -1)
        case .right: step(by: 1)
        case .up: select(selection - max(columns, 1))
        case .down: select(selection + max(columns, 1))
        }
    }

    mutating func select(_ index: Int) {
        guard tiles.indices.contains(index) else { return }
        selection = index
        forgetLeftStackIfMoved()
    }

    /// Left ⇧: windows, stacks, groups, and round again. Inside a stack it steps back out first.
    mutating func cycleMode() {
        guard allowsStacking else { return }
        guard expandedBundleID == nil else { return collapse() }
        let anchor = target
        mode = mode.next
        rebuild()
        selection = anchor.flatMap(index(holding:)) ?? 0
        leftBundleID = nil
    }

    /// A drag moves the window's whole app: into the group it lands on, or out into a new one.
    mutating func drop(tileAt index: Int, on drop: Drop) {
        guard mode == .groups, tiles.indices.contains(index), let moved = tiles[index].target
        else { return }
        let destination: Group
        switch drop {
        case .tile(let targetIndex):
            guard targetIndex != index, tiles.indices.contains(targetIndex),
                let target = tiles[targetIndex].target
            else { return }
            destination = group(of: target)
        case .section(let sectionIndex):
            guard sections.indices.contains(sectionIndex) else { return }
            destination = sections[sectionIndex].group
        case .slot(let slot):
            guard !isAlone(moved) else {
                // Alone in its group already, so the gap only says where that group should sit.
                let home = sections.firstIndex { $0.group == group(of: moved) }
                return home.map { moveSection(from: $0, toSlot: slot) } ?? ()
            }
            let numbers = appGroups.values.compactMap { group -> Int? in
                if case .custom(let number) = group { return number }
                return nil
            }
            destination = .custom((numbers.max() ?? 0) + 1)
        }
        // Back with its own kind is no override at all.
        appGroups[moved.bundleID] = destination == nativeGroup(of: moved) ? nil : destination
        rebuild()
        // A new group is born last; the gap it was dropped in is where it was meant to go.
        if case .slot(let slot) = drop, let born = sections.firstIndex(where: { $0.group == destination }) {
            moveSection(from: born, toSlot: slot)
        }
        selection = self.index(holding: moved) ?? 0
    }

    private func isAlone(_ entry: WindowSwitchEntry) -> Bool {
        let current = group(of: entry)
        return !entries.contains { $0.bundleID != entry.bundleID && group(of: $0) == current }
    }

    /// Slot N is the gap before section N, and one past the last is the end. The two gaps beside
    /// a section are where it already is.
    mutating func moveSection(from source: Int, toSlot slot: Int) {
        guard mode == .groups, sections.indices.contains(source), (0...sections.count).contains(slot),
            slot != source, slot != source + 1
        else { return }
        let anchor = target
        var visible = sections.map(\.group)
        visible.insert(visible.remove(at: source), at: slot > source ? slot - 1 : slot)
        groupOrder = WindowPickerGroupBook.reordered(groupOrder, visible: visible)
        rebuild()
        selection = anchor.flatMap(index(holding:)) ?? 0
    }

    private func nativeGroup(of entry: WindowSwitchEntry) -> Group {
        .appType(appTypes[entry.handle] ?? "")
    }

    private func group(of entry: WindowSwitchEntry) -> Group {
        appGroups[entry.bundleID] ?? nativeGroup(of: entry)
    }

    mutating func toggleStack() {
        if expandedBundleID == nil { expandSelection() } else { collapse() }
    }

    mutating func expandSelection() {
        guard expandedBundleID == nil, case .stack(let stack) = selectedTile else { return }
        expandedBundleID = stack.bundleID
        rebuild()
        // Inside the front app's stack the first window is the current one, as on the board.
        let holdsCurrent = stack.windows.first?.handle == entries.first?.handle
        selection = holdsCurrent && tiles.count > 1 ? 1 : 0
    }

    mutating func type(_ text: String) {
        // A leading space would only hide every tile behind a query that looks empty.
        guard !(query.isEmpty && text.allSatisfy(\.isWhitespace)) else { return }
        search(query + text)
    }

    mutating func deleteBackward() {
        guard !query.isEmpty else { return }
        search(String(query.dropLast()))
    }

    /// Escape, one layer at a time: the search, then the open stack. False leaves the picker.
    mutating func stepBack() -> Bool {
        if !query.isEmpty {
            search("")
            return true
        }
        guard expandedBundleID != nil else { return false }
        collapse()
        return true
    }

    private mutating func search(_ text: String) {
        query = text
        rebuild()
        // Groups keep their places, so the selection goes to the first match instead of the front.
        selection = mode == .groups ? tiles.firstIndex { !isDimmed($0) } ?? 0 : 0
        forgetLeftStackIfMoved()
    }

    mutating func collapse() {
        guard let bundleID = expandedBundleID else { return }
        expandedBundleID = nil
        rebuild()
        selection = tiles.firstIndex { $0.target?.bundleID == bundleID } ?? 0
        leftBundleID = bundleID
    }

    /// A window's state changed under the picker; its tile stays where it is.
    mutating func update(handle: Int, _ change: (inout WindowSwitchEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.handle == handle }) else { return }
        let selected = selection
        change(&entries[index])
        rebuild()
        selection = min(selected, max(tiles.count - 1, 0))
    }

    mutating func remove(handles: Set<Int>) {
        guard !handles.isEmpty else { return }
        let anchor = target.flatMap { handles.contains($0.handle) ? nil : $0 }
        let previous = selection
        entries.removeAll { handles.contains($0.handle) }
        if let expandedBundleID, stack(for: expandedBundleID, in: entries) == nil {
            self.expandedBundleID = nil
        }
        rebuild()
        selection = anchor.flatMap(index(holding:)) ?? min(previous, max(tiles.count - 1, 0))
    }

    private func index(holding entry: WindowSwitchEntry) -> Int? {
        tiles.firstIndex { tile in
            switch tile {
            case .window(let window): window.handle == entry.handle
            case .stack(let stack): stack.windows.contains { $0.handle == entry.handle }
            }
        }
    }

    private func stack(for bundleID: String, in entries: [WindowSwitchEntry]) -> Stack? {
        let windows = entries.filter { $0.bundleID == bundleID }
        guard let first = windows.first else { return nil }
        return Stack(
            bundleID: bundleID, appName: first.appName, iconURL: first.iconURL,
            iconStamp: first.iconStamp, windows: windows)
    }

    /// Name-prefix matches, then the other matches, then the rest, each still front to back.
    private func ranked() -> (entries: [WindowSwitchEntry], unmatched: Set<Int>) {
        let needle = Self.folded(query.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return (entries, []) }
        var ranks: [[WindowSwitchEntry]] = [[], [], []]
        for entry in entries {
            let app = Self.folded(entry.appName)
            if app.hasPrefix(needle) {
                ranks[0].append(entry)
            } else if app.contains(needle) || Self.folded(entry.displayTitle).contains(needle) {
                ranks[1].append(entry)
            } else {
                ranks[2].append(entry)
            }
        }
        return (ranks[0] + ranks[1] + ranks[2], Set(ranks[2].map(\.handle)))
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private mutating func rebuild() {
        let ranked = ranked()
        unmatched = ranked.unmatched
        sections = []
        if mode == .groups, expandedBundleID == nil { return rebuildGroups() }
        let entries = ranked.entries
        if let expandedBundleID {
            tiles = entries.filter { $0.bundleID == expandedBundleID }.map(Tile.window)
            return
        }
        guard isStacked else {
            tiles = entries.map(Tile.window)
            return
        }
        var seen: Set<String> = []
        tiles = entries.compactMap { entry in
            guard seen.insert(entry.bundleID).inserted,
                let stack = stack(for: entry.bundleID, in: entries)
            else { return nil }
            // An app with one window has nothing to open, so it stays a plain window tile.
            return stack.windows.count > 1 ? .stack(stack) : .window(entry)
        }
    }

    /// Sections keep the places they were given, so a group is where it was last time.
    private mutating func rebuildGroups() {
        let members = Dictionary(grouping: entries, by: group(of:))
        let placed = Set(groupOrder)
        groupOrder += members.keys.filter { !placed.contains($0) }.sorted(by: Self.precedes)
        let order = groupOrder.filter { members[$0] != nil }
        sections = order.map { Section(group: $0, count: members[$0]?.count ?? 0) }
        tiles = order.flatMap { members[$0] ?? [] }.map(Tile.window)
    }

    /// Where a group lands before anyone has placed it: hand-made, then kinds by name, then none.
    private static func precedes(_ left: Group, _ right: Group) -> Bool {
        switch (left, right) {
        case (.custom(let first), .custom(let second)): first < second
        case (.custom, .appType): true
        case (.appType, .custom): false
        case (.appType(let first), .appType(let second)):
            if first.isEmpty != second.isEmpty { !first.isEmpty } else {
                first.localizedStandardCompare(second) == .orderedAscending
            }
        }
    }
}
