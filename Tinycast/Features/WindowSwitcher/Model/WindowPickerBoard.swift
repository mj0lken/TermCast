import Foundation

/// What the picker shows and where its selection is: flat, stacked by app, or inside one stack.
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

    private(set) var entries: [WindowSwitchEntry]
    private(set) var tiles: [Tile] = []
    private(set) var selection = 0
    private(set) var isStacked: Bool
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
        entries: [WindowSwitchEntry], isStacked: Bool, allowsStacking: Bool = true,
        backwards: Bool = false
    ) {
        self.entries = entries
        self.allowsStacking = allowsStacking
        self.isStacked = isStacked && allowsStacking
        rebuild()
        // The first tile is where the user already is, so a press lands on the one behind it.
        if tiles.count > 1 { selection = backwards ? tiles.count - 1 : 1 }
    }

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

    mutating func toggleStacking() {
        guard allowsStacking else { return }
        guard expandedBundleID == nil else { return collapse() }
        let anchor = target
        isStacked.toggle()
        rebuild()
        selection = anchor.flatMap(index(holding:)) ?? 0
        leftBundleID = nil
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
        selection = 0
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
        let entries = ranked.entries
        unmatched = ranked.unmatched
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
}
