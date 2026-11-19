import Foundation

/// The most tiles the grid puts in one row, or the most rows. Zero leaves it to the screen.
enum WindowPickerGridLimit: Int, CaseIterable, Identifiable, Sendable {
    case automatic = 0
    case one, two, three, four, five, six, seven, eight

    var id: Int { rawValue }

    var title: String {
        self == .automatic ? String(localized: "Automatic") : String(rawValue)
    }
}
