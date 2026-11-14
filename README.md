<h1 align="center">
  <a href="https://mj0lken.github.io/TermCast/"><img src="docs/images/icon.png" alt="TermCast app icon" width="120" height="120"></a><br>
  TermCast - a TinyCast fork
</h1>

<p align="center">
  A fork that brings the full power of a native terminal directly into <a href="https://github.com/abue-ammar/tinycast">TinyCast</a>—run shell commands, cycle working folders, and manage live multi-tab PTY sessions without leaving the launcher palette.
</p>

<p align="center">
  <a href="https://mj0lken.github.io/TermCast/"><strong>Website</strong></a> ·
  <a href="https://github.com/mj0lken/TermCast/releases"><strong>Releases</strong></a> ·
  <a href="#install"><strong>Install</strong></a> ·
  <a href="docs/features/terminal.md"><strong>Terminal Docs</strong></a> ·
  <a href="https://tinycast.dev/docs/"><strong>Launcher Docs</strong></a>
</p>

<p align="center">
  <a href="https://github.com/mj0lken/TermCast/releases/latest"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/github/release/mj0lken/TermCast.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;label=RELEASE&amp;logo=lu:Tag&amp;valueColor=10B981" /><img alt="Latest release" src="https://shieldcn.dev/github/release/mj0lken/TermCast.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;label=RELEASE&amp;logo=lu:Tag&amp;valueColor=059669" /></picture></a>
  <a href="https://github.com/mj0lken/TermCast/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/github/downloads/mj0lken/TermCast.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;label=DOWNLOADS&amp;logo=lu:CloudDownload&amp;valueColor=A78BFA" /><img alt="Total downloads" src="https://shieldcn.dev/github/downloads/mj0lken/TermCast.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=lu:CloudDownload&amp;valueColor=7C3AED" /></picture></a>
  <a href="https://github.com/mj0lken/TermCast/actions/workflows/release.yml"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/github/ci/mj0lken/TermCast.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;workflow=release.yml&amp;label=BUILD&amp;logo=lu:Hammer&amp;valueColor=34D399" /><img alt="Release build status" src="https://shieldcn.dev/github/ci/mj0lken/TermCast.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;workflow=release.yml&amp;label=BUILD&amp;logo=lu:Hammer&amp;valueColor=16A34A" /></picture></a>
  <br>
  <picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/MACOS-26%2B.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=apple" /><img alt="macOS 26 or later" src="https://shieldcn.dev/badge/MACOS-26%2B.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=apple" /></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/SWIFT-6.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=swift&amp;valueColor=FB923C" /><img alt="Swift 6" src="https://shieldcn.dev/badge/SWIFT-6.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=swift&amp;valueColor=EA580C" /></picture>
  <a href="LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/LICENSE-AGPL--3.0.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=lu:Scale" /><img alt="License: AGPL-3.0" src="https://shieldcn.dev/badge/LICENSE-AGPL--3.0.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=lu:Scale" /></picture></a>
</p>

<p align="center">
  <img src="docs/screenshot.png" alt="TermCast command palette running Terminal Mode" width="750">
</p>

Built natively with SwiftUI and AppKit—zero third-party dependencies, no Electron, and no telemetry. Runs your existing Raycast extensions natively in JavaScriptCore.

## Install

Requires **macOS 26** or newer:

```bash
brew install --cask mj0lken/tap/termcast
```

Or download the signed `Termcast-<version>.dmg` (or `Termcast-Universal-<version>.dmg` for Intel) directly from [**Releases**](https://github.com/mj0lken/TermCast/releases), drag `Termcast.app` into `/Applications`, and enable **Settings → Terminal**.

## Terminal Mode

| Shortcut | Action |
| :--- | :--- |
| **Type a CLI command** | Automatically formats the input in monospace, shows the active folder strip underneath, and highlights `Terminal ⇧↵` |
| **`⇧↵` (`Shift+Return`)** | Executes the typed command in a terminal tab (or opens the Terminal panel when empty) |
| **`>`** | Jumps straight into Terminal Mode and active PTY tabs |
| **`⇧⇥` (`Shift+Tab`)** | Cycles through recent working directories right beneath the search bar |
| **`⌘N` / `⌘1`–`⌘9` / `⇥`** | Spawns and switches between concurrent PTY tabs |
| **`⌘.` / `⌃X`** | Interrupts a running process (`SIGINT`) or closes the current tab |

Each tab runs on a real `PseudoTerminal` with full ANSI color streaming, interactive stdin, and persistent `cd` directory tracking across commands. Read the architecture notes in [`docs/features/terminal.md`](docs/features/terminal.md).

## Inherited Launcher Suite

Everything from upstream [TinyCast](https://github.com/abue-ammar/tinycast) comes built in:

- **Fuzzy Launcher & Hotkeys** — Instant app, file, system-command, and per-app global chord bindings.
- **Raycast Extensions** — Native JavaScriptCore runtime compatible with Raycast store extensions.
- **Clipboard, Snippets & Quicklinks** — Searchable text/image clipboard history, keyword text expansion, and parameterized URLs.
- **Inline Calculator, Notes & Window Management** — Live unit/currency/timezone math, a persistent floating scratchpad, emoji search, and keyboard window snapping.

---

<p align="center">
  <a href="https://mj0lken.github.io/TermCast/">Website</a> ·
  <a href="https://github.com/mj0lken/TermCast">GitHub</a> ·
  <a href="https://github.com/mj0lken/TermCast/releases">Releases</a> ·
  <a href="LICENSE">AGPL-3.0 License</a>
</p>
