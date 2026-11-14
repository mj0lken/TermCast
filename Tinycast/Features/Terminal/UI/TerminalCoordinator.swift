import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class TerminalCoordinator {
    @ObservationIgnored let store: TerminalStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let appIndex: AppIndex
    @ObservationIgnored private let palette: PaletteState
    @ObservationIgnored private let paletteCoordinator: PaletteCoordinator
    @ObservationIgnored private let currencyRates: CurrencyRateStore
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var enteredViaPrefixAt: ContinuousClock.Instant?

    init(
        store: TerminalStore,
        settings: AppSettings,
        appIndex: AppIndex,
        palette: PaletteState,
        paletteCoordinator: PaletteCoordinator,
        currencyRates: CurrencyRateStore,
        core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.currencyRates = currencyRates
        self.core = core
    }

    func applyEnabled() {
        let enabled = settings.terminalEnabled
        appIndex.setCommandsVisible([.openTerminal], enabled)
        appIndex.setCommandsListed(
            [.openTerminal], enabled && settings.terminalShowInLauncher)
        if enabled {
            refreshExecutableIndex()
        } else {
            scanTask?.cancel()
            scanTask = nil
            store.launcherFolderPinned = false
            store.closeAllTabs()
            if palette.mode == .terminal {
                palette.replace(mode: .launcher)
            }
        }
    }

    func applyLauncherPresence() {
        appIndex.setCommandsListed(
            [.openTerminal], settings.terminalEnabled && settings.terminalShowInLauncher)
    }

    func refreshExecutableIndex() {
        guard settings.terminalEnabled else { return }
        scanTask?.cancel()
        let home = store.homeDirectory
        let pathEnv = ProcessInfo.processInfo.environment["PATH"]
        scanTask = Task { [weak self] in
            let names = await PathExecutableIndex.scan(
                homeDirectory: home, environmentPath: pathEnv)
            guard !Task.isCancelled else { return }
            self?.store.setExecutableNames(names)
        }
    }

    func showTerminal() {
        guard settings.terminalEnabled else { return }
        ensureActiveTab()
        paletteCoordinator.togglePalette(mode: .terminal)
    }

    func navigateToTerminal(carrying query: String = "") {
        guard settings.terminalEnabled else { return }
        ensureActiveTab()
        palette.forceExpanded = true
        if palette.mode != .terminal {
            palette.push(mode: .terminal)
        }
        palette.query = query
    }

    func detectLauncherCommand(_ query: String) -> TerminalCommandMatch? {
        guard settings.terminalEnabled else { return nil }
        if TerminalCommandDetector.stripExplicitPrefix(query) != nil {
            return TerminalCommandDetector.detect(
                query, executables: store.executableNames, hasCalculatorOrColorMatch: false)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasColor = ColorValue.parse(trimmed) != nil
        let hasCalc =
            hasColor
            ? false
            : CalcMemo.evaluate(
                trimmed, rates: currencyRates.rates, format: core.calcNumberFormat) != nil
        return TerminalCommandDetector.detect(
            query, executables: store.executableNames,
            hasCalculatorOrColorMatch: hasColor || hasCalc)
    }

    func isFormattingLauncherInput(_ query: String) -> Bool {
        detectLauncherCommand(query) != nil
    }

    func shouldShowLauncherFolderStrip(_ query: String) -> Bool {
        guard settings.terminalEnabled else { return false }
        return store.launcherFolderPinned || detectLauncherCommand(query) != nil
    }

    // Typing `>` jumps straight into Terminal; an immediate space after `>` is absorbed cleanly.
    func handleQueryChanged(_ query: String, mode: PaletteMode) -> Bool {
        guard settings.terminalEnabled else { return false }
        if mode == .launcher, let stripped = TerminalCommandDetector.stripExplicitPrefix(query) {
            enteredViaPrefixAt = ContinuousClock.now
            navigateToTerminal(carrying: stripped)
            return true
        }
        if mode == .terminal, let enteredAt = enteredViaPrefixAt {
            enteredViaPrefixAt = nil
            if query == " ", ContinuousClock.now - enteredAt < .milliseconds(750) {
                palette.query = ""
                return true
            }
        }
        return false
    }

    func handleShiftReturn() -> Bool {
        guard settings.terminalEnabled else { return false }
        switch palette.mode {
        case .launcher:
            let raw = TerminalCommandDetector.stripExplicitPrefix(palette.query) ?? palette.query
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            palette.forceExpanded = true
            if trimmed.isEmpty {
                ensureActiveTab()
                palette.push(mode: .terminal)
                return true
            }
            let tab = reusableEmptyTab() ?? store.createTab(
                workingDirectory: store.activeWorkingDirectory)
            palette.push(mode: .terminal)
            palette.query = ""
            startCommand(trimmed, in: tab)
            return true
        case .terminal:
            let trimmed = palette.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if store.tabs.isEmpty {
                    store.createTab(workingDirectory: store.activeWorkingDirectory)
                } else {
                    store.cycleSelectedTab()
                }
                return true
            }
            let tab = reusableEmptyTab() ?? store.createTab(
                workingDirectory: store.activeWorkingDirectory)
            palette.query = ""
            startCommand(trimmed, in: tab)
            return true
        default:
            return false
        }
    }

    func submitInTerminalScreen() {
        guard settings.terminalEnabled else { return }
        let tab = ensureActiveTab()
        if tab.isRunning {
            let line = palette.query
            if line.isEmpty {
                tab.stop()
                return
            }
            palette.query = ""
            tab.append("\u{1B}[2m\(line)\u{1B}[0m\n")
            tab.sendInputHandler?(line)
            return
        }
        let trimmed = palette.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        palette.query = ""
        if trimmed == "clear" {
            tab.clearOutput()
            return
        }
        startCommand(trimmed, in: tab)
    }

    func handleShiftTab() -> Bool {
        guard settings.terminalEnabled else { return false }
        if palette.mode == .launcher {
            palette.forceExpanded = true
            store.launcherFolderPinned = true
        }
        store.cycleRecentFolder()
        return true
    }

    func resetLauncherTransientState() {
        store.launcherFolderPinned = false
        enteredViaPrefixAt = nil
    }

    func newTab() {
        guard settings.terminalEnabled else { return }
        store.createTab(workingDirectory: store.activeWorkingDirectory)
    }

    func closeSelectedTab() {
        guard let tab = store.selectedTab else { return }
        store.closeTab(id: tab.id)
        if store.tabs.isEmpty, palette.mode == .terminal {
            if !palette.pop() {
                paletteCoordinator.hidePalette()
            }
        }
    }

    func closeTab(id: UUID) {
        store.closeTab(id: id)
        if store.tabs.isEmpty, palette.mode == .terminal {
            if !palette.pop() {
                paletteCoordinator.hidePalette()
            }
        }
    }

    func closeAllTabs() {
        store.closeAllTabs()
        if palette.mode == .terminal {
            if !palette.pop() {
                paletteCoordinator.hidePalette()
            }
        }
    }

    func stopSelectedTab() {
        store.selectedTab?.stop()
    }

    func clearSelectedTab() {
        store.selectedTab?.clearOutput()
    }

    func rerunSelectedTab() {
        guard let tab = store.selectedTab, !tab.isRunning, let command = tab.lastCommand else {
            return
        }
        startCommand(command, in: tab)
    }

    func copySelectedOutput() {
        guard let tab = store.selectedTab, !tab.log.isEmpty else { return }
        let plain = stripANSI(tab.log)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plain, forType: .string)
        core.showMessage(String(localized: "Copied terminal output"))
    }

    func copyActiveDirectory() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.activeWorkingDirectory, forType: .string)
        core.showMessage(String(localized: "Copied folder path"))
    }

    func showActiveDirectoryInFinder() {
        let url = URL(fileURLWithPath: store.activeWorkingDirectory)
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openActiveDirectoryInTerminalApp() {
        let url = URL(fileURLWithPath: store.activeWorkingDirectory)
        guard
            let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.Terminal")
        else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(
            [url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    func chooseFolderFromDialog(reopeningPalette: Bool = false) {
        let wasVisible = paletteCoordinator.isVisible
        let previousMode = palette.mode
        let previousQuery = palette.query
        if wasVisible {
            paletteCoordinator.hidePalette(restoreFocus: false)
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: store.activeWorkingDirectory)
        panel.prompt = String(localized: "Choose Folder")
        if panel.runModal() == .OK, let url = panel.url {
            store.selectFolder(url.path, recordUsage: true)
            if previousMode == .launcher {
                store.launcherFolderPinned = true
            }
        }
        if reopeningPalette, wasVisible {
            paletteCoordinator.showPalette(mode: previousMode, seeding: previousQuery)
        }
    }

    func folderMenuContent(reopeningPalette: Bool) -> PopoverMenuContent {
        let current = RecentFolders.normalize(
            store.activeWorkingDirectory, homeDirectory: store.homeDirectory)
        var items: [PopoverMenuItem] = store.recentFolders.map { folder in
            let normalized = RecentFolders.normalize(folder, homeDirectory: store.homeDirectory)
            let isSelected = normalized == current
            return PopoverMenuItem(
                title: RecentFolders.displayPath(normalized, homeDirectory: store.homeDirectory),
                systemImage: isSelected ? "checkmark" : "folder"
            ) { [weak self] in
                self?.store.selectFolder(normalized, recordUsage: false)
                if self?.palette.mode == .launcher {
                    self?.store.launcherFolderPinned = true
                }
            }
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Choose Folder…"),
                systemImage: "folder.badge.plus",
                startsSection: true
            ) { [weak self] in
                self?.chooseFolderFromDialog(reopeningPalette: reopeningPalette)
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Show Folder in Finder"),
                systemImage: "finder",
                shortcut: "⌘F"
            ) { [weak self] in
                self?.showActiveDirectoryInFinder()
            })
        return PopoverMenuContent(header: String(localized: "Working Directory"), items: items)
    }

    func prepareForTermination() {
        scanTask?.cancel()
        store.closeAllTabs()
    }

    @discardableResult
    private func ensureActiveTab() -> TerminalTab {
        if let tab = store.selectedTab { return tab }
        return store.createTab(workingDirectory: store.activeWorkingDirectory)
    }

    private func reusableEmptyTab() -> TerminalTab? {
        guard let tab = store.selectedTab, !tab.isRunning, tab.lastCommand == nil, tab.log.isEmpty
        else { return nil }
        tab.workingDirectory = store.activeWorkingDirectory
        return tab
    }

    private func startCommand(_ command: String, in tab: TerminalTab) {
        tab.drainTask?.cancel()
        store.recordUsedFolder(tab.workingDirectory)
        tab.beginCommand(command, homeDirectory: store.homeDirectory)

        let handle = TerminalSessionRunner.start(
            command: command,
            workingDirectory: tab.workingDirectory,
            loadsShellEnvironment: settings.terminalLoadsShellEnvironment)
        tab.sendInputHandler = handle.sendInput
        tab.stopHandler = handle.stop

        let tabID = tab.id
        tab.drainTask = Task { @MainActor [weak self, weak tab] in
            for await event in handle.events {
                guard !Task.isCancelled, let self, let tab else { break }
                switch event {
                case .output(let chunk):
                    tab.append(chunk)
                case .finished(let termination, let updatedDirectory):
                    tab.finish(
                        termination: termination,
                        updatedDirectory: updatedDirectory,
                        homeDirectory: self.store.homeDirectory)
                    if let updatedDirectory {
                        self.store.recordUsedFolder(updatedDirectory)
                        if self.store.selectedTabID == tabID {
                            self.store.activeWorkingDirectory = tab.workingDirectory
                        }
                    }
                }
            }
        }
    }

    private func stripANSI(_ raw: String) -> String {
        var result = ""
        var chars = Array(raw)[...]
        while let ch = chars.first {
            chars = chars.dropFirst()
            if ch == "\u{1B}" {
                guard let introducer = chars.first else { break }
                chars = chars.dropFirst()
                if introducer == "[" {
                    while let next = chars.first {
                        chars = chars.dropFirst()
                        if next.isLetter { break }
                    }
                } else {
                    while let next = chars.first, next != "\u{07}", next != "\u{1B}" {
                        chars = chars.dropFirst()
                    }
                }
            } else if ch != "\r" {
                result.append(ch)
            }
        }
        return result
    }
}
