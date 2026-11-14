import Darwin
import Foundation

@main
struct TerminalTests {
    @MainActor
    static func main() async throws {
        // Detach any inherited controlling tty so interactive shells never stall on SIGTTOU.
        setsid()

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // MARK: - Command Detector

        let executables: Set<String> = ["ffmpeg", "sqlite3", "rg", "git", "cal", "mail"]

        check(
            "prefix strips leading >",
            TerminalCommandDetector.stripExplicitPrefix(">") == "")
        check(
            "prefix strips leading > and single space",
            TerminalCommandDetector.stripExplicitPrefix("> git status") == "git status")
        check(
            "prefix preserves subsequent spaces",
            TerminalCommandDetector.stripExplicitPrefix(">  ls -la") == " ls -la")
        check(
            "non-prefixed query returns nil from stripExplicitPrefix",
            TerminalCommandDetector.stripExplicitPrefix("git status") == nil)

        check(
            "explicit prefix matches even when empty",
            TerminalCommandDetector.detect("> ", executables: executables) == .prefix(""))
        check(
            "explicit prefix overrides calculator deferral",
            TerminalCommandDetector.detect(
                "> 2 + 2", executables: executables, hasCalculatorOrColorMatch: true)
                == .prefix("2 + 2"))
        check(
            "calculator match suppresses implicit command detection",
            TerminalCommandDetector.detect(
                "2 + 2", executables: executables, hasCalculatorOrColorMatch: true) == nil)
        check(
            "unambiguous CLI verb matches as single word",
            TerminalCommandDetector.detect("pwd", executables: executables) == .detected("pwd"))
        check(
            "unambiguous CLI verb matches with arguments",
            TerminalCommandDetector.detect("git status -sb", executables: executables)
                == .detected("git status -sb"))
        check(
            "PATH executable requires trailing space or arguments",
            TerminalCommandDetector.detect("ffmpeg", executables: executables) == nil
                && TerminalCommandDetector.detect("ffmpeg ", executables: executables)
                    == .detected("ffmpeg")
                && TerminalCommandDetector.detect("ffmpeg -i in.mp4", executables: executables)
                    == .detected("ffmpeg -i in.mp4"))
        check(
            "relative and home path invocations match",
            TerminalCommandDetector.detect("./Scripts/lint.sh", executables: executables)
                == .detected("./Scripts/lint.sh")
                && TerminalCommandDetector.detect("~/bin/deploy", executables: executables)
                    == .detected("~/bin/deploy")
                && TerminalCommandDetector.detect("/usr/bin/env", executables: executables)
                    == .detected("/usr/bin/env"))
        check(
            "leading environment assignment matches when followed by command",
            TerminalCommandDetector.detect("FOO=bar node server.js", executables: executables)
                == .detected("FOO=bar node server.js"))
        check(
            "shell pipelines and logical operators match",
            TerminalCommandDetector.detect("cat file.txt | wc -l", executables: executables)
                == .detected("cat file.txt | wc -l")
                && TerminalCommandDetector.detect("mkdir sub && cd sub", executables: executables)
                    == .detected("mkdir sub && cd sub"))
        check(
            "ordinary app searches and URLs do not match",
            TerminalCommandDetector.detect("Safari", executables: executables) == nil
                && TerminalCommandDetector.detect("Calendar", executables: executables) == nil
                && TerminalCommandDetector.detect("cal", executables: executables) == nil
                && TerminalCommandDetector.detect("mail", executables: executables) == nil
                && TerminalCommandDetector.detect("https://example.com", executables: executables)
                    == nil)

        // MARK: - Recent Folders

        let home = "/Users/tester"
        check(
            "normalize expands tilde and trims trailing slash",
            RecentFolders.normalize("~/Projects/tinycast/", homeDirectory: home)
                == "/Users/tester/Projects/tinycast")
        check(
            "empty folder normalizes to home",
            RecentFolders.normalize("   ", homeDirectory: home) == home)
        check(
            "displayPath abbreviates home and descendants",
            RecentFolders.displayPath(home, homeDirectory: home) == "~"
                && RecentFolders.displayPath(home + "/Projects/tinycast", homeDirectory: home)
                    == "~/Projects/tinycast"
                && RecentFolders.displayPath("/tmp/work", homeDirectory: home) == "/tmp/work")
        check(
            "shortName shows ~ for home and basename otherwise",
            RecentFolders.shortName(home, homeDirectory: home) == "~"
                && RecentFolders.shortName("/", homeDirectory: home) == "/"
                && RecentFolders.shortName(home + "/Projects/tinycast", homeDirectory: home)
                    == "tinycast")

        var mru = [home, home + "/Projects", home + "/Downloads"]
        mru = RecentFolders.record("~/Downloads/", in: mru, homeDirectory: home)
        check(
            "record promotes matching folder to front without duplicates",
            mru == [home + "/Downloads", home, home + "/Projects"])
        let capped = RecentFolders.record(
            "/tmp/a", in: [home, home + "/Projects", home + "/Downloads"],
            homeDirectory: home, maxCount: 2)
        check("record honors maxCount", capped == ["/tmp/a", home])

        let cycleOrder = [home, home + "/Projects", home + "/Downloads"]
        let step1 = RecentFolders.cycle(from: home, in: cycleOrder, homeDirectory: home)
        let step2 = RecentFolders.cycle(from: step1, in: cycleOrder, homeDirectory: home)
        let step3 = RecentFolders.cycle(from: step2, in: cycleOrder, homeDirectory: home)
        check(
            "cycle walks forward and wraps without mutating folder order",
            step1 == home + "/Projects" && step2 == home + "/Downloads" && step3 == home)
        let back = RecentFolders.cycle(
            from: home, in: cycleOrder, reverse: true, homeDirectory: home)
        check("reverse cycle wraps to last folder", back == home + "/Downloads")

        let seeded = RecentFolders.seeded(
            stored: [],
            homeDirectory: home,
            currentDirectory: home + "/Projects",
            directoryExists: { $0 == home || $0 == home + "/Projects" })
        check(
            "seeded filters to existing directories in priority order",
            seeded == [home + "/Projects", home])

        // MARK: - Tab Formatting

        check(
            "tab title falls back to folder shortName when idle",
            TerminalTabFormatting.title(
                lastCommand: nil, workingDirectory: home + "/Projects/tinycast", homeDirectory: home
            ) == "tinycast")
        check(
            "tab title truncates long commands with ellipsis",
            TerminalTabFormatting.title(
                lastCommand: "xcodebuild -project Tinycast.xcodeproj -scheme Tinycast",
                workingDirectory: home,
                homeDirectory: home
            ).count == 24)
        check(
            "zero exit footer omits error banner",
            TerminalTabFormatting.exitFooter(status: 0) == "\n"
                && TerminalTabFormatting.exitFooter(status: 127).contains("[exit 127]"))

        let oversized =
            String(repeating: "a", count: 70_000) + "\n"
            + String(repeating: "b", count: TerminalTabFormatting.maxLogScalarCount)
        let trimmed = TerminalTabFormatting.trimLogIfNeeded(oversized)
        check(
            "oversized log trims cleanly at newline boundary",
            trimmed.didTrim && trimmed.trimmed.first == "b")

        // MARK: - PTY Session Runner

        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-terminal-tests-\(UUID().uuidString)")
        let nested = sandbox.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let echoResult = await collect(
            TerminalSessionRunner.start(
                command: "printf 'hello-termcast'",
                workingDirectory: sandbox.path,
                loadsShellEnvironment: false))
        check(
            "runner streams stdout and exits 0",
            echoResult.output.contains("hello-termcast")
                && echoResult.termination == .exited(status: 0))

        let cdResult = await collect(
            TerminalSessionRunner.start(
                command: "cd nested && printf 'moved'",
                workingDirectory: sandbox.path,
                loadsShellEnvironment: false))
        let resolvedNested = nested.resolvingSymlinksInPath().path
        let reportedNested = cdResult.updatedDirectory.map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
        }
        check(
            "runner reports updated working directory across cd",
            cdResult.output.contains("moved") && reportedNested == resolvedNested)

        let stdinHandle = TerminalSessionRunner.start(
            command: "read line && printf 'got:%s' \"$line\"",
            workingDirectory: sandbox.path,
            loadsShellEnvironment: false)
        stdinHandle.sendInput("interactive-ok")
        let stdinResult = await collect(stdinHandle)
        check(
            "runner forwards live stdin to running process",
            stdinResult.output.contains("got:interactive-ok")
                && stdinResult.termination == .exited(status: 0))

        let stopHandle = TerminalSessionRunner.start(
            command: "sleep 30",
            workingDirectory: sandbox.path,
            loadsShellEnvironment: false)
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            stopHandle.stop()
        }
        let stopResult = await collect(stopHandle)
        check("stop terminates running session cleanly", stopResult.termination == .stopped)

        let missingResult = await collect(
            TerminalSessionRunner.start(
                command: "pwd",
                workingDirectory: sandbox.appendingPathComponent("does-not-exist").path,
                loadsShellEnvironment: false))
        var missingFailed = false
        if case .launchFailed = missingResult.termination { missingFailed = true }
        check("missing working directory fails immediately", missingFailed)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        Foundation.exit(failures == 0 ? 0 : 1)
    }

    private struct RunSummary {
        var output = ""
        var termination: ShellCommandTermination?
        var updatedDirectory: String?
    }

    private static func collect(_ handle: TerminalRunHandle) async -> RunSummary {
        var summary = RunSummary()
        for await event in handle.events {
            switch event {
            case .output(let chunk):
                summary.output.append(chunk)
            case .finished(let termination, let updatedDirectory):
                summary.termination = termination
                summary.updatedDirectory = updatedDirectory
            }
        }
        return summary
    }
}
