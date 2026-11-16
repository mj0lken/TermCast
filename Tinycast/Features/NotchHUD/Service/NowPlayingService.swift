import AppKit
import Darwin
import Foundation

/// System-wide Now Playing state fed by `NowPlayingMonitor`, plus `MediaRemote` transport.
@MainActor
@Observable
final class NowPlayingService {
    /// Commands defined by `MRMediaRemoteCommand`.
    private enum Command: UInt32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private(set) var snapshot: NowPlayingSnapshot?
    private(set) var artworkImage: NSImage?
    private(set) var appIconImage: NSImage?
    private(set) var sourceName: String?

    /// Fired when playback moves to a different track, never for the track found at launch.
    @ObservationIgnored var onTrackChanged: ((NowPlayingSnapshot) -> Void)?

    @ObservationIgnored private let monitor = NowPlayingMonitor()
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var hasBaseline = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        hasBaseline = false
        monitor.onMessage = { [weak self] in self?.apply($0) }
        monitor.onExit = { [weak self] in self?.show(nil) }
        monitor.start()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        monitor.stop()
        show(nil)
    }

    /// Called as the tray opens, so a relay that died gets one relaunch per open.
    func resume() {
        guard isStarted else { return }
        monitor.start()
    }

    func togglePlayPause() {
        send(.togglePlayPause)
    }

    func nextTrack() {
        send(.nextTrack)
    }

    func previousTrack() {
        send(.previousTrack)
    }

    func seek(to seconds: TimeInterval) {
        guard let current = snapshot, current.duration > 0 else { return }
        let target = current.seeking(to: seconds, at: Date())
        _ = MediaRemoteBridge.shared?.setElapsedTime(target.elapsedAtAnchor)
        snapshot = target
    }

    private func send(_ command: Command) {
        _ = MediaRemoteBridge.shared?.sendCommand(command.rawValue)
    }

    private func apply(_ message: NowPlayingRelayMessage) {
        let previous = snapshot
        let next = message.snapshot(carrying: previous, receivedAt: Date())
        show(next)
        defer { hasBaseline = true }
        guard hasBaseline, let next, next.isPlaying,
            next.title != previous?.title || next.artist != previous?.artist
        else { return }
        onTrackChanged?(next)
    }

    private func show(_ next: NowPlayingSnapshot?) {
        guard next != snapshot else { return }
        if next?.artworkData != snapshot?.artworkData {
            artworkImage = next?.artworkData.flatMap(NSImage.init(data:))
        }
        if next?.clientBundleID != snapshot?.clientBundleID || next?.clientName != snapshot?.clientName {
            showSource(of: next)
        }
        snapshot = next
    }

    private func showSource(of next: NowPlayingSnapshot?) {
        let bundleID = next?.clientBundleID
        let workspace = NSWorkspace.shared
        let running = bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        appIconImage = bundleID.flatMap(workspace.urlForApplication(withBundleIdentifier:))
            .map { workspace.icon(forFile: $0.path) }
        sourceName = running?.localizedName ?? next?.clientName
    }
}

/// Transport only: macOS still takes commands from a process Apple did not sign, but not reads.
private final class MediaRemoteBridge: Sendable {
    private typealias SendCommandFn = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Bool

    static let shared = MediaRemoteBridge()

    private let sendCommandFn: SendCommandFn
    private let setElapsedFn: SetElapsedFn?

    private init?() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY),
            let sendCommand = dlsym(handle, "MRMediaRemoteSendCommand")
        else { return nil }

        sendCommandFn = unsafeBitCast(sendCommand, to: SendCommandFn.self)
        setElapsedFn = dlsym(handle, "MRMediaRemoteSetElapsedTime")
            .map { unsafeBitCast($0, to: SetElapsedFn.self) }
    }

    func sendCommand(_ rawCommand: UInt32) -> Bool {
        sendCommandFn(rawCommand, nil)
    }

    func setElapsedTime(_ seconds: Double) -> Bool {
        setElapsedFn?(seconds) ?? false
    }
}
