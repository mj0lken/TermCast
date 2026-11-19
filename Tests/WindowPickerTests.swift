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
        stackedBoard()
        expanding()
        togglingKeepsTheWindow()
        frontAppBoard()
        removal()
        groupsBoard()
        searching()
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
                == .cycleMode, "a left Shift tap toggles stacking")
        _ = keys.modifiersChanged(
            keyCode: Key.rightShift, isDown: true, modifiers: [.command, .shift])
        expect(
            keys.modifiersChanged(keyCode: Key.rightShift, isDown: false, modifiers: .command)
                == .toggleStack, "a right Shift tap opens the stack")

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
        expect(keys.keyDown(Key.escape, modifiers: .command).command == .back, "Escape steps back")
        expect(keys.active != nil, "and leaves closing to whoever knows what is open")
        expect(keys.keyDown(51, modifiers: .command).command == nil, "⌫ is nothing with search off")
        var typing = Engine(
            triggers: Engine.triggers(allWindows: .command, frontApp: .off),
            characters: [3: "f", 13: "w"])
        _ = typing.keyDown(Key.tab, modifiers: .command)
        expect(typing.keyDown(3, modifiers: .command).command == .type("f"), "a letter types")
        expect(typing.keyDown(13, modifiers: .command).command == .type("w"), "W types too")
        expect(typing.keyDown(51, modifiers: .command).command == .deleteBackward, "⌫ deletes")
        expect(
            typing.keyDown(13, modifiers: [.command, .shift]).command == .perform(.close),
            "and ⇧W is still the action")
        expect(typing.keyDown(49, modifiers: .command).command == .type(" "), "space types")
        keys.reset()
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
        var board = WindowPickerBoard(entries: desk, mode: .windows)
        expect(board.tiles.count == 6, "unstacked, every window is a tile")
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
            WindowPickerBoard(entries: desk, mode: .windows, backwards: true).selection == 5,
            "opened backwards it starts on the last tile")
        expect(
            WindowPickerBoard(entries: [entry(0)], mode: .windows).selection == 0,
            "a single window is selected itself")
        expect(WindowPickerBoard(entries: [], mode: .stacks).target == nil, "no windows, no target")
    }

    static func stackedBoard() {
        let board = WindowPickerBoard(entries: desk, mode: .stacks)
        expect(
            board.tiles.map(\.id) == ["stack:com.example.finder", "stack:com.example.safari", "window:3"],
            "apps stack in first-seen order, a lone window stays a window: \(board.tiles.map(\.id))")
        expect(board.target?.handle == 1, "a stack stands for its frontmost window")
        expect(board.canExpandSelection, "a stack can open")
    }

    static func expanding() {
        var board = WindowPickerBoard(entries: desk, mode: .stacks)
        board.toggleStack()
        expect(board.expandedStack?.appName == "Safari", "the selected stack opened")
        expect(board.tiles.compactMap(\.target).map(\.handle) == [1, 4], "showing only its windows")
        expect(board.selection == 0, "on its frontmost window")
        board.step(by: 1)
        board.step(by: 1)
        expect(board.selection == 0, "stepping stays inside the stack")
        board.toggleStack()
        expect(
            board.expandedStack == nil && board.selectedTile?.id == "stack:com.example.safari",
            "closing it returns to the stack's own tile")

        board.select(0)
        board.expandSelection()
        expect(board.selection == 1, "the front app's stack opens past the current window")
        board.cycleMode()
        expect(
            board.expandedStack == nil && board.isStacked,
            "left Shift inside a stack steps back out rather than unstacking")
    }

    static func togglingKeepsTheWindow() {
        var board = WindowPickerBoard(entries: desk, mode: .windows)
        board.select(4)
        board.cycleMode()
        expect(
            board.isStacked && board.selectedTile?.id == "stack:com.example.safari",
            "stacking selects the stack holding the selected window")
        board.cycleMode()
        expect(
            board.mode == .groups && board.target?.handle == 1,
            "a second press moves on to groups, still on that stack's frontmost window")
        board.cycleMode()
        expect(board.mode == .windows && board.target?.handle == 1, "and a third comes back round")
    }

    static func frontAppBoard() {
        let finder = desk.filter { $0.appName == "Finder" }
        var board = WindowPickerBoard(entries: finder, mode: .stacks, allowsStacking: false)
        expect(!board.isStacked && board.tiles.count == 3, "one app's windows never stack")
        board.cycleMode()
        expect(!board.isStacked, "and the toggle is inert there")
    }

    static func removal() {
        var board = WindowPickerBoard(entries: desk, mode: .stacks)
        board.toggleStack()
        board.remove(handles: [1, 4])
        expect(board.expandedStack == nil, "an open stack whose app quit closes")
        expect(
            board.tiles.map(\.id) == ["stack:com.example.finder", "window:3"],
            "and its tile leaves the board")
        var flat = WindowPickerBoard(entries: desk, mode: .windows)
        flat.select(5)
        flat.remove(handles: [5])
        expect(flat.selection == 4, "removing the last selected tile clamps the selection")
        flat.select(2)
        flat.remove(handles: [0])
        expect(flat.target?.handle == 2, "removing an earlier tile keeps the selected window")
    }

    /// Finder and Mail are "Productivity", Safari a "Browser": two outlines to start from.
    static let kinds = [
        0: "Productivity", 1: "Browser", 2: "Productivity", 3: "Productivity", 4: "Browser",
        5: "Productivity"
    ]

    static func groupsBoard() {
        typealias Group = WindowPickerBoard.Group
        var board = WindowPickerBoard(entries: desk, mode: .groups, appTypes: kinds)
        func handles() -> [Int] { board.tiles.compactMap { $0.target?.handle } }
        expect(
            board.sections.map(\.group) == [.appType("Productivity"), .appType("Browser")],
            "windows gather by kind of app, in the order each kind first appears")
        expect(board.sections.map(\.count) == [4, 2] && handles() == [0, 2, 3, 5, 1, 4], "kind by kind")
        expect(board.target?.handle == 1, "and it still opens on the window behind the current one")
        expect(!board.canExpandSelection, "groups hold windows, never stacks")

        board.drop(tileAt: 4, on: .tile(2))
        expect(
            board.sections.map(\.group) == [.appType("Productivity"), .custom(1), .appType("Browser")],
            "dropping one window on another starts a group of the two: \(board.sections)")
        expect(board.customGroups == [1: 1, 3: 1] && board.target?.handle == 1, "selecting the moved one")
        board.drop(tileAt: 0, on: .tile(board.tiles.firstIndex { $0.target?.handle == 3 } ?? -1))
        expect(board.customGroups == [0: 1, 1: 1, 3: 1], "dropping on a grouped window joins its group")
        let custom = board.sections.firstIndex { $0.group == .custom(1) } ?? -1
        board.drop(tileAt: board.tiles.firstIndex { $0.target?.handle == 5 } ?? -1, on: .section(custom))
        expect(board.customGroups[5] == 1, "as does dropping on the group's own outline")

        let kind = board.sections.firstIndex { $0.group == .appType("Productivity") } ?? -1
        board.drop(tileAt: board.tiles.firstIndex { $0.target?.handle == 5 } ?? -1, on: .section(kind))
        expect(board.customGroups[5] == nil, "an app-type outline sends a window back to its kind")
        board.remove(handles: [0, 3])
        expect(
            board.customGroups.isEmpty && !board.sections.contains { $0.group == .custom(1) },
            "a group left with one window dissolves")

        board.drop(tileAt: 0, on: .tile(0))
        expect(board.customGroups.isEmpty, "a window dropped on itself changes nothing")
        var flat = WindowPickerBoard(entries: desk, mode: .windows)
        flat.drop(tileAt: 0, on: .tile(1))
        expect(flat.customGroups.isEmpty, "and nothing regroups outside groups mode")

        var seeded = WindowPickerBoard(
            entries: desk, mode: .groups, appTypes: kinds, customGroups: [1: 7, 3: 7, 5: 9])
        expect(seeded.customGroups == [1: 7, 3: 7], "remembered groups return, minus the lone ones")
        seeded.type("saf")
        expect(
            seeded.tiles.compactMap { $0.target?.handle } == [0, 2, 5, 1, 3, 4] && seeded.target?.handle == 1,
            "a search leaves groups where they are and selects the first match")
        expect(
            WindowPickerBoard(entries: desk, mode: .groups, allowsStacking: false).mode == .windows,
            "one app's windows are never grouped")
    }

    static func searching() {
        var board = WindowPickerBoard(entries: desk, mode: .windows)
        func handles() -> [Int] { board.tiles.compactMap { $0.target?.handle } }
        board.type("s")
        board.type("a")
        expect(board.tiles.count == desk.count, "a search never removes a tile")
        expect(handles() == [1, 4, 0, 2, 3, 5] && board.selection == 0, "it brings the matches first")
        expect(board.unmatched == [0, 2, 3, 5], "and marks the rest to be dimmed")
        board.type("x")
        expect(handles() == [0, 1, 2, 3, 4, 5], "a query matching nothing leaves the order alone")
        expect(board.tiles.allSatisfy(board.isDimmed), "with every tile dimmed")
        board.deleteBackward()
        expect(handles().prefix(2) == [1, 4], "⌫ brings the matches back")
        expect(board.stepBack() && board.query.isEmpty, "Escape clears the search first")
        expect(handles() == [0, 1, 2, 3, 4, 5] && board.unmatched.isEmpty, "restoring the board")
        expect(!board.stepBack(), "and with nothing open Escape leaves the picker")

        board.type(" ")
        expect(board.query.isEmpty, "a leading space starts no search")
        board.type("WINDOW 3")
        expect(board.target?.handle == 3, "titles match, whatever the case")
        _ = board.stepBack()
        board.type("m")
        expect(board.target?.appName == "Mail", "an app-name prefix leads")

        var stacked = WindowPickerBoard(entries: desk, mode: .stacks)
        stacked.type("fi")
        expect(
            stacked.tiles.count == 3 && stacked.selectedTile?.id == "stack:com.example.finder",
            "stacked, a search lands on the app's stack")
        expect(
            stacked.tiles.filter(stacked.isDimmed).count == 2, "and dims the stacks that hold no match")
        stacked.expandSelection()
        expect(stacked.tiles.count == 3 && stacked.showsHeader, "which opens as usual")
        expect(stacked.stepBack() && stacked.expandedStack != nil, "Escape drops the search first")
        expect(stacked.stepBack() && stacked.expandedStack == nil, "then steps out of the stack")
        expect(
            stacked.canExpandSelection && !stacked.canAutoExpandSelection,
            "a stack just left opens by hand but not by itself")
        stacked.step(by: 1)
        stacked.step(by: -1)
        expect(stacked.canAutoExpandSelection, "until the selection has been somewhere else")
        expect(!stacked.stepBack(), "then leaves")
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
            "an open stack's header adds its own height")

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
        let grouped = WindowPickerGeometry.groupLayout(sectionSizes: [4, 2, 1], screen: screen)
        expect(
            grouped.tileFrames.count == 7 && grouped.sectionFrames.count == 3,
            "groups lay out a frame per tile and per outline")
        expect(
            zip(grouped.sectionFrames, [0..<4, 4..<6, 6..<7]).allSatisfy { box, tiles in
                tiles.allSatisfy { box.contains(grouped.tileFrames[$0]) }
            }, "every tile sits inside its own outline")
        expect(
            !grouped.sectionFrames[0].intersects(grouped.sectionFrames[1]), "and outlines never overlap")
        expect(
            grouped.sectionFrames[0].width < grouped.tile.width * 3,
            "four windows sit two by two rather than in a ribbon")
        let crowded = WindowPickerGeometry.groupLayout(
            sectionSizes: Array(repeating: 6, count: 8), screen: screen)
        expect(
            crowded.panel.width <= screen.width && crowded.panel.height <= screen.height,
            "a crowded board wraps and shrinks to stay on screen: \(crowded.panel)")
        let frames = grouped.tileFrames
        expect(WindowPickerGeometry.neighbor(of: 0, .right, in: frames) == 1, "→ goes to the next tile")
        expect(WindowPickerGeometry.neighbor(of: 0, .down, in: frames) == 2, "↓ to the one below")
        expect(WindowPickerGeometry.neighbor(of: 1, .right, in: frames) == 4, "→ crosses into the next box")
        expect(WindowPickerGeometry.neighbor(of: 0, .left, in: frames) == nil, "and stops at the edge")

        expect(
            laid(3, Limits(tileScale: 1.35)).preview.width > few.preview.width
                && laid(3, Limits(tileScale: 0.75)).preview.width < few.preview.width,
            "the window size scales the tiles")
    }
}
