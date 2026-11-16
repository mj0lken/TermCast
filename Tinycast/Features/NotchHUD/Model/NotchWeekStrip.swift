import Foundation

/// Pure 6-day week strip and per-day agenda formatter for the Notch Calendar pane.
enum NotchWeekStrip {
    struct DaySlot: Identifiable, Equatable, Sendable {
        let date: Date
        let weekdayShort: String
        let dayNumber: String
        let isToday: Bool

        var id: Date { date }
    }

    static let dayOffsets = [-2, -1, 0, 1, 2, 3]

    static func build(
        around referenceDate: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> (monthLabel: String, yearLabel: String, days: [DaySlot]) {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let monthLabel = referenceDate.formatted(.dateTime.month(.abbreviated).locale(locale))
        let yearLabel = referenceDate.formatted(.dateTime.year().locale(locale))

        let slots: [DaySlot] = dayOffsets.compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else {
                return nil
            }
            let weekday = day.formatted(.dateTime.weekday(.abbreviated).locale(locale))
            let number = day.formatted(.dateTime.day().locale(locale))
            return DaySlot(
                date: day,
                weekdayShort: weekday,
                dayNumber: number,
                isToday: offset == 0)
        }
        return (monthLabel, yearLabel, slots)
    }

    static func dateInterval(
        around referenceDate: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: dayOffsets.first ?? -2, to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: (dayOffsets.last ?? 3) + 1, to: todayStart) ?? todayStart
        return DateInterval(start: start, end: max(start, end))
    }

    static func filterEvents(
        _ events: [MeetingEvent],
        on dayStart: Date,
        now: Date,
        hideAllDay: Bool = false,
        calendar: Calendar = .current
    ) -> [MeetingEvent] {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let isToday = calendar.isDate(dayStart, inSameDayAs: now)
        return events
            .filter { event in
                guard !event.isDeclined else { return false }
                if hideAllDay, event.isAllDay { return false }
                guard event.start < dayEnd, event.end > dayStart else { return false }
                if isToday, !event.isAllDay, event.end <= now { return false }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return !lhs.isAllDay }
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }
}
