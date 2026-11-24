import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Magnet-style Window Management submenu inside Tinycast's menu-bar item when enabled.
struct WindowManagementMenu: View {
    private static let sections: [[WindowCommand.ID]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter],
        [.firstThird, .centerThird, .lastThird],
        [.firstTwoThirds, .centerTwoThirds, .lastTwoThirds, .firstThreeFourths, .lastThreeFourths],
        [
            .topThird, .middleThird, .bottomThird, .topTwoThirds, .middleTwoThirds,
            .bottomTwoThirds
        ],
        [.nextDisplay, .previousDisplay],
        [.maximize, .almostMaximize, .reasonableSize, .center, .restore]
    ]

    var body: some View {
        let core = AppCore.shared
        @Bindable var settings = core.settings
        let hotKeys = core.hotKeys

        Menu {
            Toggle(isOn: $settings.windowSnapByDragging) {
                Label("Snap windows by dragging", systemImage: "cursorarrow.motionlines")
            }

            Divider()

            ForEach(Array(Self.sections.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group, id: \.self) { id in
                    if let command = WindowCommandCatalog.command(id: id) {
                        menuButton(
                            title: command.name,
                            binding: hotKeys.binding(for: .windowCommand(id: id)),
                            icon: { WindowCommandIcon(command: command) }
                        ) {
                            core.windowCommandCoordinator.runWindowCommand(id: id)
                        }
                    }
                }
            }

            let sizes = core.customWindowSizes.sizes
            if !sizes.isEmpty {
                Divider()
                ForEach(sizes) { size in
                    menuButton(
                        title: size.name,
                        binding: hotKeys.binding(for: .customWindowSize(id: size.id)),
                        icon: { WindowCommandIcon(size: size) }
                    ) {
                        core.windowCommandCoordinator.runCustomWindowSize(id: size.id)
                    }
                }
            }

            let layouts = core.windowLayouts.layouts
            if !layouts.isEmpty {
                Divider()
                ForEach(layouts) { layout in
                    menuButton(
                        title: layout.name,
                        binding: hotKeys.binding(for: .windowLayout(id: layout.id)),
                        icon: { Image(systemName: layout.symbol) }
                    ) {
                        core.windowLayoutCoordinator.runWindowLayout(id: layout.id)
                    }
                }
            }

            let rooms = core.rooms.rooms
            if !rooms.isEmpty {
                Divider()
                ForEach(rooms) { room in
                    menuButton(
                        title: room.name,
                        binding: hotKeys.binding(for: .windowRoom(id: room.id)),
                        icon: { Image(systemName: Room.sfSymbol) }
                    ) {
                        core.roomCoordinator.enterRoom(id: room.id)
                    }
                }
            }

            Divider()
            Button {
                core.settingsCoordinator.showSettings(tab: .windowManagement)
            } label: {
                Label("Window Management Settings…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Text("Window Management")
        }
    }

    @ViewBuilder
    private func menuButton<Icon: View>(
        title: String, binding: HotKeyBinding?, @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Label {
                Text(verbatim: title)
            } icon: {
                icon()
            }
        }
        if case .combo(let shortcut) = binding, let equivalent = shortcut.menuKeyboardShortcut {
            button.keyboardShortcut(equivalent.key, modifiers: equivalent.modifiers)
        } else {
            button
        }
    }
}

extension KeyShortcut {
    /// Converts a Carbon combo into SwiftUI's menu key equivalent; nil for Globe-modified chords.
    @MainActor fileprivate var menuKeyboardShortcut:
        (key: KeyEquivalent, modifiers: SwiftUI.EventModifiers)?
    {
        let flags = modifierFlags
        guard !flags.contains(.function), let key = menuKeyEquivalent else {
            return nil
        }
        var modifiers: SwiftUI.EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return (key, modifiers)
    }

    @MainActor private var menuKeyEquivalent: KeyEquivalent? {
        switch carbonKeyCode {
        case kVK_LeftArrow: return .leftArrow
        case kVK_RightArrow: return .rightArrow
        case kVK_UpArrow: return .upArrow
        case kVK_DownArrow: return .downArrow
        case kVK_Return, kVK_ANSI_KeypadEnter: return .return
        case kVK_Tab: return .tab
        case kVK_Space: return .space
        case kVK_Delete: return .delete
        case kVK_ForwardDelete: return .deleteForward
        case kVK_Escape: return .escape
        case kVK_Home: return .home
        case kVK_End: return .end
        case kVK_PageUp: return .pageUp
        case kVK_PageDown: return .pageDown
        default:
            if let functionScalar = Self.functionKeyScalars[carbonKeyCode],
                let scalar = UnicodeScalar(functionScalar)
            {
                return KeyEquivalent(Character(scalar))
            }
            guard let char = ASCIIKeyboardLayout.character(for: carbonKeyCode)?.lowercased().first
            else { return nil }
            return KeyEquivalent(char)
        }
    }

    private static let functionKeyScalars: [Int: Int] = [
        kVK_F1: NSF1FunctionKey, kVK_F2: NSF2FunctionKey, kVK_F3: NSF3FunctionKey,
        kVK_F4: NSF4FunctionKey, kVK_F5: NSF5FunctionKey, kVK_F6: NSF6FunctionKey,
        kVK_F7: NSF7FunctionKey, kVK_F8: NSF8FunctionKey, kVK_F9: NSF9FunctionKey,
        kVK_F10: NSF10FunctionKey, kVK_F11: NSF11FunctionKey, kVK_F12: NSF12FunctionKey,
        kVK_F13: NSF13FunctionKey, kVK_F14: NSF14FunctionKey, kVK_F15: NSF15FunctionKey,
        kVK_F16: NSF16FunctionKey, kVK_F17: NSF17FunctionKey, kVK_F18: NSF18FunctionKey,
        kVK_F19: NSF19FunctionKey, kVK_F20: NSF20FunctionKey
    ]
}
