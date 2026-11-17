import SwiftUI

/// The Home page's week strip and the selected day's events.
struct NotchCalendarAgendaCard: View {
    let state: NotchOpenTrayState
    let onEnableCalendar: () -> Void
    let onJoinMeeting: (MeetingEvent) -> Void

    var body: some View {
        let now = Date()
        let week = NotchWeekStrip.build(around: now)
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: week.monthLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(verbatim: week.yearLabel)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    ForEach(week.days) { slot in
                        let selected = Calendar.current.isDate(slot.date, inSameDayAs: state.selectedDay)
                        Button {
                            state.selectedDay = slot.date
                        } label: {
                            VStack(spacing: 2) {
                                Text(verbatim: slot.weekdayShort)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(
                                        selected ? Color.white : Theme.Colors.textSecondary)
                                Text(verbatim: slot.dayNumber)
                                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                                    .foregroundStyle(
                                        selected
                                            ? Color.white
                                            : (slot.isToday ? Color.accentColor : Theme.Colors.textPrimary))
                            }
                            .frame(width: 30, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selected ? Color.accentColor : .clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !state.isCalendarEnabled || !state.hasCalendarAccess {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("See upcoming meetings & join calls")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Button("Enable Calendar…", action: onEnableCalendar)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let dayEvents = NotchWeekStrip.filterEvents(
                    state.weekEvents,
                    on: state.selectedDay,
                    now: now,
                    hideAllDay: state.hidesAllDayEvents)
                if dayEvents.isEmpty {
                    VStack {
                        Text("No upcoming events")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: Theme.Spacing.xs) {
                            ForEach(dayEvents) { event in
                                NotchAgendaEventRow(
                                    event: event, now: now, leadMinutes: state.meetingLeadMinutes
                                ) {
                                    onJoinMeeting(event)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }
}

private struct NotchAgendaEventRow: View {
    let event: MeetingEvent
    let now: Date
    let leadMinutes: Int
    let action: () -> Void

    private var barColor: Color {
        guard let c = event.calendarColor else { return .accentColor }
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    private var subtitle: String {
        if let link = event.link {
            return String(localized: "Online (\(link.provider.title))")
        }
        return event.calendarName
    }

    /// The pill appears exactly when the closed notch is counting down to this call.
    private var isJoinable: Bool {
        guard event.link != nil else { return false }
        return NotchMeetingCountdown(leadMinutes: leadMinutes).current(from: [event], now: now) != nil
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Capsule()
                    .fill(barColor)
                    .frame(width: 3)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: event.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(verbatim: subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if event.isAllDay {
                    Text("All-day")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else if isJoinable {
                    Text("Join")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.Colors.success))
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(event.start, format: .dateTime.hour().minute())
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(event.end, format: .dateTime.hour().minute())
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.Colors.rowHover)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
