import SwiftUI

/// The closed notch's persistent wings: a glyph on the left, a compact readout on the right.
struct NotchLiveActivityView: View {
    let state: NotchLiveActivityState
    let nowPlaying: NowPlayingService

    var body: some View {
        Group {
            if case .notched(
                let notchOriginX, let notchWidth, let notchHeight,
                let leftWingWidth, let rightWingWidth, let earRadius, let innerCornerRadius
            ) = state.layout.mode {
                ZStack(alignment: .topLeading) {
                    // No rim: any stroke beside the cutout reads as a seam against the bezel.
                    NotchWingShape(
                        notchOriginX: notchOriginX,
                        notchWidth: notchWidth,
                        leftExtension: state.isExpanded ? leftWingWidth : 0,
                        rightExtension: state.isExpanded ? rightWingWidth : 0,
                        earRadius: earRadius,
                        innerCornerRadius: innerCornerRadius
                    )
                    .fill(Theme.Colors.notchHardwareBlack)

                    HStack(spacing: 0) {
                        NotchLiveLeadingWing(presentation: state.presentation, nowPlaying: nowPlaying)
                            .frame(width: leftWingWidth, height: notchHeight)
                        Color.clear
                            .frame(width: notchWidth, height: notchHeight)
                        NotchLiveTrailingWing(state: state)
                            .frame(width: rightWingWidth, height: notchHeight)
                    }
                    .offset(x: notchOriginX - leftWingWidth)
                    .opacity(state.isExpanded ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(Theme.NotchMotion.wing, value: state.isExpanded)
                .animation(Theme.NotchMotion.wing, value: leftWingWidth)
                .animation(Theme.NotchMotion.wing, value: rightWingWidth)
            }
        }
        .frame(
            width: state.layout.panelFrame.width,
            height: state.layout.panelFrame.height,
            alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        switch state.presentation.activity {
        case .dictation:
            String(localized: "Dictating")
        case .meeting(let event):
            String(localized: "Upcoming meeting: \(event.title)")
        case .timer:
            String(localized: "Timer running")
        case .nowPlaying:
            nowPlaying.snapshot.map { String(localized: "Now playing: \($0.title)") } ?? ""
        case nil:
            terminalOrCaptureSummary
        }
    }
}

extension NotchLiveActivityView {
    /// With no activity on the wings, what is left is the terminal mark or the capture dot.
    fileprivate var terminalOrCaptureSummary: String {
        let count = state.presentation.terminalCount
        guard count > 0 else { return String(localized: "Microphone or camera in use") }
        return String(localized: "\(count) terminal sessions running")
    }
}

private struct NotchLiveLeadingWing: View {
    let presentation: NotchLivePresentation
    let nowPlaying: NowPlayingService

    var body: some View {
        HStack(spacing: 0) {
            if presentation.terminalCount > 0 {
                NotchLiveTerminalCount(count: presentation.terminalCount)
                    .frame(width: NotchLivePresentation.terminalWidth)
            }
            if let activity = presentation.activity {
                glyph(for: activity)
                    .frame(width: NotchLivePresentation.glyphWidth)
            }
        }
    }

    @ViewBuilder
    private func glyph(for activity: NotchLiveActivity) -> some View {
        switch activity {
        case .nowPlaying:
            if let artwork = nowPlaying.artworkImage {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                symbol(activity.symbol, tint: Theme.Colors.textPrimary)
            }
        case .meeting(let event):
            symbol(activity.symbol, tint: Self.calendarTint(of: event))
        case .dictation:
            symbol(activity.symbol, tint: Color.red)
        case .timer:
            symbol(activity.symbol, tint: Theme.Colors.textPrimary)
        }
    }

    private func symbol(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
    }

    private static func calendarTint(of event: MeetingEvent) -> Color {
        guard let color = event.calendarColor else { return .accentColor }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }
}

private struct NotchLiveTrailingWing: View {
    let state: NotchLiveActivityState

    var body: some View {
        HStack(spacing: 0) {
            if let activity = state.presentation.activity {
                readout(for: activity)
                    .frame(width: activity.readoutWidth)
            }
            if state.presentation.capture.isActive {
                Circle()
                    .fill(state.presentation.capture.camera ? Theme.Colors.success : Theme.Colors.warning)
                    .frame(width: 6, height: 6)
                    .frame(width: NotchLivePresentation.captureDotWidth)
            }
        }
    }

    @ViewBuilder
    private func readout(for activity: NotchLiveActivity) -> some View {
        switch activity {
        case .nowPlaying:
            NotchEqualizerView()
                .fixedSize()
        case .dictation:
            NotchLiveWaveform(levels: state.dictationLevels)
        case .timer(let end):
            Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        case .meeting(let event):
            TimelineView(.everyMinute) { context in
                Text(verbatim: NotchMeetingCountdown.label(for: event, now: context.date, locale: .current))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// Running terminal sessions: the terminal glyph lit in the brand's purple, and how many.
private struct NotchLiveTerminalCount: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "apple.terminal.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.brandSecondary)
            Text(verbatim: "\(count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

private struct NotchLiveWaveform: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.Colors.textPrimary)
                    .frame(width: 2.5, height: 3 + 11 * CGFloat(min(max(levels[index], 0), 1)))
            }
        }
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}
