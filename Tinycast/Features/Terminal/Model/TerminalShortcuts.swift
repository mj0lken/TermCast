import Foundation

enum TerminalShortcutAction: String, CaseIterable, Codable, Sendable {
    case toggleTerminalMode
    case switchToTerminal
    case copyLastOutput
    case openExternalTerminal
    case runInTerminal
    case cycleFolder
    case newTab
    case closeTab
    case stopCommand
    case clearOutput

    var worksInLauncher: Bool {
        switch self {
        case .toggleTerminalMode, .switchToTerminal, .openExternalTerminal, .runInTerminal,
            .cycleFolder:
            true
        case .copyLastOutput, .newTab, .closeTab, .stopCommand, .clearOutput:
            false
        }
    }

    var defaultChord: TerminalKeyChord {
        switch self {
        case .toggleTerminalMode: TerminalKeyChord(key: .character("t"), command: true)
        case .switchToTerminal: TerminalKeyChord(key: .character("i"), command: true)
        case .copyLastOutput: TerminalKeyChord(key: .character("c"), command: true, shift: true)
        case .openExternalTerminal: TerminalKeyChord(key: .character("o"), command: true)
        case .runInTerminal: TerminalKeyChord(key: .returnKey, shift: true)
        case .cycleFolder: TerminalKeyChord(key: .tab, shift: true)
        case .newTab: TerminalKeyChord(key: .character("n"), command: true)
        case .closeTab: TerminalKeyChord(key: .character("x"), control: true)
        case .stopCommand: TerminalKeyChord(key: .character("."), command: true)
        case .clearOutput: TerminalKeyChord(key: .delete, command: true)
        }
    }
}

struct TerminalKeyChord: Equatable, Hashable, Sendable {
    enum Key: Equatable, Hashable, Sendable {
        case character(String)
        case returnKey
        case tab
        case delete
        case forwardDelete
        case space
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
        case function(Int)
    }

    let key: Key
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    init(
        key: Key,
        command: Bool = false,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false
    ) {
        if case .character(let ch) = key {
            self.key = .character(ch.lowercased())
        } else {
            self.key = key
        }
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    var isValid: Bool {
        if isReservedChord { return false }
        let hasPrimaryModifier = command || option || control
        switch key {
        case .function(let number):
            return (1...20).contains(number)
        case .character(let text):
            guard text.count == 1,
                let scalar = text.unicodeScalars.first,
                scalar.value >= 0x21 && scalar.value <= 0x7E
            else { return false }
            return hasPrimaryModifier
        case .space, .delete, .forwardDelete:
            return hasPrimaryModifier
        case .returnKey, .tab, .upArrow, .downArrow, .leftArrow, .rightArrow:
            return hasPrimaryModifier || shift
        }
    }

    private var isReservedChord: Bool {
        if command && !option && !control && !shift, case .character(let ch) = key {
            let reserved: Set<String> = [
                "a", "c", "v", "x", "z", "k", "w", ",",
                "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"
            ]
            if reserved.contains(ch) { return true }
        }
        if command && !option && !control && shift, key == .character("z") { return true }
        if command && option && !control && !shift, key == .character(",") { return true }
        return false
    }

    var text: String {
        var parts: [String] = []
        if control { parts.append("ctrl") }
        if option { parts.append("opt") }
        if shift { parts.append("shift") }
        if command { parts.append("cmd") }
        parts.append(keyToken)
        return parts.joined(separator: "+")
    }

    private var keyToken: String {
        switch key {
        case .character("+"): "plus"
        case .character(let ch): ch
        case .returnKey: "return"
        case .tab: "tab"
        case .delete: "delete"
        case .forwardDelete: "forwarddelete"
        case .space: "space"
        case .upArrow: "up"
        case .downArrow: "down"
        case .leftArrow: "left"
        case .rightArrow: "right"
        case .function(let n): "f\(n)"
        }
    }

    init?(text: String) {
        let tokens = text.lowercased()
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = tokens.last, !last.isEmpty else { return nil }
        var command = false
        var option = false
        var control = false
        var shift = false
        for mod in tokens.dropLast() {
            switch mod {
            case "cmd", "command": command = true
            case "opt", "option", "alt": option = true
            case "ctrl", "control": control = true
            case "shift": shift = true
            default: return nil
            }
        }
        guard let parsedKey = Self.parseKeyToken(last) else { return nil }
        let candidate = TerminalKeyChord(
            key: parsedKey, command: command, option: option, control: control, shift: shift)
        guard candidate.isValid else { return nil }
        self = candidate
    }

    private static func parseKeyToken(_ token: String) -> Key? {
        switch token {
        case "return", "enter": return .returnKey
        case "tab": return .tab
        case "delete", "backspace": return .delete
        case "forwarddelete": return .forwardDelete
        case "space": return .space
        case "up": return .upArrow
        case "down": return .downArrow
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "plus": return .character("+")
        default:
            if token.hasPrefix("f"), token.count >= 2,
                let number = Int(token.dropFirst()), (1...20).contains(number)
            {
                return .function(number)
            }
            guard token.count == 1 else { return nil }
            return .character(token)
        }
    }

    func keycaps(hyperIncludesShift: Bool? = nil) -> [String] {
        var caps: [String] = []
        let matchesHyper =
            hyperIncludesShift.map { includesShift in
                control && option && command && (!includesShift || shift)
            } ?? false
        if matchesHyper, let hyperIncludesShift {
            caps.append("✦")
            if !hyperIncludesShift && shift { caps.append("⇧") }
        } else {
            if control { caps.append("⌃") }
            if option { caps.append("⌥") }
            if shift { caps.append("⇧") }
            if command { caps.append("⌘") }
        }
        caps.append(keyGlyph)
        return caps
    }

    func inlineDisplay(hyperIncludesShift: Bool? = nil) -> String {
        keycaps(hyperIncludesShift: hyperIncludesShift).joined()
    }

    var keyGlyph: String {
        switch key {
        case .character(let ch): ch.uppercased()
        case .returnKey: "↵"
        case .tab: "⇥"
        case .delete: "⌫"
        case .forwardDelete: "⌦"
        case .space: "Space"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .function(let n): "F\(n)"
        }
    }
}

extension TerminalKeyChord: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = TerminalKeyChord(text: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid TerminalKeyChord: \(raw)")
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

struct TerminalShortcuts: Equatable, Sendable {
    static let defaults = TerminalShortcuts()

    private var bindings: [TerminalShortcutAction: TerminalKeyChord?]

    init() {
        var initial: [TerminalShortcutAction: TerminalKeyChord?] = [:]
        for action in TerminalShortcutAction.allCases {
            initial[action] = .some(action.defaultChord)
        }
        self.bindings = initial
    }

    init?(bindings: [TerminalShortcutAction: TerminalKeyChord?]) {
        var resolved: [TerminalShortcutAction: TerminalKeyChord?] = [:]
        var used: Set<TerminalKeyChord> = []
        for action in TerminalShortcutAction.allCases {
            guard let explicit = bindings[action] else { continue }
            if let chord = explicit {
                guard chord.isValid, used.insert(chord).inserted else { return nil }
            }
            resolved[action] = .some(explicit)
        }
        for action in TerminalShortcutAction.allCases where bindings[action] == nil {
            let fallback = action.defaultChord
            if fallback.isValid, used.insert(fallback).inserted {
                resolved[action] = .some(fallback)
            } else {
                resolved[action] = .some(nil)
            }
        }
        self.bindings = resolved
    }

    var isDefault: Bool { self == .defaults }

    func chord(for action: TerminalShortcutAction) -> TerminalKeyChord? {
        bindings[action] ?? action.defaultChord
    }

    func conflict(
        for chord: TerminalKeyChord, excluding action: TerminalShortcutAction
    ) -> TerminalShortcutAction? {
        TerminalShortcutAction.allCases.first { other in
            other != action && self.chord(for: other) == chord
        }
    }

    func setting(_ chord: TerminalKeyChord?, for action: TerminalShortcutAction) -> TerminalShortcuts {
        if let chord {
            guard chord.isValid, conflict(for: chord, excluding: action) == nil else { return self }
        }
        var copy = self
        copy.bindings[action] = .some(chord)
        return copy
    }

    func matchedAction(for chord: TerminalKeyChord, inLauncher: Bool) -> TerminalShortcutAction? {
        TerminalShortcutAction.allCases.first { action in
            (!inLauncher || action.worksInLauncher) && self.chord(for: action) == chord
        }
    }
}

extension TerminalShortcuts: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: String?].self)
        var parsed: [TerminalShortcutAction: TerminalKeyChord?] = [:]
        for action in TerminalShortcutAction.allCases {
            if let entry = raw[action.rawValue] {
                if let text = entry {
                    guard let chord = TerminalKeyChord(text: text) else {
                        throw DecodingError.dataCorruptedError(
                            in: container, debugDescription: "Invalid shortcut for \(action)")
                    }
                    parsed[action] = .some(chord)
                } else {
                    parsed[action] = .some(nil)
                }
            }
        }
        guard let shortcuts = TerminalShortcuts(bindings: parsed) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Conflicting terminal shortcuts")
        }
        self = shortcuts
    }

    func encode(to encoder: Encoder) throws {
        var raw: [String: String?] = [:]
        for action in TerminalShortcutAction.allCases {
            raw[action.rawValue] = .some(chord(for: action)?.text)
        }
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}
