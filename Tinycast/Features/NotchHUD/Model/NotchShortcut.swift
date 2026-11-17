import Foundation

/// A button the user can place in the open notch's header, beside the notch.
enum NotchShortcut: String, CaseIterable, Sendable {
    case clipboard
    case notebook
    case camera
    case windowManagement
    case timer
    case settings

    static let defaults: [NotchShortcut] = [.clipboard, .notebook, .camera, .settings]

    /// The header's trailing half has to hold the row and, when shown, the battery readout.
    static func limit(showsBattery: Bool) -> Int {
        showsBattery ? 4 : 5
    }

    /// Unknown names and repeats make the whole list invalid, so a bad edit changes nothing.
    static func shortcuts(from identifiers: [String]) -> [NotchShortcut]? {
        let shortcuts = identifiers.compactMap(NotchShortcut.init(rawValue:))
        return shortcuts.count == identifiers.count && isValid(shortcuts) ? shortcuts : nil
    }

    static func isValid(_ shortcuts: [NotchShortcut]) -> Bool {
        shortcuts.count <= limit(showsBattery: false) && Set(shortcuts).count == shortcuts.count
    }

    /// What the header draws: the configured row, minus what is unavailable, cut to what fits.
    static func visible(
        _ shortcuts: [NotchShortcut], showsBattery: Bool, isAvailable: (NotchShortcut) -> Bool
    ) -> [NotchShortcut] {
        Array(shortcuts.filter(isAvailable).prefix(limit(showsBattery: showsBattery)))
    }

    var symbol: String {
        switch self {
        case .clipboard: "paperclip"
        case .notebook: "text.book.closed"
        case .camera: "web.camera"
        case .windowManagement: "rectangle.split.2x1"
        case .timer: "timer"
        case .settings: "gearshape"
        }
    }

    var title: String {
        switch self {
        case .clipboard: String(localized: "Clipboard History")
        case .notebook: String(localized: "Notebook")
        case .camera: String(localized: "Camera Mirror")
        case .windowManagement: String(localized: "Window Management")
        case .timer: String(localized: "Timer")
        case .settings: String(localized: "Notch Settings")
        }
    }
}
