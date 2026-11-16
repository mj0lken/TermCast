import Foundation
import os

/// Runs `NowPlayingRelay.js` under `osascript` and reports each now-playing change it prints.
@MainActor
final class NowPlayingMonitor {
    var onMessage: ((NowPlayingRelayMessage) -> Void)?
    var onExit: (() -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var launchID: UInt64 = 0

    private static let logger = Logger(subsystem: "com.tinycast", category: "NowPlaying")
    private static let hostURL = URL(fileURLWithPath: "/usr/bin/osascript")
    /// A line carries one base64 artwork image; anything this long is not the relay talking.
    private static let lineLimit = 8 * 1_048_576

    var isRunning: Bool { process?.isRunning == true }

    func start() {
        guard !isRunning else { return }
        guard let script = Bundle.main.url(forResource: "NowPlayingRelay", withExtension: "js") else {
            Self.logger.error("NowPlayingRelay.js is missing from the app bundle")
            return
        }
        launchID &+= 1
        let launch = launchID
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = Self.hostURL
        process.arguments = ["-l", "JavaScript", script.path]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consume(data, from: launch) }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.didExit(launch, status: status) }
        }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            Self.logger.error("Could not start the now-playing relay: \(error.localizedDescription)")
            return
        }
        self.process = process
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
    }

    /// Closing stdin is the relay's cue to leave; SIGTERM covers one that is not listening.
    func stop() {
        guard let process else { return }
        launchID &+= 1
        release()
        process.terminate()
    }

    private func release() {
        output?.readabilityHandler = nil
        try? input?.close()
        process = nil
        input = nil
        output = nil
        buffer.removeAll()
    }

    private func consume(_ data: Data, from launch: UInt64) {
        guard launch == launchID else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let message = NowPlayingRelayMessage.decode(line: line) else { continue }
            onMessage?(message)
        }
        if buffer.count > Self.lineLimit { buffer.removeAll() }
    }

    private func didExit(_ launch: UInt64, status: Int32) {
        guard launch == launchID else { return }
        Self.logger.error("The now-playing relay exited unexpectedly with status \(status)")
        release()
        onExit?()
    }
}
