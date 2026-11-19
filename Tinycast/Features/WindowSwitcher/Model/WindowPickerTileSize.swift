import Foundation

/// How large a window's tile starts out, before a crowded board shrinks it.
enum WindowPickerTileSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: String { rawValue }

    var scale: Double {
        switch self {
        case .small: 0.75
        case .medium: 1
        case .large: 1.35
        }
    }

    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}
