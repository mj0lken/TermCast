import Foundation

/// Turns raw key events into picker commands. Pure, so the tap thread only feeds and forwards.
struct WindowPickerKeyEngine: Sendable {
    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: UInt8
        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)
    }

    enum Scope: Sendable { case allWindows, frontApp }

    enum Direction: Sendable { case left, right, up, down }

    enum Action: Hashable, Sendable { case close, quit, hide }

    enum Command: Equatable, Sendable {
        case open(Scope, backwards: Bool)
        case step(Int)
        case move(Direction)
        case cycleMode
        case toggleStack
        case pick(Int)
        case type(String)
        case deleteBackward
        case perform(Action)
        case commit
        /// Escape: the coordinator knows whether that leaves a search, a stack or the picker.
        case back
    }

    struct Trigger: Equatable, Sendable {
        let scope: Scope
        let modifier: Modifiers
        let keyCode: UInt16
    }

    struct Outcome: Equatable, Sendable {
        var command: Command?
        var swallows: Bool

        static let passed = Outcome(command: nil, swallows: false)
    }

    enum KeyCode {
        static let tab: UInt16 = 48
        static let grave: UInt16 = 50
        static let escape: UInt16 = 53
        static let delete: UInt16 = 51
        static let space: UInt16 = 49
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let leftShift: UInt16 = 56
        static let rightShift: UInt16 = 60
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
        /// The digit row by position, so 1–9 hold on a layout that needs Shift to type them.
        static let digits: [UInt16: Int] = [
            18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8
        ]
        /// The ANSI positions, for a layout that cannot be read.
        static let defaultActions: [UInt16: Action] = [13: .close, 12: .quit, 4: .hide]
    }

    var triggers: [Trigger]
    var actionKeys: [UInt16: Action]
    /// The letters this layout types, by key; what a search is spelled with. Empty turns search off.
    var characters: [UInt16: String]
    private(set) var active: Trigger?
    /// A Shift that went down while open and has seen no key since: its release is a tap.
    private var pendingShiftTap: UInt16?

    init(
        triggers: [Trigger] = [], actionKeys: [UInt16: Action] = KeyCode.defaultActions,
        characters: [UInt16: String] = [:]
    ) {
        self.triggers = triggers
        self.actionKeys = actionKeys
        self.characters = characters
    }

    static func triggers(allWindows: WindowPickerChord, frontApp: WindowPickerChord) -> [Trigger] {
        [
            allWindows.modifier.map {
                Trigger(scope: .allWindows, modifier: $0, keyCode: KeyCode.tab)
            },
            frontApp.modifier.map {
                Trigger(scope: .frontApp, modifier: $0, keyCode: KeyCode.grave)
            }
        ].compactMap(\.self)
    }

    mutating func reset() {
        active = nil
        pendingShiftTap = nil
    }

    mutating func keyDown(_ keyCode: UInt16, modifiers: Modifiers) -> Outcome {
        guard let active else { return opening(keyCode, modifiers: modifiers) }
        pendingShiftTap = nil
        return Outcome(command: command(for: keyCode, modifiers: modifiers, in: active), swallows: true)
    }

    /// Modifier changes always travel on: swallowing one would strand it down in every other app.
    mutating func modifiersChanged(
        keyCode: UInt16, isDown: Bool, modifiers: Modifiers
    ) -> Command? {
        guard let active else { return nil }
        guard modifiers.contains(active.modifier) else {
            reset()
            return .commit
        }
        guard keyCode == KeyCode.leftShift || keyCode == KeyCode.rightShift else {
            pendingShiftTap = nil
            return nil
        }
        if isDown {
            pendingShiftTap = keyCode
            return nil
        }
        guard pendingShiftTap == keyCode else { return nil }
        pendingShiftTap = nil
        return keyCode == KeyCode.leftShift ? .cycleMode : .toggleStack
    }

    private mutating func opening(_ keyCode: UInt16, modifiers: Modifiers) -> Outcome {
        let held = modifiers.subtracting(.shift)
        guard let trigger = triggers.first(where: { $0.keyCode == keyCode && $0.modifier == held })
        else { return .passed }
        active = trigger
        pendingShiftTap = nil
        return Outcome(
            command: .open(trigger.scope, backwards: modifiers.contains(.shift)), swallows: true)
    }

    private mutating func command(
        for keyCode: UInt16, modifiers: Modifiers, in active: Trigger
    ) -> Command? {
        switch keyCode {
        case active.keyCode, KeyCode.tab: return .step(modifiers.contains(.shift) ? -1 : 1)
        case KeyCode.leftArrow: return .move(.left)
        case KeyCode.rightArrow: return .move(.right)
        case KeyCode.upArrow: return .move(.up)
        case KeyCode.downArrow: return .move(.down)
        case KeyCode.escape: return .back
        case KeyCode.returnKey, KeyCode.keypadEnter:
            reset()
            return .commit
        default:
            if let index = KeyCode.digits[keyCode] { return .pick(index) }
            guard !characters.isEmpty else { return actionKeys[keyCode].map(Command.perform) }
            // Searching, Shift marks an action so every bare letter is free to spell a query.
            if modifiers.contains(.shift), let action = actionKeys[keyCode] { return .perform(action) }
            if keyCode == KeyCode.delete { return .deleteBackward }
            if keyCode == KeyCode.space { return .type(" ") }
            return characters[keyCode].map(Command.type)
        }
    }
}
