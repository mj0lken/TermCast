import Foundation

/// Pure playback snapshot and live elapsed-time interpolation for the Notch media player.
struct NowPlayingSnapshot: Sendable, Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let elapsedAtAnchor: TimeInterval
    let anchorDate: Date
    let playbackRate: Double
    let isPlaying: Bool
    let clientBundleID: String?
    let clientName: String?
    let artworkID: String?
    let artworkData: Data?

    var hasTrack: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func liveElapsed(at now: Date) -> TimeInterval {
        let base = max(elapsedAtAnchor, 0)
        let rate = isPlaying ? max(playbackRate, 0) : 0
        let advanced = base + max(now.timeIntervalSince(anchorDate), 0) * rate
        guard duration > 0 else { return advanced }
        return min(advanced, duration)
    }

    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(liveElapsed(at: now) / duration, 0), 1)
    }

    func seeking(to seconds: TimeInterval, at now: Date) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsedAtAnchor: min(max(seconds, 0), duration),
            anchorDate: now,
            playbackRate: playbackRate,
            isPlaying: isPlaying,
            clientBundleID: clientBundleID,
            clientName: clientName,
            artworkID: artworkID,
            artworkData: artworkData)
    }

    static func formatTimestamp(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
