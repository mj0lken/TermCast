import Foundation

/// The countdown lengths the notch offers.
enum NotchTimerPreset {
    static let minutes = [5, 10, 25, 45]

    static func end(afterMinutes minutes: Int, from now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(max(minutes, 1) * 60))
    }
}
