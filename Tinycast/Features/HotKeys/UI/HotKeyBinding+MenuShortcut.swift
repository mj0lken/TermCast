import Carbon.HIToolbox
import SwiftUI

extension HotKeyBinding {
    /// The chord as a menu key equivalent, so a native menu draws it; nil when a menu cannot spell it.
    @MainActor var menuShortcut: KeyboardShortcut? {
        guard case .combo(let shortcut) = self else { return nil }
        let flags = shortcut.modifierFlags
        guard !flags.contains(.function), let key = Self.menuKey(for: shortcut.carbonKeyCode) else { return nil }
        let pairs: [(NSEvent.ModifierFlags, SwiftUI.EventModifiers)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command)
        ]
        let modifiers = pairs.reduce(into: SwiftUI.EventModifiers()) { result, pair in
            if flags.contains(pair.0) { result.insert(pair.1) }
        }
        return KeyboardShortcut(key, modifiers: modifiers)
    }

    @MainActor private static func menuKey(for keyCode: Int) -> KeyEquivalent? {
        if let named = namedKeys[keyCode] { return named }
        if let index = functionKeys.firstIndex(of: keyCode),
            let scalar = Unicode.Scalar(UInt32(NSF1FunctionKey + index))
        {
            return KeyEquivalent(Character(scalar))
        }
        return ASCIIKeyboardLayout.character(for: keyCode)?.lowercased().first.map { KeyEquivalent($0) }
    }

    private static let namedKeys: [Int: KeyEquivalent] = [
        kVK_Return: .return, kVK_Tab: .tab, kVK_Space: .space, kVK_Delete: .delete,
        kVK_ForwardDelete: .deleteForward, kVK_Escape: .escape,
        kVK_LeftArrow: .leftArrow, kVK_RightArrow: .rightArrow, kVK_UpArrow: .upArrow,
        kVK_DownArrow: .downArrow, kVK_Home: .home, kVK_End: .end, kVK_PageUp: .pageUp,
        kVK_PageDown: .pageDown
    ]

    /// In F1…F20 order, which is the order AppKit's function-key characters run in.
    private static let functionKeys = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]
}
