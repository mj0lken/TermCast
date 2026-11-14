import Darwin
import Foundation

enum TerminalRunEvent: Sendable {
    case output(String)
    case finished(termination: ShellCommandTermination, updatedDirectory: String?)
}

struct TerminalRunHandle: Sendable {
    let events: AsyncStream<TerminalRunEvent>
    let sendInput: @Sendable (String) -> Void
    let stop: @Sendable () -> Void
}

enum TerminalSessionRunner {
    private static let shell = "/bin/zsh"
    private static let readSize = 16 * 1024
    private static let flushInterval: Duration = .milliseconds(35)
    private static let stopGrace: DispatchTimeInterval = .seconds(2)
    private static let cwdTargetFD: Int32 = 9
    private static let queue = DispatchQueue(
        label: "com.tinycast.terminal-session", qos: .userInitiated, attributes: .concurrent)

    nonisolated static func start(
        command: String,
        workingDirectory: String,
        loadsShellEnvironment: Bool
    ) -> TerminalRunHandle {
        let expanded = (workingDirectory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return failedHandle(
                String(localized: "The folder “\(workingDirectory)” no longer exists."))
        }

        var cwdPipe: [Int32] = [0, 0]
        let hasCwdPipe = pipe(&cwdPipe) == 0
        if hasCwdPipe {
            _ = fcntl(cwdPipe[0], F_SETFD, FD_CLOEXEC)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["TINYCAST"] = "1"
        environment["TERM"] = "xterm-256color"

        let flag = loadsShellEnvironment ? "-ilc" : "-lc"
        // fd 9 reports the shell's final directory so `cd` persists across runs in the same tab.
        let wrapper =
            hasCwdPipe
            ? #"eval "$1"; __tc_ec=$?; pwd -L >&9 2>/dev/null; exit $__tc_ec"#
            : #"eval "$1""#
        let arguments = [flag, wrapper, "zsh", command]

        let extra = hasCwdPipe ? (source: cwdPipe[1], target: cwdTargetFD) : nil
        guard
            let terminal = PseudoTerminal.spawn(
                executable: shell,
                arguments: arguments,
                environment: environment,
                workingDirectory: expanded,
                sendsEOF: false,
                extraDescriptor: extra)
        else {
            if hasCwdPipe {
                Darwin.close(cwdPipe[0])
                Darwin.close(cwdPipe[1])
            }
            return failedHandle(String(localized: "The shell could not be started."))
        }

        if hasCwdPipe {
            Darwin.close(cwdPipe[1])
        }
        let cwdReadFD: Int32? = hasCwdPipe ? cwdPipe[0] : nil
        let stopped = StopState()

        let events = AsyncStream<TerminalRunEvent> { continuation in
            queue.async {
                drain(terminal, cwdReadFD: cwdReadFD, stopped: stopped, into: continuation)
            }
        }

        return TerminalRunHandle(
            events: events,
            sendInput: { line in
                terminal.writeInput(line.hasSuffix("\n") ? line : line + "\n")
            },
            stop: { [weak stopped] in
                stopped?.mark()
                terminal.signalSession(SIGINT)
                terminal.signalSession(SIGTERM)
                queue.asyncAfter(deadline: .now() + stopGrace) {
                    terminal.signalSession(SIGKILL)
                }
            })
    }

    nonisolated private static func failedHandle(_ reason: String) -> TerminalRunHandle {
        TerminalRunHandle(
            events: AsyncStream { continuation in
                continuation.yield(
                    .finished(termination: .launchFailed(reason), updatedDirectory: nil))
                continuation.finish()
            },
            sendInput: { _ in },
            stop: {})
    }

    nonisolated private static func drain(
        _ terminal: PseudoTerminal,
        cwdReadFD: Int32?,
        stopped: StopState,
        into continuation: AsyncStream<TerminalRunEvent>.Continuation
    ) {
        var decoder = ShellCommandRunner.TerminalTextDecoder()
        var buffer = [UInt8](repeating: 0, count: readSize)
        var lastYield = ContinuousClock().now

        while true {
            if decoder.canFlush, !hasOutput(terminal.parentEnd, within: flushInterval) {
                if let text = decoder.take(force: true) {
                    continuation.yield(.output(text))
                    lastYield = ContinuousClock().now
                }
                continue
            }
            let count = read(terminal.parentEnd, &buffer, readSize)
            guard count > 0 else { break }
            decoder.append(buffer, count: count)
            let due = ContinuousClock().now - lastYield >= flushInterval
            if let text = decoder.take(force: due) {
                continuation.yield(.output(text))
                lastYield = ContinuousClock().now
            }
        }
        if let text = decoder.take(force: true) { continuation.yield(.output(text)) }
        if let text = decoder.takeTruncated() { continuation.yield(.output(text)) }

        let status = terminal.wait()
        terminal.close()

        let updatedDirectory = cwdReadFD.flatMap(readReportedDirectory)
        let termination: ShellCommandTermination =
            stopped.isSet ? .stopped : .exited(status: status)
        continuation.yield(.finished(termination: termination, updatedDirectory: updatedDirectory))
        continuation.finish()
    }

    nonisolated private static func readReportedDirectory(_ fd: Int32) -> String? {
        defer { Darwin.close(fd) }
        var bytes: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { break }
            bytes.append(contentsOf: chunk[0..<n])
            if bytes.count > 8192 { break }
        }
        let path = (String(bytes: bytes, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    nonisolated private static func hasOutput(_ descriptor: Int32, within interval: Duration) -> Bool {
        var request = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        var ready: Int32
        repeat {
            ready = poll(&request, 1, Int32(interval / .milliseconds(1)))
        } while ready < 0 && errno == EINTR
        return ready != 0
    }

    private final class StopState: @unchecked Sendable {
        private let lock = NSLock()
        private var marked = false

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return marked
        }

        func mark() {
            lock.lock()
            marked = true
            lock.unlock()
        }
    }
}
