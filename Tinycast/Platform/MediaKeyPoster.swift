import AppKit
import CoreGraphics

/// Posts HID media keys on an isolated event source so held hotkey modifiers never leak into them.
@MainActor
enum MediaKeyPoster {
    enum Key: Int32, Sendable {
        case soundUp = 0
        case soundDown = 1
        case mute = 7
        case playPause = 16
        case nextTrack = 17
        case previousTrack = 18
        case illuminationUp = 21
        case illuminationDown = 22
    }

    private static let source = CGEventSource(stateID: .privateState)

    static func post(_ key: Key, fineStep: Bool = false) {
        let nsModifiers: NSEvent.ModifierFlags = fineStep ? [.shift, .option] : []
        let cgFlags: CGEventFlags = fineStep ? [.maskShift, .maskAlternate] : []
        // 0xA is key-down and 0xB is key-up on NSSystemDefined subtype 8.
        for state in [Int32(0xA), Int32(0xB)] {
            let data1 = Int((key.rawValue << 16) | (state << 8))
            guard
                let event = NSEvent.otherEvent(
                    with: .systemDefined, location: .zero, modifierFlags: nsModifiers,
                    timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                    data1: data1, data2: -1),
                let cgEvent = event.cgEvent
            else { continue }
            cgEvent.setSource(source)
            cgEvent.flags = cgFlags
            cgEvent.post(tap: .cghidEventTap)
        }
    }
}
