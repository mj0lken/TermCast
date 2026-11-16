import CoreGraphics
import Foundation

/// The one ongoing thing the closed notch shows on its wings.
enum NotchLiveActivity: Sendable, Equatable {
    case dictation
    case meeting(MeetingEvent)
    case timer(end: Date)
    case terminal(runningCount: Int)
    case nowPlaying

    var symbol: String {
        switch self {
        case .dictation: "mic.fill"
        case .meeting: "calendar"
        case .timer: "timer"
        case .terminal: "apple.terminal"
        case .nowPlaying: "music.note"
        }
    }

    var readoutWidth: CGFloat {
        switch self {
        case .dictation: 38
        case .meeting: 46
        case .timer: 50
        case .terminal: 30
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
    static let terminalBadgeWidth: CGFloat = 30
    static let captureDotWidth: CGFloat = 16

    let activity: NotchLiveActivity?
    /// Running terminal sessions, counted beside an activity that outranks them.
    let terminalBadgeCount: Int
    let capture: NotchCaptureUse

    var isEmpty: Bool { activity == nil && !capture.isActive }

    var leftWingWidth: CGFloat {
        guard activity != nil else { return 0 }
        return Self.glyphWidth + (terminalBadgeCount > 0 ? Self.terminalBadgeWidth : 0)
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
        let activity = activity(at: now)
        let showsTerminalBadge: Bool
        switch activity {
        case .terminal, nil: showsTerminalBadge = false
        case .dictation, .meeting, .timer, .nowPlaying: showsTerminalBadge = true
        }
        return NotchLivePresentation(
            activity: activity,
            terminalBadgeCount: showsTerminalBadge ? max(runningTerminalCount, 0) : 0,
            capture: capture)
    }

    private func activity(at now: Date) -> NotchLiveActivity? {
        if isDictating { return .dictation }
        if let meeting { return .meeting(meeting) }
        if let timerEnd, timerEnd > now { return .timer(end: timerEnd) }
        if runningTerminalCount > 0 { return .terminal(runningCount: runningTerminalCount) }
        if isPlaying { return .nowPlaying }
        return nil
    }
}
