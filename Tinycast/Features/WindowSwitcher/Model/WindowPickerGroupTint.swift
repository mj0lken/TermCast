import Foundation

/// The faint shade behind a group's outline. Automatic deals the palette out by position.
enum WindowPickerGroupTint: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic, red, orange, yellow, green, mint, teal, blue, purple, pink, gray

    var id: String { rawValue }

    /// Gray stays a deliberate choice: dealt out, it would read as a group with no shade at all.
    static let palette: [WindowPickerGroupTint] = [
        .blue, .green, .orange, .purple, .teal, .pink, .yellow, .mint, .red
    ]

    /// Full system colours shout behind thumbnails; this much keeps them apart without that.
    static let saturation = 0.55

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .mint: String(localized: "Mint")
        case .teal: String(localized: "Teal")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .gray: String(localized: "Gray")
        }
    }
}
