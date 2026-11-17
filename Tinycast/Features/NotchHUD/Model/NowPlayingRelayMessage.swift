import Foundation

/// One line printed by `NowPlayingRelay.js`; a line with no title means nothing is playing.
struct NowPlayingRelayMessage: Decodable, Sendable, Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let elapsed: TimeInterval?
    let timestamp: TimeInterval?
    let rate: Double?
    let isPlaying: Bool?
    let bundleID: String?
    let parentBundleID: String?
    let appName: String?
    let artworkID: String?
    let artwork: Data?

    static func decode(line: Data) -> NowPlayingRelayMessage? {
        try? JSONDecoder().decode(NowPlayingRelayMessage.self, from: line)
    }

    /// The relay sends each image once, so later lines for the same artwork reuse `previous`'s.
    func snapshot(carrying previous: NowPlayingSnapshot?, receivedAt: Date) -> NowPlayingSnapshot? {
        let next = NowPlayingSnapshot(
            title: title ?? "",
            artist: artist ?? "",
            album: album ?? "",
            duration: duration ?? 0,
            elapsedAtAnchor: elapsed ?? 0,
            anchorDate: timestamp.map(Date.init(timeIntervalSince1970:)) ?? receivedAt,
            playbackRate: rate ?? 1,
            isPlaying: isPlaying ?? false,
            clientBundleID: owningBundleID,
            clientName: appName,
            artworkID: artworkID,
            artworkData: artwork ?? carriedArtwork(from: previous))
        return next.hasTrack ? next : nil
    }

    /// Browsers play through a helper process; its parent is the app the user knows.
    private var owningBundleID: String? {
        guard let parentBundleID, !parentBundleID.isEmpty else { return bundleID }
        return parentBundleID
    }

    private func carriedArtwork(from previous: NowPlayingSnapshot?) -> Data? {
        guard let artworkID, previous?.artworkID == artworkID else { return nil }
        return previous?.artworkData
    }
}
