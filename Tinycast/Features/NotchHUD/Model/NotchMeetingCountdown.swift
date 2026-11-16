import Foundation

/// Which meeting the closed notch counts down to, and when that answer next changes.
struct NotchMeetingCountdown: Sendable {
    /// How long a meeting that has started stays on the wings.
    static let grace: TimeInterval = 5 * 60

    let leadMinutes: Int

    private var lead: TimeInterval { TimeInterval(max(leadMinutes, 1) * 60) }

    func current(from events: [MeetingEvent], now: Date) -> MeetingEvent? {
        Self.candidates(from: events, now: now).first {
            now >= $0.start - lead && now < Self.expiry(of: $0)
        }
    }

    /// The single wake-up the notch schedules, so an idle Mac never ticks for a meeting hours away.
    func nextChange(from events: [MeetingEvent], now: Date) -> Date? {
        Self.candidates(from: events, now: now)
            .flatMap { [$0.start - lead, Self.expiry(of: $0)] }
            .filter { $0 > now }
            .min()
    }

    static func label(for event: MeetingEvent, now: Date, locale: Locale) -> String {
        let delta = event.start.timeIntervalSince(now)
        guard delta > 0 else { return String(localized: "Now", locale: locale) }
        let minutes = max(1, Int((delta / 60).rounded(.up)))
        return Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.minutes], width: .narrow).locale(locale))
    }

    private static func candidates(from events: [MeetingEvent], now: Date) -> [MeetingEvent] {
        events
            .filter { !$0.isAllDay && !$0.isDeclined && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    private static func expiry(of event: MeetingEvent) -> Date {
        min(event.start + grace, event.end)
    }
}
