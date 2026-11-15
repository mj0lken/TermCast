# Terminal

Terminal mode lets users run interactive shell sessions and manage live PTY tabs inside the palette
without switching to an external Terminal window — and seamlessly hand off heavier workflows to
their preferred external terminal app.

The pane sits right after **Snippets** in the Settings sidebar and carries the feature switch —
**on out of the box** — alongside **Detected commands**, **Terminal look**, **External terminal**,
**Load shell environment**, **Recommended shell config**, its launcher-visibility companion, the
global **Open Terminal** shortcut, customizable in-palette **Shortcuts**, **Command History**, and
the **Recent Folders** list. Because interactive shell preferences stay machine-local,
`terminalEnabled` and its companion keys are excluded from native settings backups.

## Invariants

- **Every file under `Features/Terminal/Model/` stays free of AppKit and SwiftUI**
  (`TerminalEmulator`, `TerminalCommandDetector`, `TerminalDetectionBehavior`,
  `TerminalCommandHistory`, `TerminalShortcuts`, `ExternalTerminalApp`, `TerminalTabCompleter`,
  `TerminalColorTheme`, `TerminalShellConfig`, `RecentFolders`, `TerminalTabState`) so
  `TerminalTests` compiles them standalone alongside `Service/TerminalSessionRunner.swift`.
- **Calculator and color cards win unless the query starts with `>`.** `2 + 2` or `#FF5733` stays a
  calculator or color match; `> 2 + 2` explicitly enters Terminal mode.
- **Repeated folder cycling does not mutate MRU order.** Cycling walks `recentFolders` in place so
  repeated presses visit every recent directory; MRU promotion happens only when a command runs or a
  directory is chosen from the folder dialog.
- **Command history stays local to this Mac.** `terminalCommandHistory` is persisted in
  `UserDefaults` (capped at 500 deduplicated entries, newest first) and excluded from both native
  settings backups and `settings.json`.
- **Disabling Terminal closes all active tabs and stops running sessions.**
  `TerminalCoordinator.applyEnabled()` cancels any `PATH` scan, terminates open PTYs, unpins the
  launcher folder strip, and replaces `.terminal` with `.launcher`.

## Standard, Hybrid, and Terminal Modes

When `terminalEnabled` is on, Termcast operates across three distinct modes:

1. **Standard Mode** (`PaletteMode.launcher` without Hybrid Mode): Normal Termcast search for apps,
   commands, calculator expressions, colors, and files.
2. **Hybrid Mode** (`TerminalCoordinator.isHybridModeActive`): Top command input bar stays focused
   (monospaced `"Enter a shell command…"`, `apple.terminal` icon, `Terminal Mode ⌘I` chip, `↑`/`↓`
   command history, `⇥` path/command completion) with `TerminalFolderStrip` (`Select Folder…` at
   row 0 of the searchable `Working Directory` menu) and the live `TerminalPanelContentView`
   (tabs + live PTY output, `interactiveFocusEnabled: false`) rendered immediately below — never
   mixing in launcher app/command rows.
   - Entered explicitly via **`⌘T`** (`toggleTerminalMode`), typing **`>`** at the start of Standard
     Mode, returning from Terminal Mode with **`⌘I`**, or automatically as soon as Standard Mode
     interprets a typed query as a shell command (`TerminalDetectionBehavior.topResult`, default
     `"Show in Hybrid Mode"`).
   - Pressing **`↵`** (`Run Command`) or **`⇧↵` / `⌘↵`** (`Run in New Tab`) executes the command in
     the live PTY tab below while **keeping the user in Hybrid Mode** with the top input bar cleared
     and ready for the next command.
   - Pressing **`⌘T`**, **`⌫`**, or **`Esc`** on an empty Hybrid Mode input returns to Standard
     Mode (`⌘T` on an auto-detected query suppresses Hybrid auto-detection for that query so app
     matches remain reachable).
3. **Terminal Mode** (`PaletteMode.terminal` — or automatically on command detection when
   `TerminalDetectionBehavior.openTerminal` is selected): Full interactive `/bin/zsh` PTY screen
   where `InteractiveTerminalView` (`TerminalSurfaceNSView`) owns keyboard focus directly for native
   `zsh` `Tab` completion, interactive prompts, `Ctrl+C`, and full-screen TUIs (`vim`, `less`,
   `htop`, `fzf`).

## Interactive PTY handoff (`⌘I`), copy latest output (`⇧⌘C`), external handoff (`⌘O`), and shell integration

- **Bidirectional `⌘I` handoff (Hybrid Mode ↔ Terminal Mode)**: Pressing `⌘I` in Standard or Hybrid
  Mode enters **Terminal Mode**, focuses `InteractiveTerminalView`, and drops any typed text onto
  the live `/bin/zsh` prompt. Pressing `⌘I` inside **Terminal Mode** lifts any unexecuted command
  from the idle `zsh` prompt line (clearing `$BUFFER` via `OSC 133;I;<buffer>` paired with
  synchronous `TerminalEmulator.currentPromptInput()`) and returns to **Hybrid Mode** carrying that
  input.
- **Copy Latest Output (`⇧⌘C` — `copyLastOutput`)**: Works identically in **both Hybrid Mode and
  Terminal Mode**. `TerminalEmulator.latestCommandOutput()` uses `OSC 133;C` / `OSC 133;D` markers
  (stripping `zsh`'s inverse `%` `PROMPT_SP` end-of-line mark when output lacks a trailing newline)
  to copy only the most recent command's output without surrounding shell prompts; dragging to
  select text in the terminal canvas + `⌘C` also works in both Hybrid and Terminal Mode, and `Copy
  All Output` is available in `⌘K`.
- **Active sessions badge & close confirmation**: Whenever open tabs have live shells
  (`TerminalStore.sessionSummary.showsBadge`), `TerminalActiveSessionsBadge` appears in both the
  compact and expanded input bars: tabs with a running command, background job, or TUI
  (`activeCount > 0`) display a glowing green dot + active count, whereas purely idle shell tabs
  (`activeCount == 0`) show only a subtle dot with no number. Hovering displays a summary tooltip
  (e.g. `"2 active\n2 idle tabs"`, `"1 active tab"`, or `"2 idle tabs"`), and clicking enters
  **Hybrid Mode** (selecting the running tab when one is active). Closing a tab or all tabs prompts
  via `DialogController` (`AppCore.confirm`) only when an active command/process is running; idle
  and exited tabs close immediately.
- **Continue in External Terminal (`⌘O`)**: Available via `⌘O` and the `⌘K` Actions menu (never
  crowding the top header bar, which shows only `Terminal Mode ⌘I` / `Hybrid Mode ⌘I`).
  `ExternalTerminalLauncher` auto-detects installed terminals (**Ghostty**, **iTerm2**, **Warp**,
  **kitty**, **Alacritty**, **WezTerm**, and **macOS Terminal**; configurable via
  `terminal.externalApp`) and hands off both the active working directory and any typed command.
- **Spaceship prompt & shell integration (`OSC 7` & `OSC 133`)**: `TerminalSessionRunner.startInteractive`
  installs a lightweight `ZDOTDIR` trampoline that restores the user's `ZDOTDIR`, loads `~/.zshenv`
  / `~/.zprofile` / `~/.zshrc` when enabled, sources `~/.config/termcast/init.zsh` if present,
  provides a fast zero-fork **Spaceship** Zsh prompt (`~/path ⎇ branch ❯ `, exit-code colored `❯`,
  and `took Ns` elapsed time for commands ≥ 2s) whenever the user's `.zshrc` leaves `$PROMPT` at the
  stock macOS default, and registers `preexec`/`precmd` hooks plus a `zle` prompt-buffer handoff
  widget reporting working directory changes (`OSC 7`), command execution/background job state
  (`OSC 133;C`/`D`), and lifted prompt buffers (`OSC 133;I`) back to `TerminalTab` and
  `TerminalFolderStrip`.
- **Customizable shortcuts (`terminal.shortcuts` in `settings.json`)**: Customizes all ten
  in-palette chords — `toggleTerminalMode` (`⌘T`), `switchToTerminal` (`⌘I`), `copyLastOutput`
  (`⇧⌘C`), `openExternalTerminal` (`⌘O`), `runInTerminal` (`⇧↵`), `cycleFolder` (`⇧⇥`), `newTab`
  (`⌘N`), `closeTab` (`⌃X`), `stopCommand` (`⌘.`), and `clearOutput` (`⌘⌫`) — with Hyper Key (`✦`)
  support.

## VT100 / xterm emulation, color themes, and `init.zsh`

- **Grid & alternate screen (`TerminalEmulator` + `InteractiveTerminalView`)**: Pure-Swift VT100 /
  xterm emulator storing cells as 16-byte packed values (`TerminalCell`, with a sparse per-line
  grapheme-cluster side table) and scrollback (`4,000` lines) in `128 KB+` flat slabs
  (`TerminalScrollbackBuffer`) so macOS unmaps freed pages directly when tabs close or scrollback
  clears. Supports alternate screen (`?1049h`),
  deferred right-margin wrap (`?7h`), DEC line-drawing graphics, cursor save/restore, `DECSTBM`
  scroll regions, `TIOCSWINSZ` dynamic resizing, bracketed paste (`?2004h`), mouse text selection,
  and 16-color / 256-color / 24-bit TrueColor rendering across four curated looks
  (`terminal.colorTheme`: **Default** native translucent glass, plus one light look — **Paper** —
  and two darker looks — **Slate** and **Midnight** — each with tailored surface, chrome, and text
  palettes).
- **Readability defaults & `~/.config/termcast/init.zsh`**: `TerminalSessionRunner` sets
  `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERMCAST=1`, and `CLICOLOR=1` out of the box, and
  automatically sources `~/.config/termcast/init.zsh` if present (`TerminalShellConfig` generates a
  fast recommended config from **Settings → Terminal** without Oh My Zsh startup overhead).
