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

    /// An outline in groups mode: the kind of app its windows belong to, or one made by hand.
    enum Group: Hashable, Sendable {
        case appType(String)
        case custom(Int)
    }

    struct Section: Equatable, Sendable {
        let group: Group
        let count: Int
    }

    /// Where a dragged tile was let go: on another tile, or on a section's own background.
    enum Drop: Equatable, Sendable {
        case tile(Int)
        case section(Int)
    }

    private(set) var entries: [WindowSwitchEntry]
    private(set) var tiles: [Tile] = []
    private(set) var selection = 0
    private(set) var mode: WindowPickerMode
    /// Groups mode only, in tile order: each section's tiles follow the one before.
    private(set) var sections: [Section] = []
    /// Handle to a hand-made group's number; every other window falls in its app's type.
    private(set) var customGroups: [Int: Int]
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
        backwards: Bool = false, appTypes: [Int: String] = [:], customGroups: [Int: Int] = [:]
    ) {
        self.entries = entries
        self.allowsStacking = allowsStacking
        self.mode = allowsStacking ? mode : .windows
        self.appTypes = appTypes
        self.customGroups = customGroups
        dissolveLoneGroups()
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

    /// Dropping on a window joins its hand-made group, or starts one with it.
    mutating func drop(tileAt index: Int, on drop: Drop) {
        guard mode == .groups, tiles.indices.contains(index), let moved = tiles[index].target
        else { return }
        switch drop {
        case .tile(let targetIndex):
            guard targetIndex != index, tiles.indices.contains(targetIndex),
                let target = tiles[targetIndex].target
            else { return }
            let number = customGroups[target.handle] ?? (customGroups.values.max() ?? 0) + 1
            customGroups[target.handle] = number
            customGroups[moved.handle] = number
        case .section(let sectionIndex):
            guard sections.indices.contains(sectionIndex) else { return }
            // An app-type outline takes nothing in: letting go there sends the window home.
            if case .custom(let number) = sections[sectionIndex].group {
                customGroups[moved.handle] = number
            } else {
                customGroups[moved.handle] = nil
            }
        }
        dissolveLoneGroups()
        rebuild()
        selection = self.index(holding: moved) ?? 0
    }

    /// A group of one is no group, so its window returns to its app's type.
    private mutating func dissolveLoneGroups() {
        let present = Set(entries.map(\.handle))
        customGroups = customGroups.filter { present.contains($0.key) }
        let sizes = Dictionary(grouping: customGroups.values, by: \.self).mapValues(\.count)
        customGroups = customGroups.filter { (sizes[$0.value] ?? 0) > 1 }
    }

    private func group(of entry: WindowSwitchEntry) -> Group {
        customGroups[entry.handle].map(Group.custom) ?? .appType(appTypes[entry.handle] ?? "")
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

    mutating func remove(handles: Set<Int>) {
        guard !handles.isEmpty else { return }
        let anchor = target.flatMap { handles.contains($0.handle) ? nil : $0 }
        let previous = selection
        entries.removeAll { handles.contains($0.handle) }
        dissolveLoneGroups()
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

    /// Sections in the order their frontmost window appears; a search dims but never moves one.
    private mutating func rebuildGroups() {
        var order: [Group] = []
        var members: [Group: [WindowSwitchEntry]] = [:]
        for entry in entries {
            let group = group(of: entry)
            if members[group] == nil { order.append(group) }
            members[group, default: []].append(entry)
        }
        sections = order.map { Section(group: $0, count: members[$0]?.count ?? 0) }
        tiles = order.flatMap { members[$0] ?? [] }.map(Tile.window)
    }
}
