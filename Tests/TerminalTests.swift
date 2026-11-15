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
            "zero exit footer omits error banner and shows duration only on longer runs",
            TerminalTabFormatting.exitFooter(status: 0, elapsedMilliseconds: 40) == "\n"
                && TerminalTabFormatting.exitFooter(status: 0, elapsedMilliseconds: 1_200)
                    .contains("✓ 1.2s")
                && TerminalTabFormatting.exitFooter(status: 127, elapsedMilliseconds: 85)
                    .contains("✗ exit 127"))

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

        // MARK: - Command History & Prefix-Filtered Navigator

        var history: [String] = []
        history = TerminalCommandHistory.record("echo first", in: history)
        history = TerminalCommandHistory.record("git status", in: history)
        history = TerminalCommandHistory.record("ls -la", in: history)
        history = TerminalCommandHistory.record("git diff --staged", in: history)
        history = TerminalCommandHistory.record("   ", in: history)
        check(
            "record stores newest first and ignores blank commands",
            history == ["git diff --staged", "ls -la", "git status", "echo first"])

        history = TerminalCommandHistory.record("  git status  ", in: history)
        check(
            "record deduplicates and promotes existing command to newest",
            history == ["git status", "git diff --staged", "ls -la", "echo first"])

        let cappedHistory = TerminalCommandHistory.record("pwd", in: history, limit: 3)
        check(
            "record enforces history cap",
            cappedHistory == ["pwd", "git status", "git diff --staged"])

        check(
            "sanitized trims, deduplicates, and drops empty entries",
            TerminalCommandHistory.sanitized([" a ", "", "b", "a", "c"], limit: 2) == ["a", "b"])

        var nav = TerminalHistoryNavigator()
        check(
            "stepping newer when idle is inactive",
            nav.stepNewer() == .inactive && !nav.isBrowsing)
        check(
            "empty prompt steps through all commands newest to oldest",
            nav.stepOlder(currentInput: "", history: history) == .updated("git status")
                && nav.stepOlder(currentInput: "git status", history: history)
                    == .updated("git diff --staged")
                && nav.stepOlder(currentInput: "git diff --staged", history: history)
                    == .updated("ls -la")
                && nav.stepOlder(currentInput: "ls -la", history: history)
                    == .updated("echo first")
                && nav.stepOlder(currentInput: "echo first", history: history) == .boundary)
        check(
            "stepping newer walks back and restores empty draft at prompt",
            nav.stepNewer() == .updated("ls -la")
                && nav.stepNewer() == .updated("git diff --staged")
                && nav.stepNewer() == .updated("git status")
                && nav.stepNewer() == .updated("")
                && !nav.isBrowsing)

        var prefixNav = TerminalHistoryNavigator()
        check(
            "prefix navigation filters matching commands and restores typed prefix",
            prefixNav.stepOlder(currentInput: "git", history: history) == .updated("git status")
                && prefixNav.stepOlder(currentInput: "git status", history: history)
                    == .updated("git diff --staged")
                && prefixNav.stepOlder(currentInput: "git diff --staged", history: history)
                    == .boundary
                && prefixNav.stepNewer() == .updated("git status")
                && prefixNav.stepNewer() == .updated("git")
                && !prefixNav.isBrowsing)

        prefixNav.reset()
        check(
            "unmatched prefix leaves navigator inactive",
            prefixNav.stepOlder(currentInput: "cargo", history: history) == .inactive
                && !prefixNav.isBrowsing)

        // MARK: - Terminal Shortcuts & Detection Behavior

        let defaults = TerminalShortcuts.defaults
        check(
            "default shortcuts match documented chords",
            defaults.chord(for: .toggleTerminalMode)?.inlineDisplay() == "⌘T"
                && defaults.chord(for: .switchToTerminal)?.inlineDisplay() == "⌘I"
                && defaults.chord(for: .copyLastOutput)?.inlineDisplay() == "⇧⌘C"
                && defaults.chord(for: .openExternalTerminal)?.inlineDisplay() == "⌘O"
                && defaults.chord(for: .runInTerminal)?.inlineDisplay() == "⇧↵"
                && defaults.chord(for: .cycleFolder)?.inlineDisplay() == "⇧⇥"
                && defaults.chord(for: .newTab)?.inlineDisplay() == "⌘N"
                && defaults.chord(for: .closeTab)?.inlineDisplay() == "⌃X"
                && defaults.chord(for: .stopCommand)?.inlineDisplay() == "⌘."
                && defaults.chord(for: .clearOutput)?.inlineDisplay() == "⌘⌫")

        check(
            "launcher only matches launcher-eligible terminal shortcuts",
            defaults.matchedAction(
                for: TerminalShortcutAction.toggleTerminalMode.defaultChord, inLauncher: true)
                == .toggleTerminalMode
                && defaults.matchedAction(
                    for: TerminalShortcutAction.switchToTerminal.defaultChord, inLauncher: true)
                    == .switchToTerminal
                && defaults.matchedAction(
                    for: TerminalShortcutAction.openExternalTerminal.defaultChord, inLauncher: true)
                    == .openExternalTerminal
                && defaults.matchedAction(
                    for: TerminalShortcutAction.copyLastOutput.defaultChord, inLauncher: true) == nil
                && defaults.matchedAction(
                    for: TerminalShortcutAction.copyLastOutput.defaultChord, inLauncher: false)
                    == .copyLastOutput
                && defaults.matchedAction(
                    for: TerminalShortcutAction.newTab.defaultChord, inLauncher: true) == nil
                && defaults.matchedAction(
                    for: TerminalShortcutAction.newTab.defaultChord, inLauncher: false) == .newTab)

        check(
            "reserved and unmodified printable chords are rejected",
            TerminalKeyChord(text: "t") == nil
                && TerminalKeyChord(text: "shift+t") == nil
                && TerminalKeyChord(text: "cmd+c") == nil
                && TerminalKeyChord(text: "cmd+v") == nil
                && TerminalKeyChord(text: "cmd+k") == nil
                && TerminalKeyChord(text: "cmd+1") == nil
                && TerminalKeyChord(text: "f5")?.inlineDisplay() == "F5"
                && TerminalKeyChord(text: "cmd+plus")?.inlineDisplay() == "⌘+")

        let hyperChord = TerminalKeyChord(text: "ctrl+opt+shift+cmd+t")
        check(
            "hyper chord collapses to hyper glyph when configured",
            hyperChord?.inlineDisplay(hyperIncludesShift: true) == "✦T"
                && hyperChord?.inlineDisplay(hyperIncludesShift: nil) == "⌃⌥⇧⌘T")

        var customized = defaults.setting(nil, for: .closeTab)
        customized = customized.setting(TerminalKeyChord(text: "ctrl+t"), for: .switchToTerminal)
        check(
            "conflict prevents binding two actions to the same chord",
            customized.conflict(
                for: TerminalShortcutAction.newTab.defaultChord, excluding: .clearOutput) == .newTab)
        let encodedShortcuts = try JSONEncoder().encode(customized)
        let decodedShortcuts = try JSONDecoder().decode(
            TerminalShortcuts.self, from: encodedShortcuts)
        check(
            "customized shortcuts round-trip through JSON with cleared bindings preserved",
            decodedShortcuts == customized
                && decodedShortcuts.chord(for: .closeTab) == nil
                && decodedShortcuts.chord(for: .switchToTerminal)?.inlineDisplay() == "⌃T")

        check(
            "detection behavior raw values stay stable",
            TerminalDetectionBehavior.topResult.rawValue == "topResult"
                && TerminalDetectionBehavior.openTerminal.rawValue == "openTerminal")

        // MARK: - External Terminal Handoff

        check(
            "automatic external terminal prefers Ghostty over Terminal.app when installed",
            ExternalTerminalApp.resolve(
                preference: .automatic,
                installedBundleIDs: ["com.apple.Terminal", "com.mitchellh.ghostty"]) == .ghostty)
        check(
            "explicit external terminal preference wins when installed and falls back otherwise",
            ExternalTerminalApp.resolve(
                preference: .warp,
                installedBundleIDs: ["com.apple.Terminal", "dev.warp.Warp-Stable", "com.mitchellh.ghostty"])
                == .warp
                && ExternalTerminalApp.resolve(
                    preference: .iterm2,
                    installedBundleIDs: ["com.apple.Terminal"]) == .appleTerminal)
        let handoff = ExternalTerminalApp.handoffScript(
            command: "git commit -m 'fix it'",
            workingDirectory: "/Users/test/My Project",
            displayDirectory: "~/My Project")
        check(
            "handoff script safely quotes single quotes, spaces, and drops into interactive zsh",
            handoff.contains("cd -- '/Users/test/My Project'")
                && handoff.contains("'git commit -m '\\''fix it'\\'''")
                && handoff.contains(#"exec "${SHELL:-/bin/zsh}" -il"#))
        check(
            "direct launch arguments pass working directory and shell command for kitty",
            ExternalTerminalApp.kitty.directLaunchArguments(
                workingDirectory: "/tmp/work", command: "htop").starts(
                    with: ["--directory", "/tmp/work", "/bin/zsh", "-ilc"]))

        // MARK: - Tab Completion & Cycling Session

        let fakeFS: [String: [TerminalCompletionEntry]] = [
            "/work": [
                TerminalCompletionEntry(name: "Sources", isDirectory: true),
                TerminalCompletionEntry(name: "Scripts", isDirectory: true),
                TerminalCompletionEntry(name: "My Notes", isDirectory: true),
                TerminalCompletionEntry(name: "README.md", isDirectory: false),
                TerminalCompletionEntry(name: ".env", isDirectory: false)
            ],
            "/Users/test/Downloads": [
                TerminalCompletionEntry(name: "report.pdf", isDirectory: false)
            ]
        ]
        let listFake: (String) -> [TerminalCompletionEntry] = { fakeFS[$0] ?? [] }

        let cmdCompletion = TerminalTabCompleter.complete(
            input: "ghost",
            workingDirectory: "/work",
            homeDirectory: "/Users/test",
            executables: ["ghostty", "git", "grep"],
            listDirectory: listFake)
        check(
            "command position completes matching executable and appends trailing space",
            cmdCompletion?.candidates.map(\.appliedToken) == ["ghostty "])

        let gitSub = TerminalTabCompleter.complete(
            input: "git ch",
            workingDirectory: "/work",
            homeDirectory: "/Users/test",
            executables: ["git"],
            listDirectory: listFake)
        check(
            "git first argument completes matching subcommands",
            gitSub?.candidates.map(\.display) == ["checkout", "cherry-pick"])

        let cdOnlyDirs = TerminalTabCompleter.complete(
            input: "cd ",
            workingDirectory: "/work",
            homeDirectory: "/Users/test",
            executables: [],
            listDirectory: listFake)
        check(
            "cd completes directories only, hides dotfiles by default, and escapes spaces",
            cdOnlyDirs?.candidates.map(\.appliedToken) == ["My\\ Notes/", "Scripts/", "Sources/"])

        let dotfileCompletion = TerminalTabCompleter.complete(
            input: "cat .e",
            workingDirectory: "/work",
            homeDirectory: "/Users/test",
            executables: ["cat"],
            listDirectory: listFake)
        check(
            "dotfile prefix reveals hidden files",
            dotfileCompletion?.candidates.map(\.appliedToken) == [".env "])

        let homeCompletion = TerminalTabCompleter.complete(
            input: "open ~/Downloads/rep",
            workingDirectory: "/work",
            homeDirectory: "/Users/test",
            executables: ["open"],
            listDirectory: listFake)
        check(
            "tilde path completion preserves ~/ prefix",
            homeCompletion?.candidates.map(\.appliedToken) == ["~/Downloads/report.pdf "])

        var session = TerminalCompletionSession()
        let firstTab = session.step(currentInput: "cd S", backwards: false) { input in
            TerminalTabCompleter.complete(
                input: input,
                workingDirectory: "/work",
                homeDirectory: "/Users/test",
                executables: [],
                listDirectory: listFake)
        }
        let secondTab = session.step(currentInput: "cd Scripts/", backwards: false) { _ in nil }
        let backTab = session.step(currentInput: "cd Sources/", backwards: true) { _ in nil }
        check(
            "completion session cycles forward and backward across candidates",
            firstTab == .cycling("cd Scripts/")
                && secondTab == .cycling("cd Sources/")
                && backTab == .cycling("cd Scripts/")
                && session.isActive)

        // MARK: - Color Themes, Git Header Formatting, and Shell Config

        check(
            "terminal provides Default plus one light look and two darker looks",
            TerminalColorTheme.allCases == [.standard, .paper, .slate, .midnight]
                && TerminalColorTheme.standard.surfaceBackground == nil
                && TerminalColorTheme.standard.chromeColors == nil
                && TerminalColorTheme.standard.overridesIsDark == nil
                && TerminalColorTheme.paper.overridesIsDark == false
                && TerminalColorTheme.slate.overridesIsDark == true
                && TerminalColorTheme.midnight.overridesIsDark == true)
        let luma: (TerminalRGB) -> Int = { Int($0.r) * 299 + Int($0.g) * 587 + Int($0.b) * 114 }
        let paperBg = TerminalColorTheme.paper.surfaceBackground!
        let slateBg = TerminalColorTheme.slate.surfaceBackground!
        let midnightBg = TerminalColorTheme.midnight.surfaceBackground!
        check(
            "extra styles supply distinct surfaces and tailored text and chrome colors",
            luma(midnightBg) < luma(slateBg)
                && luma(slateBg) < luma(paperBg)
                && luma(TerminalColorTheme.paper.palette(isDark: false).foreground) < luma(paperBg)
                && luma(TerminalColorTheme.slate.palette(isDark: true).foreground) > luma(slateBg)
                && luma(TerminalColorTheme.midnight.palette(isDark: true).foreground) > luma(midnightBg)
                && TerminalColorTheme.paper.chromeColors != nil
                && TerminalColorTheme.slate.chromeColors != nil
                && TerminalColorTheme.midnight.chromeColors != nil
                && Set([
                    TerminalColorTheme.paper.palette(isDark: false).foreground,
                    TerminalColorTheme.slate.palette(isDark: true).foreground,
                    TerminalColorTheme.midnight.palette(isDark: true).foreground
                ]).count == 3)
        check(
            "resolve maps unset and legacy theme raw values cleanly",
            TerminalColorTheme.resolve(stored: nil) == .standard
                && TerminalColorTheme.resolve(stored: "default") == .standard
                && TerminalColorTheme.resolve(stored: "adaptive") == .standard
                && TerminalColorTheme.resolve(stored: "spaceship") == .standard
                && TerminalColorTheme.resolve(stored: "daylight") == .paper
                && TerminalColorTheme.resolve(stored: "tokyoNight") == .midnight
                && TerminalColorTheme.resolve(stored: "obsidian") == .midnight
                && TerminalColorTheme.resolve(stored: "ghostty") == .midnight)
        for theme in TerminalColorTheme.allCases {
            check(
                "\(theme.rawValue) supplies 16 ANSI colors in light and dark",
                theme.palette(isDark: false).ansi.count == 16
                    && theme.palette(isDark: true).ansi.count == 16)
        }
        check(
            "256-color lookup resolves cube and grayscale indices",
            TerminalColorTheme.standard.color256(196, isDark: true) == TerminalRGB(255, 0, 0)
                && TerminalColorTheme.standard.color256(232, isDark: true) == TerminalRGB(8, 8, 8))

        check(
            "parseGitHead extracts branch names and detached short SHAs",
            TerminalTabFormatting.parseGitHead("ref: refs/heads/feature/tab-complete\n")
                == "feature/tab-complete"
                && TerminalTabFormatting.parseGitHead("a1b2c3d4e5f67890\n") == "a1b2c3d")
        let gitHeader = TerminalTabFormatting.commandHeader(
            command: "ls -la",
            workingDirectory: "/Users/test/Projects/termcast",
            homeDirectory: "/Users/test",
            gitBranch: "main",
            hasLeadingContent: true)
        check(
            "commandHeader renders separator, shortened folder, and git branch",
            gitHeader.contains("~/Projects/termcast")
                && gitHeader.contains("⎇ main")
                && gitHeader.contains("───"))
        check(
            "duration formatting scales across milliseconds, seconds, and minutes",
            TerminalTabFormatting.formatDuration(milliseconds: 42) == "42ms"
                && TerminalTabFormatting.formatDuration(milliseconds: 1_420) == "1.4s"
                && TerminalTabFormatting.formatDuration(milliseconds: 75_000) == "1m 15s")

        let tempHome = sandbox.appendingPathComponent("fake-home", isDirectory: true)
        let configURL = try TerminalShellConfig.ensureRecommendedConfig(homeDirectory: tempHome.path)
        check(
            "ensureRecommendedConfig writes ~/.config/termcast/init.zsh",
            TerminalShellConfig.exists(homeDirectory: tempHome.path)
                && ((try? String(contentsOf: configURL, encoding: .utf8))?.contains("CLICOLOR=1")
                    ?? false))
        try "# custom\n".write(to: configURL, atomically: true, encoding: .utf8)
        _ = try TerminalShellConfig.ensureRecommendedConfig(
            homeDirectory: tempHome.path, overwrite: false)
        check(
            "ensureRecommendedConfig preserves existing user config when overwrite is false",
            (try? String(contentsOf: configURL, encoding: .utf8)) == "# custom\n")

        // MARK: - VT100 / Xterm Emulator & Interactive PTY Session

        let emu = TerminalEmulator(cols: 20, rows: 5)
        emu.feed(
            "\u{1B}[1m\u{1B}[7m%\u{1B}[27m\u{1B}[0m"
            + String(repeating: " ", count: 19)
            + "\r \r$ ls -a")
        check(
            "deferred wrap lets zsh PROMPT_SP overwrite percent sign on same row",
            emu.cursorRow == 0
                && emu.plainText(includeScrollback: false) == "$ ls -a")

        emu.feed("\u{08}\u{08}\u{1B}[K-la")
        check(
            "backspace and EL erase-to-end edit line in place",
            emu.plainText(includeScrollback: false) == "$ ls -la")

        emu.feed("\r\n\u{1B}[38;2;255;128;64;1mcolored\u{1B}[0m")
        check(
            "truecolor and bold SGR attributes populate grid cells",
            emu.grid[1].cells[0].foreground == .rgb(255, 128, 64)
                && emu.grid[1].cells[0].style.contains(.bold))

        emu.feed("\u{1B}[?1049h\u{1B}[2;4HVIM\u{1B}[?1049l")
        check(
            "alternate screen isolates TUI drawing and restores primary buffer on exit",
            !emu.isAlternateScreen
                && emu.plainText(includeScrollback: false).contains("$ ls -la")
                && !emu.plainText(includeScrollback: false).contains("VIM"))

        emu.feed("\u{1B}[6n")
        let replies = emu.takePendingResponses()
        check(
            "CSI 6n queues cursor position report back to PTY",
            replies.count == 1
                && (String(bytes: replies[0], encoding: .utf8) ?? "").hasPrefix("\u{1B}["))

        emu.feed("\u{1B}]7;file://macbook/Users/test/My%20Folder\u{07}\u{1B}]133;C;git status\u{07}\u{1B}]133;D;0\u{07}")
        let shellEvents = emu.takeShellEvents()
        check(
            "OSC 7 and OSC 133 emit directory and command lifecycle events",
            emu.reportedDirectory == "/Users/test/My Folder"
                && shellEvents == [
                    .directoryChanged("/Users/test/My Folder"),
                    .commandStarted("git status"),
                    .commandFinished(0)
                ])

        let fakeGitDir = sandbox.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeGitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/spaceship-check\n".write(
            to: fakeGitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let interactive = TerminalSessionRunner.startInteractive(
            workingDirectory: sandbox.path,
            homeDirectory: tempHome.path,
            loadsShellEnvironment: false,
            rows: 24,
            cols: 80)
        let interactiveEmu = TerminalEmulator(cols: 80, rows: 24)
        var capturedPromptBuffer: String?
        var step = 0
        for await event in interactive.events {
            switch event {
            case .output(let bytes):
                interactiveEmu.feed(bytes)
                for resp in interactiveEmu.takePendingResponses() {
                    interactive.writeBytes(resp)
                }
                for shellEvent in interactiveEmu.takeShellEvents() {
                    if case .promptInputCaptured(let text) = shellEvent {
                        capturedPromptBuffer = text
                    }
                }
                if step == 0 && interactiveEmu.bracketedPaste {
                    step = 1
                    interactive.writeText("cd nested && printf 'PTY_OK'\r")
                } else if step == 1
                    && interactiveEmu.plainText().contains("PTY_OK")
                    && interactiveEmu.bracketedPaste
                {
                    step = 2
                    interactive.writeText("git status -sb\u{1B}[D\u{1B}[D\u{1B}[D")
                } else if step == 2
                    && interactiveEmu.currentPromptInput() == "git status -sb"
                {
                    step = 3
                    interactive.writeBytes(Array("\u{1B}[99~".utf8))
                } else if step == 3
                    && capturedPromptBuffer != nil
                    && interactiveEmu.currentPromptInput().isEmpty
                {
                    step = 4
                    interactive.writeText("exit\r")
                }
            case .exited, .launchFailed:
                break
            }
        }
        check(
            "interactive zsh session executes seeded input and tracks OSC 7 directory",
            interactiveEmu.plainText().contains("PTY_OK")
                && interactiveEmu.plainText().contains("⎇ spaceship-check")
                && interactiveEmu.plainText().contains("❯")
                && interactiveEmu.latestCommandOutput() == "PTY_OK"
                && interactiveEmu.reportedDirectory.map {
                    URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
                } == resolvedNested)

        let outputEmu = TerminalEmulator(cols: 80, rows: 24)
        outputEmu.feed("~/Downloads % \u{1B}]133;B\u{07}ls -a\r\n")
        outputEmu.feed("\u{1B}]133;C;ls -a\u{07}")
        outputEmu.feed("Movies\r\nProjects\r\n")
        outputEmu.feed("\u{1B}]133;D;0;0\u{07}~/Downloads % \u{1B}]133;B\u{07}")
        check(
            "latestCommandOutput isolates command output from surrounding prompts",
            outputEmu.latestCommandOutput() == "Movies\nProjects")

        outputEmu.feed("printf 'raw'\r\n\u{1B}]133;C;printf 'raw'\u{07}")
        outputEmu.feed("raw\u{1B}[7m%\u{1B}[27m\r\n")
        outputEmu.feed("\u{1B}]133;D;0;0\u{07}~/Downloads % \u{1B}]133;B\u{07}")
        check(
            "latestCommandOutput strips zsh inverse PROMPT_SP marker on no-newline output",
            outputEmu.latestCommandOutput() == "raw")

        outputEmu.feed("cd ..\r\n\u{1B}]133;C;cd ..\u{07}\u{1B}]133;D;0;0\u{07}~ % \u{1B}]133;B\u{07}")
        check(
            "silent commands preserve most recent non-empty command output",
            outputEmu.latestCommandOutput() == "raw")
        check(
            "interactive zsh session captures full edited prompt buffer on cmd+i handoff and clears prompt",
            capturedPromptBuffer == "git status -sb"
                && interactiveEmu.currentPromptInput().isEmpty)

        let mixedSummary = TerminalTabFormatting.sessionSummary(
            tabs: [
                (isAlive: true, isRunning: true),
                (isAlive: true, isRunning: true),
                (isAlive: true, isRunning: false),
                (isAlive: true, isRunning: false),
                (isAlive: false, isRunning: false)
            ])
        let idleOnlySummary = TerminalTabFormatting.sessionSummary(
            tabs: [
                (isAlive: true, isRunning: false),
                (isAlive: true, isRunning: false)
            ])
        let activeOnlySummary = TerminalTabFormatting.sessionSummary(
            tabs: [(isAlive: true, isRunning: true)])
        let emptySummary = TerminalTabFormatting.sessionSummary(
            tabs: [(isAlive: false, isRunning: false)])
        check(
            "session summary shows active numbers only for running processes and formats active/idle tooltip",
            mixedSummary.activeCount == 2
                && mixedSummary.idleCount == 2
                && mixedSummary.displayedNumber == 2
                && mixedSummary.tooltipText == "2 active\n2 idle tabs"
                && idleOnlySummary.activeCount == 0
                && idleOnlySummary.idleCount == 2
                && idleOnlySummary.showsBadge
                && idleOnlySummary.displayedNumber == nil
                && idleOnlySummary.tooltipText == "2 idle tabs"
                && activeOnlySummary.displayedNumber == 1
                && activeOnlySummary.tooltipText == "1 active tab"
                && !emptySummary.showsBadge
                && TerminalTabFormatting.requiresCloseConfirmation(isRunning: true)
                && !TerminalTabFormatting.requiresCloseConfirmation(isRunning: false))

        emu.feed("\u{1B}]133;D;0;2\u{07}")
        check(
            "OSC 133;D reports background job count for backgrounded servers",
            emu.takeShellEvents() == [
                .commandFinished(0),
                .backgroundJobCountChanged(2)
            ])

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
