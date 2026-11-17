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

enum TerminalInteractiveEvent: Sendable {
    case output([UInt8])
    case exited(status: Int32)
    case launchFailed(String)
}

struct TerminalInteractiveHandle: Sendable {
    let events: AsyncStream<TerminalInteractiveEvent>
    /// Each `.output` must be acknowledged once handled, or the reader stops after a few chunks.
    let acknowledgeOutput: @Sendable () -> Void
    let writeBytes: @Sendable ([UInt8]) -> Void
    let resize: @Sendable (Int, Int) -> Void
    let interrupt: @Sendable () -> Void
    let terminate: @Sendable () -> Void
    let hasChildProcesses: @Sendable () -> Bool

    nonisolated func writeText(_ text: String) {
        guard !text.isEmpty else { return }
        writeBytes(Array(text.utf8))
    }
}

enum TerminalSessionRunner {
    private static let shell = "/bin/zsh"
    private static let readSize = 16 * 1024
    private static let flushInterval: Duration = .milliseconds(35)
    private static let interactiveFlushInterval: Duration = .milliseconds(12)
    static let maxQueuedOutputChunks = 4
    private static let stopGrace: DispatchTimeInterval = .seconds(2)
    private static let cwdTargetFD: Int32 = 9
    private static let queue = DispatchQueue(
        label: "com.tinycast.terminal-session", qos: .userInitiated, attributes: .concurrent)

    nonisolated static func startInteractive(
        workingDirectory: String,
        homeDirectory: String,
        loadsShellEnvironment: Bool,
        rows: Int = TerminalEmulator.defaultRows,
        cols: Int = TerminalEmulator.defaultCols
    ) -> TerminalInteractiveHandle {
        let candidateDir = (workingDirectory as NSString).expandingTildeInPath
        let fallbackHome = (homeDirectory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        let resolvedDir: String
        if FileManager.default.fileExists(atPath: candidateDir, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            resolvedDir = candidateDir
        } else if FileManager.default.fileExists(atPath: fallbackHome, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            resolvedDir = fallbackHome
        } else {
            resolvedDir = "/"
        }

        var environment = ProcessInfo.processInfo.environment
        environment["TERMCAST"] = "1"
        environment["TINYCAST"] = "1"
        environment["TERM_PROGRAM"] = "Termcast"
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if (environment["LANG"] ?? "").isEmpty && (environment["LC_ALL"] ?? "").isEmpty {
            environment["LANG"] = "en_US.UTF-8"
        }
        if environment["CLICOLOR"] == nil {
            environment["CLICOLOR"] = "1"
        }
        if environment["LSCOLORS"] == nil {
            environment["LSCOLORS"] = "GxFxCxDxBxegedabagaced"
        }

        if let shimPath = ensureZshShimDirectory() {
            if let existingZDot = environment["ZDOTDIR"], existingZDot != shimPath {
                environment["TERMCAST_USER_ZDOTDIR"] = existingZDot
            } else {
                environment.removeValue(forKey: "TERMCAST_USER_ZDOTDIR")
            }
            environment["TERMCAST_SHIM_ZDOTDIR"] = shimPath
            environment["TERMCAST_LOAD_ENV"] = loadsShellEnvironment ? "1" : "0"
            environment["ZDOTDIR"] = shimPath
        }

        let args = loadsShellEnvironment ? ["-il"] : ["-i"]
        guard
            let terminal = PseudoTerminal.spawnInteractive(
                executable: shell,
                arguments: args,
                environment: environment,
                workingDirectory: resolvedDir,
                rows: rows,
                cols: cols)
        else {
            return TerminalInteractiveHandle(
                events: AsyncStream { continuation in
                    continuation.yield(
                        .launchFailed(String(localized: "The shell could not be started.")))
                    continuation.finish()
                },
                acknowledgeOutput: {},
                writeBytes: { _ in },
                resize: { _, _ in },
                interrupt: {},
                terminate: {},
                hasChildProcesses: { false })
        }

        let credits = TerminalOutputCredits(limit: maxQueuedOutputChunks)
        let writer = TerminalInputWriter(terminal: terminal)
        let events = AsyncStream<TerminalInteractiveEvent> { continuation in
            continuation.onTermination = { _ in credits.cancel() }
            queue.async {
                drainInteractive(terminal, writer: writer, credits: credits, into: continuation)
            }
        }

        return TerminalInteractiveHandle(
            events: events,
            acknowledgeOutput: {
                credits.release()
            },
            writeBytes: { bytes in
                writer.write(bytes)
            },
            resize: { newRows, newCols in
                terminal.resize(rows: newRows, cols: newCols)
            },
            interrupt: {
                writer.write([0x03])
            },
            terminate: {
                credits.cancel()
                terminal.signalSession(SIGHUP)
                terminal.signalSession(SIGTERM)
                queue.asyncAfter(deadline: .now() + stopGrace) {
                    terminal.signalSession(SIGKILL)
                }
            },
            hasChildProcesses: {
                terminal.hasChildProcesses()
            })
    }

    nonisolated private static func drainInteractive(
        _ terminal: PseudoTerminal,
        writer: TerminalInputWriter,
        credits: TerminalOutputCredits,
        into continuation: AsyncStream<TerminalInteractiveEvent>.Continuation
    ) {
        var buffer = [UInt8](repeating: 0, count: readSize)
        var pending: [UInt8] = []
        pending.reserveCapacity(readSize)
        var lastYield = ContinuousClock().now

        func flush() {
            credits.acquire()
            continuation.yield(.output(pending))
            pending.removeAll(keepingCapacity: true)
            lastYield = ContinuousClock().now
        }

        while true {
            if !pending.isEmpty, !hasOutput(terminal.parentEnd, within: interactiveFlushInterval) {
                flush()
                continue
            }
            let count = Darwin.read(terminal.parentEnd, &buffer, readSize)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { break }
            pending.append(contentsOf: buffer[0..<count])
            if pending.count >= 32_768
                || ContinuousClock().now - lastYield >= interactiveFlushInterval
            {
                flush()
            }
        }
        if !pending.isEmpty {
            flush()
        }
        let status = terminal.wait()
        writer.close()
        continuation.yield(.exited(status: status))
        continuation.finish()
    }

    nonisolated private static func ensureZshShimDirectory() -> String? {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "termcast-zsh-v2-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        let zshenvURL = dir.appendingPathComponent(".zshenv")
        let zprofileURL = dir.appendingPathComponent(".zprofile")
        let zshrcURL = dir.appendingPathComponent(".zshrc")
        if FileManager.default.fileExists(atPath: zshrcURL.path) {
            return dir.path
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let zshenv = """
                if [[ -n "$TERMCAST_USER_ZDOTDIR" ]]; then
                  ZDOTDIR="$TERMCAST_USER_ZDOTDIR"
                else
                  unset ZDOTDIR
                fi
                if [[ "$TERMCAST_LOAD_ENV" == "1" && -f "${ZDOTDIR:-$HOME}/.zshenv" ]]; then
                  source "${ZDOTDIR:-$HOME}/.zshenv"
                fi
                ZDOTDIR="$TERMCAST_SHIM_ZDOTDIR"
                """
            let zprofile = """
                if [[ -n "$TERMCAST_USER_ZDOTDIR" ]]; then
                  ZDOTDIR="$TERMCAST_USER_ZDOTDIR"
                else
                  unset ZDOTDIR
                fi
                if [[ "$TERMCAST_LOAD_ENV" == "1" && -f "${ZDOTDIR:-$HOME}/.zprofile" ]]; then
                  source "${ZDOTDIR:-$HOME}/.zprofile"
                fi
                ZDOTDIR="$TERMCAST_SHIM_ZDOTDIR"
                """
            let zshrc = #"""
                if [[ -n "$TERMCAST_USER_ZDOTDIR" ]]; then
                  ZDOTDIR="$TERMCAST_USER_ZDOTDIR"
                else
                  unset ZDOTDIR
                fi
                export HISTFILE="${HISTFILE:-${ZDOTDIR:-$HOME}/.zsh_history}"
                HISTSIZE="${HISTSIZE:-10000}"
                SAVEHIST="${SAVEHIST:-10000}"
                __tc_default_prompt="$PROMPT"
                if [[ "$TERMCAST_LOAD_ENV" == "1" && -f "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
                  source "${ZDOTDIR:-$HOME}/.zshrc"
                else
                  autoload -Uz colors compinit && colors
                  compinit -C -d "${TMPDIR:-/tmp}/.zcompdump-termcast-$UID" 2>/dev/null
                  setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY INTERACTIVE_COMMENTS
                fi
                setopt HIST_IGNORE_SPACE
                if [[ -r "$HOME/.config/termcast/init.zsh" ]]; then
                  source "$HOME/.config/termcast/init.zsh"
                fi
                zmodload zsh/parameter 2>/dev/null
                zmodload zsh/datetime 2>/dev/null
                autoload -Uz add-zsh-hook colors && colors 2>/dev/null
                __termcast_git_segment() {
                  local dir="$PWD" gitdir="" head_line="" branch=""
                  while [[ -n "$dir" ]]; do
                    if [[ -f "$dir/.git/HEAD" ]]; then
                      gitdir="$dir/.git"
                      break
                    elif [[ -f "$dir/.git" ]]; then
                      IFS= read -r head_line < "$dir/.git" 2>/dev/null || break
                      if [[ "$head_line" == "gitdir: "* ]]; then
                        gitdir="${head_line#gitdir: }"
                        [[ "$gitdir" != /* ]] && gitdir="$dir/$gitdir"
                      fi
                      break
                    fi
                    [[ "$dir" == "/" ]] && break
                    dir="${dir:h}"
                  done
                  [[ -n "$gitdir" && -r "$gitdir/HEAD" ]] || return 0
                  IFS= read -r head_line < "$gitdir/HEAD" 2>/dev/null || return 0
                  if [[ "$head_line" == "ref: refs/heads/"* ]]; then
                    branch="${head_line#ref: refs/heads/}"
                  elif [[ "$head_line" == "ref: "* ]]; then
                    branch="${head_line##*/}"
                  else
                    branch="${head_line[1,7]}"
                  fi
                  branch="${branch//\%/%%}"
                  [[ -n "$branch" ]] && REPLY=" %F{magenta}%B⎇ ${branch}%b%f"
                }
                typeset -gi __termcast_use_spaceship=0
                typeset -gi __termcast_ran_cmd=0
                typeset -gi __termcast_has_prompted=0
                typeset -g __termcast_cmd_start=""
                typeset -g __termcast_git=""
                typeset -g __termcast_dur=""
                if [[ -z "$STARSHIP_SHELL" && -z "$SPACESHIP_VERSION" && -z "$P9K_SSH" ]]; then
                  if [[ -z "$PROMPT" || "$PROMPT" == "$__tc_default_prompt" \
                        || "$PROMPT" == "%n@%m %1~ %# " || "$PROMPT" == "%m%# " ]]; then
                    __termcast_use_spaceship=1
                    setopt PROMPT_SUBST
                    __tc_dir='%F{cyan}%B%~%b%f${__termcast_git}${__termcast_dur}'
                    __tc_sym='%(?.%F{green}%B❯%b%f.%F{red}%B❯%b%f)'
                    PROMPT="${__tc_dir} ${__tc_sym} %{"$'\033'"]133;B"$'\007'"%}"
                    unset __tc_dir __tc_sym
                  fi
                fi
                unset __tc_default_prompt
                __termcast_preexec() {
                  __termcast_ran_cmd=1
                  __termcast_cmd_start="$EPOCHREALTIME"
                  builtin printf '\033]133;C;%s\007' "${1%%$'\n'*}"
                }
                __termcast_precmd() {
                  local ec=$?
                  local bg=${#jobtexts}
                  builtin printf '\033]133;D;%d;%d\007\033]7;%s\007' "$ec" "$bg" "$PWD"
                  if (( __termcast_use_spaceship )); then
                    REPLY=""
                    __termcast_git_segment
                    __termcast_git="$REPLY"
                    __termcast_dur=""
                    if (( __termcast_ran_cmd )) && [[ -n "$__termcast_cmd_start" && -n "$EPOCHREALTIME" ]]; then
                      local -i ms=$(( (EPOCHREALTIME - __termcast_cmd_start) * 1000 ))
                      if (( ms >= 2000 )); then
                        local -i secs=$(( ms / 1000 ))
                        if (( secs >= 60 )); then
                          __termcast_dur=" %F{yellow}took $(( secs / 60 ))m $(( secs % 60 ))s%f"
                        else
                          local -i tenths=$(( (ms + 50) / 100 ))
                          __termcast_dur=" %F{yellow}took $(( tenths / 10 )).$(( tenths % 10 ))s%f"
                        fi
                      fi
                    fi
                    if (( __termcast_has_prompted && __termcast_ran_cmd )); then
                      builtin print ""
                    fi
                    __termcast_has_prompted=1
                  fi
                  __termcast_ran_cmd=0
                }
                __termcast_take_buffer() {
                  local buf="$BUFFER"
                  buf="${buf//$'\007'/}"
                  buf="${buf//$'\033'/}"
                  buf="${buf//$'\n'/ }"
                  BUFFER=""
                  CURSOR=0
                  unset POSTDISPLAY 2>/dev/null
                  builtin printf '\033]133;I;%s\007' "$buf"
                  zle -R
                }
                zle -N __termcast_take_buffer
                bindkey '\e[99~' __termcast_take_buffer
                bindkey -M emacs '\e[99~' __termcast_take_buffer 2>/dev/null
                bindkey -M viins '\e[99~' __termcast_take_buffer 2>/dev/null
                bindkey -M vicmd '\e[99~' __termcast_take_buffer 2>/dev/null
                add-zsh-hook -d preexec __termcast_preexec 2>/dev/null
                add-zsh-hook -d precmd __termcast_precmd 2>/dev/null
                add-zsh-hook preexec __termcast_preexec
                add-zsh-hook precmd __termcast_precmd
                """#
            try zshenv.write(to: zshenvURL, atomically: true, encoding: .utf8)
            try zprofile.write(to: zprofileURL, atomically: true, encoding: .utf8)
            try zshrc.write(to: zshrcURL, atomically: true, encoding: .utf8)
            return dir.path
        } catch {
            return nil
        }
    }

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
        environment["TERMCAST"] = "1"
        environment["TINYCAST"] = "1"
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["CLICOLOR"] == nil {
            environment["CLICOLOR"] = "1"
        }
        if environment["LSCOLORS"] == nil {
            environment["LSCOLORS"] = "GxFxCxDxBxegedabagaced"
        }

        let flag = loadsShellEnvironment ? "-ilc" : "-lc"
        let prelude =
            #"setopt aliases; [[ -r "$HOME/.config/termcast/init.zsh" ]] && source "$HOME/.config/termcast/init.zsh"; "#
        // fd 9 reports the shell's final directory so `cd` persists across runs in the same tab.
        let wrapper =
            hasCwdPipe
            ? prelude + #"eval "$1"; __tc_ec=$?; pwd -L >&9 2>/dev/null; exit $__tc_ec"#
            : prelude + #"eval "$1""#
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

/// Bounds the chunks waiting on the main actor: a flood pauses the shell instead of growing RAM.
final class TerminalOutputCredits: @unchecked Sendable {
    private let condition = NSCondition()
    private let limit: Int
    private var available: Int
    private var isCancelled = false

    init(limit: Int) {
        self.limit = max(limit, 1)
        self.available = self.limit
    }

    /// Blocks the reader until a chunk is acknowledged; once cancelled it never blocks again.
    func acquire() {
        condition.lock()
        defer { condition.unlock() }
        while available == 0 && !isCancelled {
            condition.wait()
        }
        if !isCancelled {
            available -= 1
        }
    }

    func release() {
        condition.lock()
        available = min(available + 1, limit)
        condition.signal()
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        isCancelled = true
        condition.broadcast()
        condition.unlock()
    }
}

/// A shell that stops reading input blocks `write`, so it must never block the main actor.
private final class TerminalInputWriter: @unchecked Sendable {
    private let terminal: PseudoTerminal
    private let queue = DispatchQueue(label: "com.tinycast.terminal-input", qos: .userInitiated)
    private var isClosed = false

    init(terminal: PseudoTerminal) {
        self.terminal = terminal
    }

    func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        queue.async { [self] in
            guard !isClosed else { return }
            terminal.writeBytes(bytes)
        }
    }

    /// Closing on the same queue keeps a late write from landing on a reused descriptor.
    func close() {
        queue.async { [self] in
            isClosed = true
            terminal.close()
        }
    }
}
