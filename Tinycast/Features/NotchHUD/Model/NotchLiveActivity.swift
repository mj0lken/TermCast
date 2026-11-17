import CoreGraphics
import Foundation

/// The one ongoing thing the closed notch shows on its wings.
enum NotchLiveActivity: Sendable, Equatable {
    case dictation
    case meeting(MeetingEvent)
    case timer(end: Date)
    case nowPlaying

    var symbol: String {
        switch self {
        case .dictation: "mic.fill"
        case .meeting: "calendar"
        case .timer: "timer"
        case .nowPlaying: "music.note"
        }
    }

    var readoutWidth: CGFloat {
        switch self {
        case .dictation: 38
        case .meeting: 46
        case .timer: 50
        case .nowPlaying: 30
        }
    }
}

/// Microphone and camera use by other apps, drawn as a dot beside whatever else is showing.
struct NotchCaptureUse: Sendable, Equatable {
    var microphone = false
    var camera = false

    var isActive: Bool { microphone || camera }
}

struct NotchLivePresentation: Sendable, Equatable {
    static let glyphWidth: CGFloat = 30
    /// The terminal glyph and its count, kept together on the leading wing.
    static let terminalWidth: CGFloat = 42
    static let captureDotWidth: CGFloat = 16

    let activity: NotchLiveActivity?
    /// Running terminal sessions; they never compete for the wings, they sit beside the activity.
    let terminalCount: Int
    let capture: NotchCaptureUse

    var isEmpty: Bool { activity == nil && terminalCount == 0 && !capture.isActive }

    var leftWingWidth: CGFloat {
        (terminalCount > 0 ? Self.terminalWidth : 0) + (activity == nil ? 0 : Self.glyphWidth)
    }

    var rightWingWidth: CGFloat {
        (activity?.readoutWidth ?? 0) + (capture.isActive ? Self.captureDotWidth : 0)
    }
}

struct NotchLiveInputs: Sendable, Equatable {
    var isDictating = false
    var meeting: MeetingEvent?
    var timerEnd: Date?
    var runningTerminalCount = 0
    var isPlaying = false
    var capture = NotchCaptureUse()

    /// What the user is doing right now outranks what is scheduled, which outranks what is ambient.
    func presentation(at now: Date) -> NotchLivePresentation {
        NotchLivePresentation(
            activity: activity(at: now),
            terminalCount: max(runningTerminalCount, 0),
            capture: capture)
    }

    private func activity(at now: Date) -> NotchLiveActivity? {
        if isDictating { return .dictation }
        if let meeting { return .meeting(meeting) }
        if let timerEnd, timerEnd > now { return .timer(end: timerEnd) }
        if isPlaying { return .nowPlaying }
        return nil
    }
}
