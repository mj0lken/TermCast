import AppKit
import Carbon.HIToolbox

enum TerminalKeyEventBridge {
    @MainActor
    static func chord(from event: NSEvent) -> TerminalKeyChord? {
        guard let key = resolveKey(from: event) else { return nil }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return TerminalKeyChord(
            key: key,
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift))
    }

    @MainActor
    static var hyperIncludesShift: Bool? {
        guard let hyper = KeyShortcut.displayedHyperChord() else { return nil }
        return hyper.contains(.shift)
    }

    @MainActor
    static func displayString(for chord: TerminalKeyChord?) -> String? {
        chord?.inlineDisplay(hyperIncludesShift: hyperIncludesShift)
    }

    @MainActor
    static func keycaps(for chord: TerminalKeyChord) -> [String] {
        chord.keycaps(hyperIncludesShift: hyperIncludesShift)
    }

    @MainActor
    private static func resolveKey(from event: NSEvent) -> TerminalKeyChord.Key? {
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: return .returnKey
        case kVK_Tab: return .tab
        case kVK_Delete: return .delete
        case kVK_ForwardDelete: return .forwardDelete
        case kVK_Space: return .space
        case kVK_UpArrow: return .upArrow
        case kVK_DownArrow: return .downArrow
        case kVK_LeftArrow: return .leftArrow
        case kVK_RightArrow: return .rightArrow
        case kVK_Escape: return nil
        default:
            if let fnNumber = functionKeyMap[Int(event.keyCode)] {
                return .function(fnNumber)
            }
            let raw =
                ASCIIKeyboardLayout.character(for: event)?.lowercased()
                ?? event.charactersIgnoringModifiers?.lowercased()
            guard let raw, raw.count == 1 else { return nil }
            return .character(raw)
        }
    }

    private static let functionKeyMap: [Int: Int] = [
        kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5,
        kVK_F6: 6, kVK_F7: 7, kVK_F8: 8, kVK_F9: 9, kVK_F10: 10,
        kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15,
        kVK_F16: 16, kVK_F17: 17, kVK_F18: 18, kVK_F19: 19, kVK_F20: 20
    ]
}
