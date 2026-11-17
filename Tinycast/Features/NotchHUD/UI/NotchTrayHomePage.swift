import AppKit
import SwiftUI

/// The Home page: Now Playing beside the week's agenda.
struct NotchHomeBodyView: View {
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
