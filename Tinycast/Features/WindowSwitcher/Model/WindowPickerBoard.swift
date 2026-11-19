import Foundation

/// What the picker shows and where its selection is: flat, grouped by app, or inside one group.
struct WindowPickerBoard: Equatable, Sendable {
    struct Group: Identifiable, Hashable, Sendable {
        let bundleID: String
        let appName: String
        let iconURL: URL?
        let iconStamp: Int
        let windows: [WindowSwitchEntry]

        var id: String { "group:" + bundleID }
    }

    enum Tile: Identifiable, Hashable, Sendable {
        case window(WindowSwitchEntry)
        case group(Group)

        var id: String {
            switch self {
            case .window(let entry): "window:" + entry.id
            case .group(let group): group.id
            }
        }

        /// The window a switch lands on: a group stands for its frontmost one.
        var target: WindowSwitchEntry? {
            switch self {
            case .window(let entry): entry
            case .group(let group): group.windows.first
            }
        }
    }

    private(set) var entries: [WindowSwitchEntry]
    private(set) var tiles: [Tile] = []
    private(set) var selection = 0
    private(set) var isGrouped: Bool
    private(set) var expandedBundleID: String?
    /// False for one app's windows, where a single group would be the whole board.
    let allowsGrouping: Bool

    init(
        entries: [WindowSwitchEntry], isGrouped: Bool, allowsGrouping: Bool = true,
        backwards: Bool = false
    ) {
        self.entries = entries
        self.allowsGrouping = allowsGrouping
        self.isGrouped = isGrouped && allowsGrouping
        rebuild()
        // The first tile is where the user already is, so a press lands on the one behind it.
        if tiles.count > 1 { selection = backwards ? tiles.count - 1 : 1 }
    }

    var selectedTile: Tile? { tiles.indices.contains(selection) ? tiles[selection] : nil }

    var target: WindowSwitchEntry? { selectedTile?.target }

    var expandedGroup: Group? {
        expandedBundleID.flatMap { group(for: $0) }
    }

    var canExpandSelection: Bool {
        guard expandedBundleID == nil, case .group = selectedTile else { return false }
        return true
    }

    mutating func step(by offset: Int) {
        guard !tiles.isEmpty else { return }
        selection = ((selection + offset) % tiles.count + tiles.count) % tiles.count
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
    }

    mutating func toggleGrouping() {
        guard allowsGrouping else { return }
        guard expandedBundleID == nil else { return collapse() }
        let anchor = target
        isGrouped.toggle()
        rebuild()
        selection = anchor.flatMap(index(holding:)) ?? 0
    }

    mutating func toggleGroup() {
        if expandedBundleID == nil { expandSelection() } else { collapse() }
    }

    mutating func expandSelection() {
        guard expandedBundleID == nil, case .group(let group) = selectedTile else { return }
        expandedBundleID = group.bundleID
        rebuild()
        // Inside the front app's group the first window is the current one, as on the board.
        let holdsCurrent = group.windows.first?.handle == entries.first?.handle
        selection = holdsCurrent && tiles.count > 1 ? 1 : 0
    }

    mutating func collapse() {
        guard let bundleID = expandedBundleID else { return }
        expandedBundleID = nil
        rebuild()
        selection = tiles.firstIndex { $0.target?.bundleID == bundleID } ?? 0
    }

    mutating func remove(handles: Set<Int>) {
        guard !handles.isEmpty else { return }
        let anchor = target.flatMap { handles.contains($0.handle) ? nil : $0 }
        let previous = selection
        entries.removeAll { handles.contains($0.handle) }
        if let expandedBundleID, group(for: expandedBundleID) == nil { self.expandedBundleID = nil }
        rebuild()
        selection = anchor.flatMap(index(holding:)) ?? min(previous, max(tiles.count - 1, 0))
    }

    private func index(holding entry: WindowSwitchEntry) -> Int? {
        tiles.firstIndex { tile in
            switch tile {
            case .window(let window): window.handle == entry.handle
            case .group(let group): group.windows.contains { $0.handle == entry.handle }
            }
        }
    }

    private func group(for bundleID: String) -> Group? {
        let windows = entries.filter { $0.bundleID == bundleID }
        guard let first = windows.first else { return nil }
        return Group(
            bundleID: bundleID, appName: first.appName, iconURL: first.iconURL,
            iconStamp: first.iconStamp, windows: windows)
    }

    private mutating func rebuild() {
        if let expandedBundleID {
            tiles = entries.filter { $0.bundleID == expandedBundleID }.map(Tile.window)
            return
        }
        guard isGrouped else {
            tiles = entries.map(Tile.window)
            return
        }
        var seen: Set<String> = []
        tiles = entries.compactMap { entry in
            guard seen.insert(entry.bundleID).inserted, let group = group(for: entry.bundleID)
            else { return nil }
            // An app with one window has nothing to open, so it stays a plain window tile.
            return group.windows.count > 1 ? .group(group) : .window(entry)
        }
    }
}
