import Foundation

/// How long a selected stack waits before it opens by itself. Zero never opens one.
enum WindowPickerStackDelay: Int, CaseIterable, Identifiable, Sendable {
    case never = 0
    case short = 400
    case medium = 700
    case long = 1000
    case longest = 1500

    var id: Int { rawValue }

    var duration: Duration? { self == .never ? nil : .milliseconds(rawValue) }

    var title: String {
        self == .never ? String(localized: "Never") : String(localized: "\(rawValue) ms")
    }
}
