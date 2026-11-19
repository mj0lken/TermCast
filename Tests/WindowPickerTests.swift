import Foundation

@main
@MainActor
struct WindowPickerTests {
    typealias Engine = WindowPickerKeyEngine
    typealias Key = WindowPickerKeyEngine.KeyCode

    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func entry(
        _ handle: Int, app: String = "Safari", minimized: Bool = false, rank: Int = 0
    ) -> WindowSwitchEntry {
        WindowSwitchEntry(
            handle: handle, appName: app, bundleID: "com.example.\(app.lowercased())",
            iconURL: nil, iconStamp: 0, title: "Window \(handle)", isMinimized: minimized,
            appRank: rank)
    }

    /// Finder ×3 in front, then Safari ×2, then one Mail window.
    static let desk = [
        entry(0, app: "Finder"), entry(1, app: "Safari"), entry(2, app: "Finder"),
        entry(3, app: "Mail"), entry(4, app: "Safari"), entry(5, app: "Finder")
    ]

    static func engine() -> Engine {
        Engine(triggers: Engine.triggers(allWindows: .command, frontApp: .option))
    }

    static func main() {
        triggers()
        opening()
        steppingAndRelease()
        shiftTaps()
        keysWhileOpen()
        ordering()
        flatBoard()
        groupedBoard()
        expanding()
        togglingKeepsTheWindow()
        frontAppBoard()
        removal()
        geometry()

        print(failures == 0 ? "Window picker tests passed" : "\(failures) window picker tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Keys

    static func triggers() {
        expect(
            Engine.triggers(allWindows: .off, frontApp: .off).isEmpty, "two chords off bind nothing")
        let both = Engine.triggers(allWindows: .command, frontApp: .control)
        expect(
            both == [
                .init(scope: .allWindows, modifier: .command, keyCode: Key.tab),
                .init(scope: .frontApp, modifier: .control, keyCode: Key.grave)
            ], "each scope keeps its own key under its own modifier")
    }

    static func opening() {
        var keys = engine()
        expect(keys.keyDown(Key.tab, modifiers: []) == .passed, "a bare Tab is not ours")
        expect(
            keys.keyDown(Key.tab, modifiers: [.command, .option]) == .passed,
            "an extra modifier is another app's chord")
        expect(keys.keyDown(0, modifiers: .command) == .passed, "⌘A travels on while closed")
        expect(
            keys.keyDown(Key.tab, modifiers: .command)
                == .init(command: .open(.allWindows, backwards: false), swallows: true),
            "⌘⇥ opens every window and is swallowed")
        keys.reset()
        expect(
            keys.keyDown(Key.tab, modifiers: [.command, .shift]).command
                == .open(.allWindows, backwards: true), "⌘⇧⇥ opens walking backwards")
        keys.reset()
        expect(
            keys.keyDown(Key.grave, modifiers: .option).command == .open(.frontApp, backwards: false),
            "⌥` opens the front app's windows")
    }

    static func steppingAndRelease() {
        var keys = engine()
        _ = keys.keyDown(Key.tab, modifiers: .command)
        expect(keys.keyDown(Key.tab, modifiers: .command).command == .step(1), "⇥ again steps on")
        expect(
            keys.keyDown(Key.tab, modifiers: [.command, .shift]).command == .step(-1),
            "⇧⇥ steps back")
        expect(
            keys.modifiersChanged(keyCode: 58, isDown: true, modifiers: [.command, .option]) == nil,
            "another modifier going down changes nothing")
        expect(
            keys.modifiersChanged(keyCode: 55, isDown: false, modifiers: []) == .commit,
            "letting go of ⌘ switches")
        expect(keys.active == nil, "and the engine is closed again")
        expect(
            keys.modifiersChanged(keyCode: 55, isDown: false, modifiers: []) == nil,
            "a release while closed is nobody's")
    }

    static func shiftTaps() {
        var keys = engine()
        _ = keys.keyDown(Key.tab, modifiers: .command)
        expect(
            keys.modifiersChanged(
                keyCode: Key.leftShift, isDown: true, modifiers: [.command, .shift]) == nil,
            "a Shift going down decides nothing yet")
        expect(
            keys.modifiersChanged(keyCode: Key.leftShift, isDown: false, modifiers: .command)
                == .toggleGrouping, "a left Shift tap toggles grouping")
        _ = keys.modifiersChanged(
            keyCode: Key.rightShift, isDown: true, modifiers: [.command, .shift])
        expect(
            keys.modifiersChanged(keyCode: Key.rightShift, isDown: false, modifiers: .command)
                == .toggleGroup, "a right Shift tap opens the group")

        _ = keys.modifiersChanged(
            keyCode: Key.leftShift, isDown: true, modifiers: [.command, .shift])
        _ = keys.keyDown(Key.tab, modifiers: [.command, .shift])
        expect(
            keys.modifiersChanged(keyCode: Key.leftShift, isDown: false, modifiers: .command) == nil,
            "a Shift that stepped backwards was a modifier, not a tap")

        var held = engine()
        _ = held.keyDown(Key.tab, modifiers: [.command, .shift])
        expect(
            held.modifiersChanged(keyCode: Key.leftShift, isDown: false, modifiers: .command) == nil,
            "a Shift already down when the picker opened is not a tap either")
    }

    static func keysWhileOpen() {
        var keys = engine()
        _ = keys.keyDown(Key.tab, modifiers: .command)
        expect(keys.keyDown(Key.rightArrow, modifiers: .command).command == .move(.right), "→ moves")
        expect(keys.keyDown(Key.upArrow, modifiers: .command).command == .move(.up), "↑ moves")
        expect(keys.keyDown(13, modifiers: .command).command == .perform(.close), "W closes")
        expect(keys.keyDown(12, modifiers: .command).command == .perform(.quit), "Q quits")
        expect(keys.keyDown(4, modifiers: .command).command == .perform(.hide), "H hides")
        expect(keys.keyDown(18, modifiers: .command).command == .pick(0), "1 picks the first tile")
        expect(keys.keyDown(25, modifiers: .command).command == .pick(8), "9 picks the ninth")
        expect(keys.keyDown(29, modifiers: .command).command == nil, "0 picks nothing")
        expect(
            keys.keyDown(0, modifiers: .command) == .init(command: nil, swallows: true),
            "an unbound key is swallowed, so ⌘A never reaches the app underneath")
        expect(keys.keyDown(Key.escape, modifiers: .command).command == .cancel, "Escape cancels")
        expect(
            keys.modifiersChanged(keyCode: 55, isDown: false, modifiers: []) == nil,
            "and the ⌘ release after it switches nothing")

        var remapped = Engine(
            triggers: Engine.triggers(allWindows: .command, frontApp: .off), actionKeys: [0: .quit])
        _ = remapped.keyDown(Key.tab, modifiers: .command)
        expect(
            remapped.keyDown(0, modifiers: .command).command == .perform(.quit),
            "the action keys follow the layout they were handed")
        expect(remapped.keyDown(Key.returnKey, modifiers: .command).command == .commit, "↵ switches")
        expect(remapped.active == nil, "↵ closes the engine")
    }

    // MARK: - Order

    static func ordering() {
        let entries = [
            entry(0, app: "Mail", rank: 1), entry(1, app: "Safari", rank: 0),
            entry(2, app: "Safari", rank: 0), entry(3, app: "Zed", minimized: true, rank: .max),
            entry(4, app: "Notes", rank: .max)
        ]
        let sorted = WindowPickerOrder.sorted(entries, windowRanks: [1: 0, 0: 1, 2: 2])
        expect(
            sorted.map(\.handle) == [1, 0, 2, 4, 3],
            "windows interleave across apps by their own rank: \(sorted.map(\.handle))")
        let unranked = WindowPickerOrder.sorted(entries, windowRanks: [:])
        expect(
            unranked.map(\.handle) == WindowSwitchOrder.sorted(entries).map(\.handle),
            "with no window ranks the order is the per-app one")
        expect(
            WindowPickerOrder.sorted(entries.reversed(), windowRanks: [1: 0, 0: 1, 2: 2]) == sorted,
            "the order is total, whatever the sweep enumerated first")
    }

    // MARK: - Board

    static func flatBoard() {
        var board = WindowPickerBoard(entries: desk, isGrouped: false)
        expect(board.tiles.count == 6, "ungrouped, every window is a tile")
        expect(board.selection == 1, "it opens on the window behind the current one")
        expect(!board.canExpandSelection, "a window has nothing to open")
        board.step(by: -2)
        expect(board.selection == 5, "stepping back wraps to the last tile")
        board.step(by: 1)
        expect(board.selection == 0, "and forward wraps to the first")
        board.move(.down, columns: 4)
        expect(board.selection == 4, "↓ drops one row")
        board.move(.down, columns: 4)
        expect(board.selection == 4, "and stays put with no row below")
        expect(
            WindowPickerBoard(entries: desk, isGrouped: false, backwards: true).selection == 5,
            "opened backwards it starts on the last tile")
        expect(
            WindowPickerBoard(entries: [entry(0)], isGrouped: false).selection == 0,
            "a single window is selected itself")
        expect(WindowPickerBoard(entries: [], isGrouped: true).target == nil, "no windows, no target")
    }

    static func groupedBoard() {
        let board = WindowPickerBoard(entries: desk, isGrouped: true)
        expect(
            board.tiles.map(\.id) == ["group:com.example.finder", "group:com.example.safari", "window:3"],
            "apps group in first-seen order, a lone window stays a window: \(board.tiles.map(\.id))")
        expect(board.target?.handle == 1, "a group stands for its frontmost window")
        expect(board.canExpandSelection, "a group can open")
    }

    static func expanding() {
        var board = WindowPickerBoard(entries: desk, isGrouped: true)
        board.toggleGroup()
        expect(board.expandedGroup?.appName == "Safari", "the selected group opened")
        expect(board.tiles.compactMap(\.target).map(\.handle) == [1, 4], "showing only its windows")
        expect(board.selection == 0, "on its frontmost window")
        board.step(by: 1)
        board.step(by: 1)
        expect(board.selection == 0, "stepping stays inside the group")
        board.toggleGroup()
        expect(
            board.expandedGroup == nil && board.selectedTile?.id == "group:com.example.safari",
            "closing it returns to the group's own tile")

        board.select(0)
        board.expandSelection()
        expect(board.selection == 1, "the front app's group opens past the current window")
        board.toggleGrouping()
        expect(
            board.expandedGroup == nil && board.isGrouped,
            "left Shift inside a group steps back out rather than ungrouping")
    }

    static func togglingKeepsTheWindow() {
        var board = WindowPickerBoard(entries: desk, isGrouped: false)
        board.select(4)
        board.toggleGrouping()
        expect(
            board.isGrouped && board.selectedTile?.id == "group:com.example.safari",
            "grouping selects the group holding the selected window")
        board.toggleGrouping()
        expect(
            !board.isGrouped && board.target?.handle == 1,
            "ungrouping selects that group's frontmost window")
    }

    static func frontAppBoard() {
        let finder = desk.filter { $0.appName == "Finder" }
        var board = WindowPickerBoard(entries: finder, isGrouped: true, allowsGrouping: false)
        expect(!board.isGrouped && board.tiles.count == 3, "one app's windows never group")
        board.toggleGrouping()
        expect(!board.isGrouped, "and the toggle is inert there")
    }

    static func removal() {
        var board = WindowPickerBoard(entries: desk, isGrouped: true)
        board.toggleGroup()
        board.remove(handles: [1, 4])
        expect(board.expandedGroup == nil, "an open group whose app quit closes")
        expect(
            board.tiles.map(\.id) == ["group:com.example.finder", "window:3"],
            "and its tile leaves the board")
        var flat = WindowPickerBoard(entries: desk, isGrouped: false)
        flat.select(5)
        flat.remove(handles: [5])
        expect(flat.selection == 4, "removing the last selected tile clamps the selection")
        flat.select(2)
        flat.remove(handles: [0])
        expect(flat.target?.handle == 2, "removing an earlier tile keeps the selected window")
    }

    // MARK: - Geometry

    static func geometry() {
        let screen = CGSize(width: 1512, height: 982)
        let few = WindowPickerGeometry.layout(tileCount: 3, screen: screen, showsHeader: false)
        expect(few.columns == 3 && few.rows == 1, "a few tiles sit on one row")
        let many = WindowPickerGeometry.layout(tileCount: 40, screen: screen, showsHeader: false)
        expect(many.rows > 1, "many tiles wrap")
        expect(many.preview.width < few.preview.width, "and shrink before they overflow")
        expect(
            many.panel.width <= screen.width && many.panel.height <= screen.height,
            "the panel stays on the screen: \(many.panel)")
        expect(
            WindowPickerGeometry.layout(tileCount: 0, screen: screen, showsHeader: false).columns == 1,
            "an empty board still has a size")
        let headed = WindowPickerGeometry.layout(tileCount: 3, screen: screen, showsHeader: true)
        expect(
            headed.panel.height == few.panel.height + WindowPickerGeometry.headerHeight,
            "an open group's header adds its own height")

        typealias Limits = WindowPickerGeometry.Limits
        func laid(_ count: Int, _ limits: Limits) -> WindowPickerGeometry.Layout {
            WindowPickerGeometry.layout(
                tileCount: count, screen: screen, showsHeader: false, limits: limits)
        }
        let capped = laid(7, Limits(maxColumns: 3))
        expect(capped.columns == 3 && capped.rows == 3, "a column limit wraps sooner")
        expect(laid(2, Limits(maxColumns: 3)).columns == 2, "and never pads a short board")
        let twoRows = laid(14, Limits(maxRows: 2))
        expect(twoRows.rows <= 2, "a row limit holds while tiles can shrink: \(twoRows.rows)")
        expect(
            twoRows.preview.width < laid(14, Limits()).preview.width,
            "by shrinking the tiles")
        let both = laid(20, Limits(maxColumns: 3, maxRows: 2))
        expect(both.columns == 3 && both.rows == 7, "rows give way once the columns run out")
        let narrow = laid(12, Limits(widthShare: 0.5, heightShare: 0.5))
        expect(
            narrow.panel.width <= screen.width * 0.5 && narrow.panel.height <= screen.height * 0.5,
            "the panel stays inside its share of the screen: \(narrow.panel)")
        expect(
            laid(3, Limits(tileScale: 1.35)).preview.width > few.preview.width
                && laid(3, Limits(tileScale: 0.75)).preview.width < few.preview.width,
            "the window size scales the tiles")
    }
}
