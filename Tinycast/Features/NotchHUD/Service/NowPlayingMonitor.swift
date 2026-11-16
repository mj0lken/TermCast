import Foundation
import os

/// Runs `NowPlayingRelay.js` under `osascript` and reports each now-playing change it prints.
@MainActor
final class NowPlayingMonitor {
    var onMessage: ((NowPlayingRelayMessage) -> Void)?
    var onExit: (() -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var reader: Task<Void, Never>?
    private var buffer = Data()

    private static let logger = Logger(subsystem: "com.tinycast", category: "NowPlaying")
    private static let hostURL = URL(fileURLWithPath: "/usr/bin/osascript")
    /// A line carries one base64 artwork image; anything this long is not the relay talking.
    private static let lineLimit = 8 * 1_048_576

    func start() {
        guard process == nil else { return }
        guard let script = Bundle.main.url(forResource: "NowPlayingRelay", withExtension: "js") else {
            Self.logger.error("NowPlayingRelay.js is missing from the app bundle")
            return
        }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = Self.hostURL
        process.arguments = ["-l", "JavaScript", script.path]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        // A terminal shell that inherited this end would keep the relay alive past Tinycast.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC)

        let (chunks, continuation) = AsyncStream.makeStream(of: Data.self)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty else {
                continuation.yield(data)
                return
            }
            handle.readabilityHandler = nil
            continuation.finish()
        }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            continuation.finish()
            Self.logger.error("Could not start the now-playing relay: \(error.localizedDescription)")
            return
        }
        self.process = process
        input = stdin.fileHandleForWriting
        reader = Task { [weak self] in
            // One task draining one stream keeps chunks in the order the relay wrote them.
            for await chunk in chunks {
                self?.consume(chunk)
            }
            guard !Task.isCancelled else { return }
            self?.relayDidCloseOutput()
        }
    }

    /// Closing stdin is the relay's cue to leave; SIGTERM covers one that is not listening.
    func stop() {
        guard let process else { return }
        release()
        process.terminate()
    }

    private func release() {
        reader?.cancel()
        reader = nil
        try? input?.close()
        input = nil
        process = nil
        buffer.removeAll()
    }

    private func consume(_ data: Data) {
        guard !Task.isCancelled else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let message = NowPlayingRelayMessage.decode(line: line) else { continue }
            onMessage?(message)
        }
        if buffer.count > Self.lineLimit { buffer.removeAll() }
    }

    private func relayDidCloseOutput() {
        Self.logger.error("The now-playing relay exited unexpectedly")
        release()
        onExit?()
    }
}
