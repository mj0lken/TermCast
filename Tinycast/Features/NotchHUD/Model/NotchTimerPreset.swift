import Foundation

/// The countdown lengths the notch offers.
enum NotchTimerPreset {
    static let minutes = [5, 10, 25, 45]

    /// A custom length runs from a minute to a day.
    static let customRange = 1...1440

    static var customLengthHint: String { String(localized: "Enter a length from 1 to 1440 minutes.") }

    /// A typed length in whole minutes, or nil when it is not a number in `customRange`.
    static func minutes(from text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { customRange.contains($0) ? $0 : nil }
    }

    static func end(afterMinutes minutes: Int, from now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(max(minutes, 1) * 60))
    }
}
