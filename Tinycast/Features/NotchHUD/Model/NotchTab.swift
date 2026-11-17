import Foundation

/// Active page inside the expanded Notch tray.
enum NotchTab: String, CaseIterable, Codable, Sendable {
    case home
    case shelf
    case terminal
}
