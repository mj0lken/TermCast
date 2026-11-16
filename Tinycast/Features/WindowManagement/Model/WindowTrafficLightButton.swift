import Foundation

/// Which window traffic-light button triggers Tinycast's hover tiling menu.
enum WindowTrafficLightButton: String, CaseIterable, Identifiable, Sendable {
    static let hoverDelayRange = 50...1000
    static let defaultHoverDelay = 150

    static func sanitizedHoverDelay(_ ms: Int) -> Int {
        min(max(ms, hoverDelayRange.lowerBound), hoverDelayRange.upperBound)
    }

    case green
    case yellow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green: String(localized: "Green (Zoom)")
        case .yellow: String(localized: "Yellow (Minimize)")
        }
    }
}
