import Foundation

/// A button the user can place in the open notch's header, beside the notch.
enum NotchShortcut: String, CaseIterable, Sendable {
    case clipboard
    case notebook
    case camera
    case windowManagement
    case timer
    case snippets
    case emoji
    case settings
    /// An empty place kept between shortcuts in a stored list; never drawn or offered.
    case gap

    static let choices = allCases.filter { $0 != .gap }

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
        let placed = shortcuts.filter { $0 != .gap }
        return shortcuts.count <= limit(showsBattery: false) && Set(placed).count == placed.count
    }

    /// Everything the trailing half has room for: the row plus the shortcuts kept beside the cutout.
    static func slots(showsBattery: Bool) -> Int {
        showsBattery ? 4 : 6
    }

    var symbol: String {
        switch self {
        case .clipboard: "paperclip"
        case .notebook: "text.book.closed"
        case .camera: "web.camera"
        case .windowManagement: "rectangle.split.2x1"
        case .timer: "timer"
        case .snippets: "text.quote"
        case .emoji: "face.smiling"
        case .settings: "gearshape"
        case .gap: ""
        }
    }

    var title: String {
        switch self {
        case .clipboard: String(localized: "Clipboard History")
        case .notebook: String(localized: "Notebook")
        case .camera: String(localized: "Camera Mirror")
        case .windowManagement: String(localized: "Window Management")
        case .timer: String(localized: "Timer")
        case .snippets: String(localized: "Snippets")
        case .emoji: String(localized: "Emoji & Symbols")
        case .settings: String(localized: "Notch Settings")
        case .gap: ""
        }
    }
}
