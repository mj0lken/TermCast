import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchOpenTrayView: View {
    let state: NotchOpenTrayState
    let nowPlaying: NowPlayingService
    let shelfStore: NotchShelfStore
    let battery: BatteryStatusService
    let onOpenClipboard: () -> Void
    let onOpenCamera: () -> Void
    let menu: NotchAppMenuActions
    let onEnableCalendar: () -> Void
    let onJoinMeeting: (MeetingEvent) -> Void

    private var layout: NotchHUDGeometry.OpenTrayLayout { state.layout }

    private var targetLeftExt: CGFloat {
        guard layout.isNotched else { return 0 }
        let trayStart = layout.earRadius
        return max(layout.notchOriginX - trayStart, 0)
    }

    private var targetRightExt: CGFloat {
        guard layout.isNotched else { return 0 }
        let trayEnd = layout.earRadius + layout.trayWidth
        return max(trayEnd - (layout.notchOriginX + layout.notchWidth), 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            trayBackdrop
                .frame(
                    width: layout.panelFrame.width,
                    height: state.isExpanded ? layout.trayHeight : layout.headerHeight,
                    alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 0) {
                NotchOpenHeaderBar(
                    state: state,
                    shelfCount: shelfStore.items.count,
                    battery: battery,
                    onOpenClipboard: onOpenClipboard,
                    onOpenCamera: onOpenCamera,
                    menu: menu
                )
                .frame(width: layout.trayWidth, height: layout.headerHeight)

                Group {
                    switch state.tab {
                    case .home:
                        NotchHomeBodyView(
                            state: state,
                            nowPlaying: nowPlaying,
                            onEnableCalendar: onEnableCalendar,
                            onJoinMeeting: onJoinMeeting)
                    case .shelf:
                        NotchShelfBodyView(shelfStore: shelfStore)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.lg)
                .frame(
                    width: layout.trayWidth,
                    height: max(layout.trayHeight - layout.headerHeight, 0))
            }
            .opacity(state.isExpanded ? 1 : 0)
            .blur(radius: state.isExpanded ? 0 : 6)
        }
        .frame(
            width: layout.panelFrame.width,
            height: layout.panelFrame.height,
            alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.notchHUDStyle, state.style)
        .animation(Theme.NotchMotion.wing, value: state.isExpanded)
        .animation(Theme.NotchMotion.wing, value: state.tab)
    }

    @ViewBuilder
    private var trayBackdrop: some View {
        if layout.isNotched {
            let shape = NotchWingShape(
                notchOriginX: layout.notchOriginX,
                notchWidth: layout.notchWidth,
                leftExtension: state.isExpanded ? targetLeftExt : 0,
                rightExtension: state.isExpanded ? targetRightExt : 0,
                earRadius: layout.earRadius,
                innerCornerRadius: layout.cornerRadius)
            // No rim: any stroke beside the cutout reads as a seam against the bezel.
            shape.fill(Theme.Colors.notchHardwareBlack)
        } else {
            let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
            shape
                .fill(Theme.Colors.notchHardwareBlack)
                .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: Theme.Size.hairline))
                .frame(width: layout.trayWidth)
                .scaleEffect(
                    x: state.isExpanded ? 1 : 0.72,
                    y: state.isExpanded ? 1 : 0.4,
                    anchor: .top)
                .opacity(state.isExpanded ? 1 : 0)
        }
    }
}

// MARK: - Header Bar

private struct NotchOpenHeaderBar: View {
    let state: NotchOpenTrayState
    let shelfCount: Int
    let battery: BatteryStatusService
    let onOpenClipboard: () -> Void
    let onOpenCamera: () -> Void
    let menu: NotchAppMenuActions

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.xs) {
                NotchTabButton(
                    symbol: "house.fill",
                    label: String(localized: "Home"),
                    isSelected: state.tab == .home,
                    badgeCount: 0
                ) {
                    state.tab = .home
                }

                NotchTabButton(
                    symbol: "tray.fill",
                    label: String(localized: "Shelf"),
                    isSelected: state.tab == .shelf,
                    badgeCount: shelfCount
                ) {
                    state.tab = .shelf
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.layout.isNotched {
                ZStack {
                    Color.clear
                        .frame(width: state.layout.notchWidth, height: state.layout.headerHeight)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                Spacer(minLength: 0)

                if let metric = state.inlineHUDMetric {
                    NotchInlineOpenHUDChip(metric: metric)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    if state.showsClipboard {
                        Button(action: onOpenClipboard) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Open Clipboard History"))
                    }

                    Button(action: onOpenCamera) {
                        Image(systemName: "web.camera")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Open Camera Mirror"))

                    NotchAppMenuButton(actions: menu)

                    if state.showsBattery, battery.status.hasBattery {
                        NotchBatteryBadge(status: battery.status)
                    }
                }
            }
            .padding(.trailing, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.16), value: state.inlineHUDMetric)
    }
}

private struct NotchTabButton: View {
    let symbol: String
    let label: String
    let isSelected: Bool
    let badgeCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                if badgeCount > 0 {
                    Text(verbatim: "\(badgeCount)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.Colors.controlHover : .clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct NotchBatteryBadge: View {
    let status: BatteryStatusService.Status

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: "\(status.percentage)%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)

            Image(systemName: status.isPluggedIn ? "battery.100percent.bolt" : "battery.100percent")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    status.isPluggedIn ? Theme.Colors.success : Theme.Colors.textPrimary,
                    Theme.Colors.textSecondary)
        }
    }
}

private struct NotchInlineOpenHUDChip: View {
    @Environment(\.notchHUDStyle) private var style
    let metric: NotchHUDMetric

    var body: some View {
        HStack(spacing: 6) {
            SymbolImage(name: metric.symbol, size: 12, monochrome: true)
                .foregroundStyle(Theme.Colors.textPrimary)
            Capsule()
                .fill(Theme.Colors.controlSurface)
                .frame(width: 56, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(style.fill)
                        .frame(width: 56 * CGFloat(metric.effectiveLevel), height: 4)
                }
            if style.showsPercentage {
                Text(verbatim: metric.percentageText())
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Capsule().fill(Theme.Colors.controlSurface))
    }
}

// MARK: - Home Page (Now Playing + Calendar)

private struct NotchHomeBodyView: View {
    let state: NotchOpenTrayState
    let nowPlaying: NowPlayingService
    let onEnableCalendar: () -> Void
    let onJoinMeeting: (MeetingEvent) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if state.showsMedia {
                NotchNowPlayingCard(nowPlaying: nowPlaying)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if state.showsMedia, state.showsCalendar {
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: Theme.Size.hairline)
                    .padding(.vertical, Theme.Spacing.xs)
            }

            if state.showsCalendar {
                NotchCalendarAgendaCard(
                    state: state,
                    onEnableCalendar: onEnableCalendar,
                    onJoinMeeting: onJoinMeeting
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !state.showsMedia, !state.showsCalendar {
                Text("Turn on Media or Calendar in Notch settings.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct NotchNowPlayingCard: View {
    let nowPlaying: NowPlayingService

    var body: some View {
        if let snapshot = nowPlaying.snapshot {
            HStack(spacing: Theme.Spacing.md) {
                artworkBadge

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: snapshot.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)

                        if !snapshot.artist.isEmpty {
                            Text(verbatim: snapshot.artist)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }

                        if let sourceName = nowPlaying.sourceName {
                            NotchNowPlayingSourceLabel(name: sourceName, isPlaying: snapshot.isPlaying)
                        }
                    }

                    TimelineView(
                        .periodic(
                            from: .now,
                            by: snapshot.isPlaying ? 1.0 : 3600.0)
                    ) { context in
                        NotchScrubberRow(
                            snapshot: snapshot,
                            now: context.date,
                            onSeek: { nowPlaying.seek(to: $0) })
                    }

                    HStack(spacing: Theme.Spacing.xl) {
                        Spacer(minLength: 0)
                        Button {
                            nowPlaying.previousTrack()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .frame(width: 28, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Previous Track"))

                        Button {
                            nowPlaying.togglePlayPause()
                        } label: {
                            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            snapshot.isPlaying
                                ? String(localized: "Pause")
                                : String(localized: "Play"))

                        Button {
                            nowPlaying.nextTrack()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .frame(width: 28, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Next Track"))
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
        } else {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "music.note")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text("Nothing Playing")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var artworkBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork = nowPlaying.artworkImage {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Theme.Colors.controlSurface
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            .frame(width: 82, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let appIcon = nowPlaying.appIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .offset(x: 5, y: 5)
            }
        }
        .padding(.trailing, 4)
    }
}

private struct NotchNowPlayingSourceLabel: View {
    let name: String
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                .font(.system(size: 9, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
            Text(verbatim: name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.Colors.textTertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Playing from \(name)"))
    }
}

private struct NotchScrubberRow: View {
    let snapshot: NowPlayingSnapshot
    let now: Date
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        let elapsed = snapshot.liveElapsed(at: now)
        let progress = CGFloat(snapshot.progress(at: now))
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.controlSurface)
                        .frame(height: 5)
                    Capsule()
                        .fill(Theme.Colors.textPrimary)
                        .frame(width: max(width * progress, progress > 0 ? 5 : 0), height: 5)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            guard snapshot.duration > 0 else { return }
                            let fraction = min(max(value.location.x / width, 0), 1)
                            onSeek(Double(fraction) * snapshot.duration)
                        })
            }
            .frame(height: 8)

            HStack {
                Text(verbatim: NowPlayingSnapshot.formatTimestamp(elapsed))
                Spacer(minLength: 4)
                Text(verbatim: NowPlayingSnapshot.formatTimestamp(snapshot.duration))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

// MARK: - Calendar & Upcoming Card

private struct NotchCalendarAgendaCard: View {
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
                                NotchAgendaEventRow(event: event) {
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

// MARK: - Shelf Page (AirDrop + Drag Staging Tray)

private struct NotchShelfBodyView: View {
    let shelfStore: NotchShelfStore

    @State private var isTargetingAirDrop = false
    @State private var isTargetingShelf = false

    private static let dropTypes: [UTType] = [.fileURL, .url, .plainText]

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                shelfStore.airDropAllStaged()
            } label: {
                VStack(spacing: Theme.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(
                                isTargetingAirDrop
                                    ? Color.accentColor.opacity(0.28)
                                    : Theme.Colors.controlSurface)
                            .frame(width: 54, height: 54)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Text("AirDrop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .frame(width: 124)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isTargetingAirDrop ? Color.accentColor : Theme.Colors.border,
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrop(of: Self.dropTypes, isTargeted: $isTargetingAirDrop) { providers in
                shelfStore.airDrop(providers: providers)
                return true
            }

            ZStack(alignment: .topTrailing) {
                Group {
                    if shelfStore.items.isEmpty {
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text("Drop files, links or text here")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: Theme.Spacing.md) {
                                ForEach(shelfStore.items) { item in
                                    NotchShelfCardView(
                                        item: item,
                                        shelfStore: shelfStore)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .frame(maxHeight: .infinity)
                        }
                        .scrollIndicators(.never)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isTargetingShelf ? Color.accentColor : Theme.Colors.border,
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                )
                .onDrop(of: Self.dropTypes, isTargeted: $isTargetingShelf) { providers in
                    shelfStore.ingestDrop(providers: providers)
                    return true
                }

                if !shelfStore.items.isEmpty {
                    Button {
                        shelfStore.clear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(6)
                            .background(Circle().fill(Theme.Colors.controlSurface))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel(String(localized: "Clear Shelf"))
                }
            }
        }
    }
}

private struct NotchShelfCardView: View {
    let item: NotchShelfItem
    let shelfStore: NotchShelfStore

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                shelfIcon
                    .frame(width: 44, height: 48)

                Text(verbatim: item.displayTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 98)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovering ? Theme.Colors.controlSurface : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                shelfStore.open(item)
            }
            .onDrag {
                shelfStore.itemProvider(for: item)
            }

            if isHovering {
                Button {
                    shelfStore.remove(id: item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textPrimary, Theme.Colors.notchHardwareBlack)
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var shelfIcon: some View {
        switch item.kind {
        case .file(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        case .link:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 36, height: 44)
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
            }
        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.Colors.controlHover)
                    .frame(width: 36, height: 44)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }
}

// MARK: - App Menu

struct NotchAppMenuActions {
    let openNotchSettings: () -> Void
}

/// The menu-bar item, moved into the notch while Open Notch hides the status item.
private struct NotchAppMenuButton: View {
    let actions: NotchAppMenuActions

    var body: some View {
        Menu {
            MenuBarMenu(appName: Bundle.main.appDisplayName)
            Divider()
            Button("Notch Settings…", action: actions.openNotchSettings)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Bundle.main.appDisplayName)
    }
}
