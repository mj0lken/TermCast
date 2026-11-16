import Foundation

/// Decodes `NSSystemDefined` subtype-8 media key events without importing AppKit.
struct MediaKeyEvent: Sendable, Equatable {
    enum Key: Int32, Sendable, Equatable {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case illuminationUp = 21
        case illuminationDown = 22
    }

    enum Phase: Sendable, Equatable {
        case down
        case up
    }

    static let auxControlSubtype: Int16 = 8

    let key: Key
    let phase: Phase
    let isRepeat: Bool
    let isFineStep: Bool

    static func decode(
        subtype: Int16,
        data1: Int,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false,
        command: Bool = false
    ) -> MediaKeyEvent? {
        guard subtype == auxControlSubtype else { return nil }
        // Bare Option opens Sound or Displays in System Settings on macOS, so let the OS handle it.
        guard !(option && !shift && !control && !command) else { return nil }
        guard !control, !command else { return nil }

        let keyCode = Int32((data1 & 0xFFFF_0000) >> 16)
        guard let key = Key(rawValue: keyCode) else { return nil }

        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let phase: Phase
        switch keyState {
        case 0x0A:
            phase = .down
        case 0x0B:
            phase = .up
        default:
            return nil
        }

        let isRepeat = (keyFlags & 0x0001) != 0
        let isFineStep = shift && option
        return MediaKeyEvent(
            key: key,
            phase: phase,
            isRepeat: isRepeat,
            isFineStep: isFineStep)
    }
}
