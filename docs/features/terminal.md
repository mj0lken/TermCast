# Terminal

Terminal mode lets users run shell commands and manage live PTY tabs inside the palette without
switching to an external Terminal window.

The pane carries the feature switch — off out of the box — alongside **Load shell environment**,
its launcher-visibility companion, the **Open Terminal** shortcut, and the **Recent Folders** list.
Because running arbitrary shell commands from the launcher input is a capability grant,
`terminalEnabled` is excluded from both native settings backups and `settings.json`; only explicit
interaction in **Settings → Terminal** turns it on.

## Invariants

- **`Model/TerminalCommandDetector.swift`, `Model/RecentFolders.swift`, and
  `Model/TerminalTabState.swift` stay free of AppKit and SwiftUI** so `TerminalTests` compiles them
  standalone alongside `Service/TerminalSessionRunner.swift`.
- **Calculator and color cards win unless the query starts with `>`.** `2 + 2` or `#FF5733` stays a
  calculator or color match; `> 2 + 2` explicitly enters Terminal mode.
- **Repeated `⇧⇥` cycles without mutating MRU order.** Cycling walks `recentFolders` in place so
  repeated presses visit every recent directory; MRU promotion happens only when a command runs or a
  directory is chosen from the folder dialog.
- **Disabling Terminal closes all active tabs and stops running sessions.** `TerminalCoordinator.applyEnabled()`
  cancels any `PATH` scan, terminates open PTYs, unpins the launcher folder strip, and replaces
  `.terminal` with `.launcher`.

## Command detection and launcher formatting

When `terminalEnabled` is on, `TerminalCoordinator.detectLauncherCommand` inspects the root launcher
query:

- Typing `>` at the start of the launcher query transitions immediately to `PaletteMode.terminal`
  and absorbs a single trailing space typed within 750 ms (`> ` → empty Terminal prompt).
- Without `>`, `TerminalCommandDetector.detect` flags unambiguous lowercase CLI verbs (`git`, `ls`,
  `rg`, `brew`, …), shell builtins (`cd`, `pwd`, `export`, …), `<PATH executable> <args>` once
  `PathExecutableIndex` has indexed `PATH`, relative/home/root path invocations (`./`, `../`, `~/`,
  `/`), leading environment assignments (`FOO=bar cmd`), and shell pipelines/operators (`|`, `&&`,
  `||`, `;`, `$(`).
- When a command is detected in the launcher, `RootPaletteView` switches the search field to a
  monospaced font, swaps the leading search icon to `apple.terminal`, shows a `Terminal ⇧↵` hint
  chip, and reveals `TerminalFolderStrip` directly beneath the input bar.

Pressing `⇧↵` (`Shift+Return`) in the launcher runs the typed command in a Terminal tab — reusing
an idle empty tab or opening a new one — or opens the Terminal panel when the query is empty.

## Working directory and `⇧⇥`

`TerminalFolderStrip` sits directly below `headerBar` inside `RootPaletteView.header` (preserving
`headerBar` and `searchField` view identity) whenever:

- the palette is in `PaletteMode.terminal`,
- the launcher query is formatted as a command, or
- the user pressed `⇧⇥` (`Shift+Tab`) or picked a folder in the launcher (`launcherFolderPinned`).

Each tab tracks its own working directory. `TerminalSessionRunner` spawns `/bin/zsh` (`-lc` by
default, `-ilc` when **Load shell environment** is enabled) on a `PseudoTerminal` with `sendsEOF: false`
so interactive stdin lines can be sent while a command runs, and passes an extra file descriptor
(`fd 9`) that reports `pwd -L` when the command exits so `cd` persists across subsequent commands in
the same tab.
