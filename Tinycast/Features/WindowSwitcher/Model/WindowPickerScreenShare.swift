import Foundation

/// The most of the screen's width or height the switcher's panel may take, in percent.
enum WindowPickerScreenShare: Int, CaseIterable, Identifiable, Sendable {
    case forty = 40
    case fifty = 50
    case sixty = 60
    case seventy = 70
    case eighty = 80
    case ninety = 90
    case full = 100

    var id: Int { rawValue }

    var fraction: Double { Double(rawValue) / 100 }

    var title: String { String(localized: "\(rawValue)%") }
}
