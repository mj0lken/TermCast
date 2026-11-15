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
    @ObservationIgnored private var suppressedAutoOpenQuery: String?
    @ObservationIgnored private var suppressedHybridAutoDetectQuery: String?
    @ObservationIgnored private var pendingPrefixSpaceEat = false
    @ObservationIgnored private var pendingCapturedInputBaseline: String?
    @ObservationIgnored private var isApplyingProgrammaticHybridQuery = false
    @ObservationIgnored private var hybridHistoryNavigator = TerminalHistoryNavigator()
    @ObservationIgnored private var hybridCompletionSession = TerminalCompletionSession()

    private(set) var shellConfigRevision = 0

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
            store.isLauncherTerminalMode = false
            store.launcherFolderPinned = false
            clearHybridInputState()
            store.closeAllTabs()
            if palette.mode == .terminal {
                palette.replace(mode: .launcher)
            }
        }
    }

    private func clearHybridInputState() {
        pendingPrefixSpaceEat = false
        pendingCapturedInputBaseline = nil
        suppressedHybridAutoDetectQuery = nil
        hybridHistoryNavigator.reset()
        hybridCompletionSession.reset()
    }

    private func rewriteHybridQuery(_ text: String) {
        isApplyingProgrammaticHybridQuery = true
        palette.rewriteQuery(text)
        isApplyingProgrammaticHybridQuery = false
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
        if paletteCoordinator.isVisible, palette.mode != .terminal {
            let carried =
                palette.mode == .launcher
                ? (TerminalCommandDetector.stripExplicitPrefix(palette.query) ?? palette.query)
                : ""
            suppressedAutoOpenQuery = palette.query
            navigateToTerminal(carrying: carried)
            return
        }
        _ = ensureActiveInteractiveTab()
        paletteCoordinator.togglePalette(mode: .terminal)
    }

    func navigateToTerminal(carrying query: String = "", executeImmediately: Bool = false) {
        guard settings.terminalEnabled else { return }
        store.isLauncherTerminalMode = false
        clearHybridInputState()
        palette.forceExpanded = true
        palette.query = ""

        let targetDir = store.activeWorkingDirectory
        let tab: TerminalTab
        let wasAlreadyAlive: Bool
        if let existing = store.selectedTab {
            wasAlreadyAlive = existing.isSessionAlive
            if !existing.isSessionAlive {
                existing.workingDirectory = targetDir
                startInteractiveSession(in: existing)
            } else if existing.isIdleAtPrompt && existing.workingDirectory != targetDir {
                existing.changeDirectoryInIdleShell(targetDir)
            }
            tab = existing
        } else {
            wasAlreadyAlive = false
            let created = store.createTab(workingDirectory: targetDir)
            startInteractiveSession(in: created)
            tab = created
        }

        if palette.mode != .terminal {
            palette.push(mode: .terminal)
        }

        if !query.isEmpty {
            let clearLinePrefix = (wasAlreadyAlive && tab.isIdleAtPrompt) ? "\u{15}" : ""
            if executeImmediately {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                store.recordCommand(trimmed)
                store.recordUsedFolder(tab.workingDirectory)
                tab.queueOrSendInput(clearLinePrefix + trimmed + "\r")
            } else {
                tab.queueOrSendInput(clearLinePrefix + query)
            }
        }

        tab.requestFocus()
    }

    func enterLauncherTerminalMode(
        carrying query: String = "", eatNextLeadingSpace: Bool = false
    ) {
        guard settings.terminalEnabled else { return }
        store.isLauncherTerminalMode = true
        palette.forceExpanded = true
        suppressedAutoOpenQuery = query
        suppressedHybridAutoDetectQuery = nil
        pendingPrefixSpaceEat = eatNextLeadingSpace && query.isEmpty
        hybridHistoryNavigator.reset()
        hybridCompletionSession.reset()
        _ = ensureActiveInteractiveTab(focus: false)
        rewriteHybridQuery(query)
    }

    func exitLauncherTerminalMode() {
        store.isLauncherTerminalMode = false
        store.launcherFolderPinned = false
        clearHybridInputState()
        if palette.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            palette.forceExpanded = false
        }
    }

    func toggleLauncherTerminalMode() -> Bool {
        guard settings.terminalEnabled else { return false }
        switch palette.mode {
        case .launcher:
            if isHybridModeActive(query: palette.query) {
                let currentQuery = palette.query
                let hasText = !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                exitLauncherTerminalMode()
                if hasText {
                    suppressedHybridAutoDetectQuery = currentQuery
                }
            } else {
                suppressedHybridAutoDetectQuery = nil
                enterLauncherTerminalMode(carrying: palette.query)
            }
            return true
        case .terminal:
            return moveTerminalInputToLauncherTerminalMode()
        default:
            return false
        }
    }

    private func moveTerminalInputToLauncherTerminalMode() -> Bool {
        let carried = store.selectedTab?.takePromptInputForLauncher() ?? ""
        if !palette.pop() {
            palette.replace(mode: .launcher)
        }
        pendingCapturedInputBaseline = carried
        enterLauncherTerminalMode(carrying: carried)
        return true
    }

    func toggleLauncherAndTerminal() -> Bool {
        guard settings.terminalEnabled else { return false }
        switch palette.mode {
        case .launcher:
            let carried = TerminalCommandDetector.stripExplicitPrefix(palette.query) ?? palette.query
            suppressedAutoOpenQuery = palette.query
            navigateToTerminal(carrying: carried, executeImmediately: false)
            return true
        case .terminal:
            return moveTerminalInputToLauncherTerminalMode()
        default:
            return false
        }
    }

    func runDetectedLauncherCommand(_ command: String, inNewTab: Bool = false) {
        guard settings.terminalEnabled else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if inNewTab {
                newTab(focus: false)
            } else if store.selectedTab?.isSessionAlive == false {
                restartSelectedTab(focus: false)
            }
            return
        }

        store.isLauncherTerminalMode = true
        clearHybridInputState()
        palette.forceExpanded = true
        rewriteHybridQuery("")

        let targetDir = store.activeWorkingDirectory
        let tab: TerminalTab
        let wasAlreadyAlive: Bool
        if inNewTab {
            wasAlreadyAlive = false
            let created = store.createTab(workingDirectory: targetDir)
            startInteractiveSession(in: created)
            tab = created
        } else if let active = store.selectedTab, active.isIdleAtPrompt {
            wasAlreadyAlive = true
            if active.workingDirectory != targetDir {
                active.changeDirectoryInIdleShell(targetDir)
            }
            tab = active
        } else if let dead = store.selectedTab, !dead.isSessionAlive {
            wasAlreadyAlive = false
            dead.workingDirectory = targetDir
            startInteractiveSession(in: dead)
            tab = dead
        } else {
            wasAlreadyAlive = false
            let created = store.createTab(workingDirectory: targetDir)
            startInteractiveSession(in: created)
            tab = created
        }

        store.recordCommand(trimmed)
        store.recordUsedFolder(targetDir)
        let prefix = wasAlreadyAlive ? "\u{15}" : ""
        tab.queueOrSendInput(prefix + trimmed + "\r")
    }

    func isHybridModeActive(query: String) -> Bool {
        guard settings.terminalEnabled else { return false }
        if hasPinnedCustomCommand(for: query) { return false }
        if store.isLauncherTerminalMode { return true }
        guard !palette.isEditingField, query != suppressedHybridAutoDetectQuery else {
            return false
        }
        return detectLauncherCommand(query) != nil
    }

    private func hasPinnedCustomCommand(for query: String) -> Bool {
        guard let entryID = palette.argumentEntryID,
            let command = core.customCommands.command(entryID: entryID)
        else { return false }
        return AppEntry(command).name == query
    }

    func detectLauncherCommand(_ query: String) -> TerminalCommandMatch? {
        guard settings.terminalEnabled else { return nil }
        if store.isLauncherTerminalMode {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .detected(trimmed)
        }
        if TerminalCommandDetector.stripExplicitPrefix(query) != nil {
            return TerminalCommandDetector.detect(
                query, executables: store.executableNames, hasCalculatorOrColorMatch: false)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if CommandCatalog.openInBrowser(for: query) != nil { return nil }
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

    func shouldShowLauncherFolderStrip(_ query: String) -> Bool {
        guard settings.terminalEnabled else { return false }
        return isHybridModeActive(query: query) || store.launcherFolderPinned
    }

    func stepHybridHistory(older: Bool) -> Bool {
        guard isHybridModeActive(query: palette.query) else { return false }
        let result =
            older
            ? hybridHistoryNavigator.stepOlder(
                currentInput: palette.query, history: store.commandHistory)
            : hybridHistoryNavigator.stepNewer()
        if case .updated(let text) = result {
            rewriteHybridQuery(text)
        }
        return true
    }

    func stepHybridTabCompletion(backwards: Bool) -> Bool {
        guard isHybridModeActive(query: palette.query) else { return false }
        let workingDir = store.activeWorkingDirectory
        let homeDir = store.homeDirectory
        let executables = store.executableNames
        let outcome = hybridCompletionSession.step(
            currentInput: palette.query,
            backwards: backwards
        ) { input in
            TerminalTabCompleter.complete(
                input: input,
                workingDirectory: workingDir,
                homeDirectory: homeDir,
                executables: executables,
                listDirectory: Self.listDirectoryEntries)
        }
        switch outcome {
        case .completed(let updated), .cycling(let updated):
            rewriteHybridQuery(updated)
        case .none:
            break
        }
        return true
    }

    private static func listDirectoryEntries(at path: String) -> [TerminalCompletionEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return []
        }
        return names.map { name in
            var isDir: ObjCBool = false
            let full = (path as NSString).appendingPathComponent(name)
            let exists = FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
            return TerminalCompletionEntry(name: name, isDirectory: exists && isDir.boolValue)
        }
    }

    func handleQueryChanged(_ query: String, mode: PaletteMode) -> Bool {
        guard settings.terminalEnabled, mode == .launcher else { return false }
        if isApplyingProgrammaticHybridQuery {
            return false
        }
        hybridHistoryNavigator.reset()
        hybridCompletionSession.noteInputChanged(query)
        if suppressedHybridAutoDetectQuery != nil, query != suppressedHybridAutoDetectQuery {
            suppressedHybridAutoDetectQuery = nil
        }
        if pendingCapturedInputBaseline != nil, query != pendingCapturedInputBaseline {
            pendingCapturedInputBaseline = nil
        }
        if pendingPrefixSpaceEat {
            pendingPrefixSpaceEat = false
            if query == " " {
                rewriteHybridQuery("")
                return true
            }
        }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            suppressedAutoOpenQuery = nil
            suppressedHybridAutoDetectQuery = nil
        }
        if !store.isLauncherTerminalMode,
            let stripped = TerminalCommandDetector.stripExplicitPrefix(query)
        {
            enterLauncherTerminalMode(carrying: stripped, eatNextLeadingSpace: query == ">")
            return true
        }
        if store.isLauncherTerminalMode {
            _ = ensureActiveInteractiveTab(focus: false)
            return false
        }
        if settings.terminalDetectionBehavior == .openTerminal {
            guard query != suppressedAutoOpenQuery, !palette.isEditingField else { return false }
            suppressedAutoOpenQuery = nil
            if case .detected(let command)? = detectLauncherCommand(query), !command.isEmpty {
                suppressedAutoOpenQuery = query
                navigateToTerminal(carrying: query, executeImmediately: false)
                return true
            }
        } else {
            if suppressedAutoOpenQuery != nil, query != suppressedAutoOpenQuery {
                suppressedAutoOpenQuery = nil
            }
            if isHybridModeActive(query: query) {
                _ = ensureActiveInteractiveTab(focus: false)
            }
        }
        return false
    }

    func noteModeChanged(from oldMode: PaletteMode, to newMode: PaletteMode) {
        if newMode == .terminal {
            let tab = ensureActiveInteractiveTab()
            tab.requestFocus()
        } else if oldMode == .terminal && newMode == .launcher {
            suppressedAutoOpenQuery = palette.query
        }
    }

    func shortcutDisplay(for action: TerminalShortcutAction) -> String? {
        TerminalKeyEventBridge.displayString(for: settings.terminalShortcuts.chord(for: action))
    }

    func handleKeyEvent(_ event: NSEvent, launcherMeetingSelected: Bool = false) -> Bool {
        guard settings.terminalEnabled,
            palette.mode == .terminal || palette.mode == .launcher,
            !palette.isComposing,
            !palette.isEditingField,
            !palette.isControlListOpen
        else { return false }

        let isHybrid = palette.mode == .launcher && isHybridModeActive(query: palette.query)
        let inStandardLauncher = palette.mode == .launcher && !isHybrid

        if palette.mode == .terminal || isHybrid,
            let chord = TerminalKeyEventBridge.chord(from: event),
            chord.key == .tab, chord.control, !chord.command, !chord.option
        {
            if store.tabs.count > 1 {
                store.cycleSelectedTab(backwards: chord.shift, focus: palette.mode == .terminal)
            }
            return true
        }

        guard let chord = TerminalKeyEventBridge.chord(from: event),
            let action = settings.terminalShortcuts.matchedAction(
                for: chord, inLauncher: inStandardLauncher)
        else { return false }

        // Inside the live PTY, unmodified Shift+Tab belongs to zsh reverse-completion (\e[Z).
        if palette.mode == .terminal,
            action == .cycleFolder,
            chord == TerminalShortcutAction.cycleFolder.defaultChord
        {
            return false
        }
        if palette.mode == .terminal,
            action == .runInTerminal,
            chord == TerminalShortcutAction.runInTerminal.defaultChord
        {
            return false
        }

        return performShortcutAction(
            action, chord: chord, launcherMeetingSelected: launcherMeetingSelected)
    }

    private func performShortcutAction(
        _ action: TerminalShortcutAction,
        chord: TerminalKeyChord,
        launcherMeetingSelected: Bool
    ) -> Bool {
        let inLauncher = palette.mode == .launcher
        let isHybrid = inLauncher && isHybridModeActive(query: palette.query)
        let hasLauncherCommand = isHybrid || (inLauncher && store.launcherFolderPinned)

        switch action {
        case .toggleTerminalMode:
            return toggleLauncherTerminalMode()
        case .switchToTerminal:
            if inLauncher,
                !hasLauncherCommand,
                launcherMeetingSelected,
                chord == TerminalShortcutAction.switchToTerminal.defaultChord
            {
                return false
            }
            return toggleLauncherAndTerminal()
        case .copyLastOutput:
            copyLatestOutput()
            return true
        case .openExternalTerminal:
            if inLauncher && !hasLauncherCommand {
                return false
            }
            return continueInExternalTerminal()
        case .runInTerminal:
            if inLauncher && !hasLauncherCommand {
                return false
            }
            return handleShiftReturn()
        case .cycleFolder:
            return handleShiftTab()
        case .newTab:
            newTab(focus: palette.mode == .terminal)
            return true
        case .closeTab:
            closeSelectedTab()
            return true
        case .stopCommand:
            stopSelectedTab()
            return true
        case .clearOutput:
            clearSelectedTab()
            return true
        }
    }

    func handleShiftReturn() -> Bool {
        guard settings.terminalEnabled else { return false }
        switch palette.mode {
        case .launcher:
            let raw = TerminalCommandDetector.stripExplicitPrefix(palette.query) ?? palette.query
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                newTab(focus: false)
                return true
            }
            runDetectedLauncherCommand(trimmed, inNewTab: true)
            return true
        case .terminal:
            newTab(focus: true)
            return true
        default:
            return false
        }
    }

    func handleShiftTab() -> Bool {
        guard settings.terminalEnabled else { return false }
        if palette.mode == .launcher {
            palette.forceExpanded = true
            store.launcherFolderPinned = true
            store.cycleRecentFolder(syncIdleTab: isHybridModeActive(query: palette.query))
        } else {
            store.cycleRecentFolder(syncIdleTab: true)
            store.selectedTab?.requestFocus()
        }
        return true
    }

    func resetLauncherTransientState() {
        store.isLauncherTerminalMode = false
        store.launcherFolderPinned = false
        suppressedAutoOpenQuery = nil
        clearHybridInputState()
    }

    func newTab(focus: Bool? = nil) {
        guard settings.terminalEnabled else { return }
        let shouldFocus = focus ?? (palette.mode == .terminal)
        let tab = store.createTab(workingDirectory: store.activeWorkingDirectory)
        startInteractiveSession(in: tab)
        if shouldFocus {
            tab.requestFocus()
        }
    }

    func restartSelectedTab(focus: Bool? = nil) {
        guard settings.terminalEnabled else { return }
        let shouldFocus = focus ?? (palette.mode == .terminal)
        let tab = ensureActiveInteractiveTab(focus: shouldFocus)
        if !tab.isSessionAlive {
            startInteractiveSession(in: tab)
        }
        if shouldFocus {
            tab.requestFocus()
        }
    }

    func openFromActiveSessionsBadge() {
        guard settings.terminalEnabled else { return }
        if let selected = store.selectedTab {
            if !selected.isRunning, let running = store.tabs.first(where: \.isRunning) {
                store.selectTab(id: running.id, focus: false)
            } else if !selected.isSessionAlive, let alive = store.tabs.first(where: \.isSessionAlive) {
                store.selectTab(id: alive.id, focus: false)
            }
        }
        if palette.mode == .terminal {
            _ = moveTerminalInputToLauncherTerminalMode()
            palette.focusToken = UUID()
            return
        }
        if palette.mode != .launcher {
            while palette.mode != .launcher, palette.pop() {}
            if palette.mode != .launcher {
                palette.replace(mode: .launcher)
            }
            enterLauncherTerminalMode(carrying: "")
            palette.focusToken = UUID()
            return
        }
        let carried = TerminalCommandDetector.stripExplicitPrefix(palette.query) ?? palette.query
        enterLauncherTerminalMode(carrying: carried)
        palette.focusToken = UUID()
    }

    func closeSelectedTab() {
        guard let tab = store.selectedTab else { return }
        closeTab(id: tab.id)
    }

    func closeTab(id: UUID) {
        guard let tab = store.tabs.first(where: { $0.id == id }) else { return }
        guard TerminalTabFormatting.requiresCloseConfirmation(isRunning: tab.isRunning) else {
            closeTabImmediately(id: id)
            return
        }
        guard !core.isShowingDialog else { return }
        let label = tab.title(homeDirectory: store.homeDirectory)
        let message = String(
            localized:
                "A command is still running in this tab. Closing it will terminate the session.")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let confirmed = await self.core.confirm(
                title: String(localized: "Close “\(label)”?"),
                message: message,
                symbol: "apple.terminal",
                confirmTitle: String(localized: "Close Tab"))
            await Task.yield()
            guard confirmed else {
                self.restorePaletteTerminalFocusIfVisible()
                return
            }
            guard self.store.tabs.contains(where: { $0.id == id }) else { return }
            self.closeTabImmediately(id: id)
            self.restorePaletteTerminalFocusIfVisible()
        }
    }

    func closeAllTabs() {
        guard !store.tabs.isEmpty else { return }
        let activeCount = store.activeSessionCount
        guard activeCount > 0 else {
            closeAllTabsImmediately()
            return
        }
        guard !core.isShowingDialog else { return }
        let title =
            activeCount == 1
            ? String(localized: "Close Active Session?")
            : String(localized: "Close \(activeCount) Active Sessions?")
        let message =
            activeCount == 1
            ? String(localized: "Closing all tabs will terminate 1 active shell session.")
            : String(
                localized: "Closing all tabs will terminate \(activeCount) active shell sessions.")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let confirmed = await self.core.confirm(
                title: title,
                message: message,
                symbol: "apple.terminal",
                confirmTitle: String(localized: "Close All"))
            await Task.yield()
            guard confirmed else {
                self.restorePaletteTerminalFocusIfVisible()
                return
            }
            self.closeAllTabsImmediately()
        }
    }

    private func closeTabImmediately(id: UUID) {
        store.closeTab(id: id)
        if store.tabs.isEmpty {
            if palette.mode == .terminal {
                if !palette.pop() {
                    paletteCoordinator.hidePalette()
                }
            } else if palette.mode == .launcher && isHybridModeActive(query: palette.query) {
                _ = ensureActiveInteractiveTab(focus: false)
            }
        }
    }

    private func closeAllTabsImmediately() {
        store.closeAllTabs()
        if palette.mode == .terminal {
            if !palette.pop() {
                paletteCoordinator.hidePalette()
            }
        } else if palette.mode == .launcher && isHybridModeActive(query: palette.query) {
            exitLauncherTerminalMode()
        }
    }

    private func restorePaletteTerminalFocusIfVisible() {
        guard paletteCoordinator.isVisible else { return }
        paletteCoordinator.anchorView?.window?.makeKeyAndOrderFront(nil)
        if palette.mode == .terminal {
            store.selectedTab?.requestFocus()
        }
    }

    func stopSelectedTab() {
        store.selectedTab?.interrupt()
        if palette.mode == .terminal {
            store.selectedTab?.requestFocus()
        }
    }

    func clearSelectedTab() {
        store.selectedTab?.clearOutput()
        if palette.mode == .terminal {
            store.selectedTab?.requestFocus()
        }
    }

    func rerunSelectedTab() {
        guard let tab = store.selectedTab, tab.isIdleAtPrompt, let command = tab.lastCommand else {
            return
        }
        tab.sendTextImmediately("\u{15}" + command + "\r")
        if palette.mode == .terminal {
            tab.requestFocus()
        }
    }

    func copyLatestOutput() {
        guard let tab = store.selectedTab else {
            core.showMessage(String(localized: "No terminal output yet"))
            return
        }
        let latest = tab.emulator.latestCommandOutput()
        guard !latest.isEmpty else {
            core.showMessage(String(localized: "No terminal output yet"))
            return
        }
        copyToPasteboard(latest, message: String(localized: "Copied latest output"))
    }

    func copyAllOutput() {
        guard let tab = store.selectedTab else {
            core.showMessage(String(localized: "No terminal output yet"))
            return
        }
        let plain = tab.emulator.plainText(includeScrollback: true)
        guard !plain.isEmpty else {
            core.showMessage(String(localized: "No terminal output yet"))
            return
        }
        copyToPasteboard(plain, message: String(localized: "Copied all terminal output"))
    }

    func showCopiedSelectionFeedback() {
        core.showMessage(String(localized: "Copied selection"))
    }

    func copyActiveDirectory() {
        copyToPasteboard(
            store.activeWorkingDirectory, message: String(localized: "Copied folder path"))
    }

    private func copyToPasteboard(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        core.showMessage(message)
    }

    func showActiveDirectoryInFinder() {
        let url = URL(fileURLWithPath: store.activeWorkingDirectory)
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showTerminalSettings() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.settingsCoordinator.showSettings(tab: .terminal)
    }

    func performPaletteShortcut(
        _ shortcut: PaletteShortcut,
        focusTerminal: Bool,
        explicitCommand: String? = nil
    ) -> Bool {
        switch shortcut {
        case .deleteAll:
            closeAllTabs()
            return true
        case .restart:
            if store.selectedTab?.isSessionAlive == false {
                restartSelectedTab(focus: focusTerminal)
            } else {
                rerunSelectedTab()
            }
            return true
        case .copyFile:
            copyLatestOutput()
            return true
        case .copyText:
            copyAllOutput()
            return true
        case .copyPath:
            copyActiveDirectory()
            return true
        case .showInFinder:
            showActiveDirectoryInFinder()
            return true
        case .showDetails:
            guard !focusTerminal, let explicitCommand else { return false }
            navigateToTerminal(carrying: explicitCommand)
            return true
        case .openInApp:
            return continueInExternalTerminal(explicitCommand: explicitCommand)
        case .settings:
            showTerminalSettings()
            return true
        case .favoriteSlot(let slot):
            guard store.tabs.indices.contains(slot) else { return false }
            store.selectTab(at: slot, focus: focusTerminal)
            return true
        default:
            return false
        }
    }

    var resolvedExternalTerminalName: String {
        ExternalTerminalLauncher.resolvedApp(for: settings.terminalExternalApp).displayName
    }

    func externalTerminalActionTitle(hasCommand: Bool) -> String {
        let appName = resolvedExternalTerminalName
        return hasCommand
            ? String(localized: "Continue in \(appName)")
            : String(localized: "Open in \(appName)")
    }

    @discardableResult
    func continueInExternalTerminal(explicitCommand: String? = nil) -> Bool {
        let rawCommand: String
        if let explicitCommand {
            rawCommand = explicitCommand
        } else if palette.mode == .launcher {
            rawCommand = TerminalCommandDetector.stripExplicitPrefix(palette.query) ?? palette.query
        } else if palette.mode == .terminal {
            rawCommand = store.selectedTab?.takePromptInputForLauncher() ?? ""
        } else {
            rawCommand = ""
        }
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder =
            palette.mode == .terminal
            ? (store.selectedTab?.workingDirectory ?? store.activeWorkingDirectory)
            : store.activeWorkingDirectory

        if !trimmed.isEmpty {
            store.recordCommand(trimmed)
            store.recordUsedFolder(folder)
            if palette.mode == .launcher {
                palette.query = ""
            }
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        return ExternalTerminalLauncher.launch(
            preference: settings.terminalExternalApp,
            workingDirectory: folder,
            homeDirectory: store.homeDirectory,
            command: trimmed)
    }

    var hasShellConfig: Bool {
        _ = shellConfigRevision
        return TerminalShellConfig.exists(homeDirectory: store.homeDirectory)
    }

    func createAndOpenShellConfig() {
        let existed = TerminalShellConfig.exists(homeDirectory: store.homeDirectory)
        guard
            let url = try? TerminalShellConfig.ensureRecommendedConfig(
                homeDirectory: store.homeDirectory, overwrite: false)
        else { return }
        shellConfigRevision &+= 1
        NSWorkspace.shared.open(url)
        if !existed {
            core.showMessage(String(localized: "Created ~/.config/termcast/init.zsh"))
        }
    }

    func revealShellConfigInFinder() {
        let url = TerminalShellConfig.configURL(homeDirectory: store.homeDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func chooseFolderFromDialog(reopeningPalette: Bool = false) {
        let wasVisible = paletteCoordinator.isVisible
        let previousMode = palette.mode
        let previousQuery = palette.query
        let wasHybrid = previousMode == .launcher && isHybridModeActive(query: previousQuery)
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
            store.selectFolder(
                url.path, recordUsage: true, syncIdleTab: previousMode == .terminal || wasHybrid)
            if previousMode == .launcher {
                store.launcherFolderPinned = true
            }
        }
        if reopeningPalette, wasVisible {
            paletteCoordinator.showPalette(mode: previousMode, seeding: previousQuery)
            if wasHybrid {
                enterLauncherTerminalMode(carrying: previousQuery)
            }
        }
    }

    func folderMenuContent(reopeningPalette: Bool) -> PopoverMenuContent {
        let current = RecentFolders.normalize(
            store.activeWorkingDirectory, homeDirectory: store.homeDirectory)
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: String(localized: "Select Folder…"),
                systemImage: "folder.badge.plus"
            ) { [weak self] in
                self?.chooseFolderFromDialog(reopeningPalette: reopeningPalette)
            }
        ]
        items.append(
            contentsOf: store.recentFolders.enumerated().map { index, folder in
                let normalized = RecentFolders.normalize(folder, homeDirectory: store.homeDirectory)
                let isSelected = normalized == current
                return PopoverMenuItem(
                    title: RecentFolders.displayPath(normalized, homeDirectory: store.homeDirectory),
                    systemImage: isSelected ? "checkmark" : "folder",
                    startsSection: index == 0
                ) { [weak self] in
                    guard let self else { return }
                    let inTerminal = self.palette.mode == .terminal
                    let inHybrid =
                        self.palette.mode == .launcher
                        && self.isHybridModeActive(query: self.palette.query)
                    self.store.selectFolder(
                        normalized, recordUsage: false, syncIdleTab: inTerminal || inHybrid)
                    if self.palette.mode == .launcher {
                        self.store.launcherFolderPinned = true
                    } else if inTerminal {
                        self.store.selectedTab?.requestFocus()
                    }
                }
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Show Folder in Finder"),
                systemImage: "finder",
                startsSection: true,
                shortcut: "⌘F"
            ) { [weak self] in
                self?.showActiveDirectoryInFinder()
            })
        return PopoverMenuContent(header: String(localized: "Working Directory"), items: items)
    }

    func terminalModeActions() -> PopoverMenuContent {
        buildActionsMenu(inTerminalMode: true, command: "")
    }

    func launcherRowActions(command: String) -> PopoverMenuContent {
        buildActionsMenu(inTerminalMode: false, command: command)
    }

    private func buildActionsMenu(inTerminalMode: Bool, command: String) -> PopoverMenuContent {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedTab = store.selectedTab
        var items: [PopoverMenuItem] = []

        if !inTerminalMode && !trimmed.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Run Command"),
                    systemImage: "play.fill",
                    shortcut: "↵"
                ) { [weak self] in
                    self?.runDetectedLauncherCommand(command, inNewTab: false)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Run in New Tab"),
                    systemImage: "plus.rectangle.on.rectangle",
                    shortcut: shortcutDisplay(for: .runInTerminal)
                ) { [weak self] in
                    self?.runDetectedLauncherCommand(command, inNewTab: true)
                })
        } else if selectedTab?.isSessionAlive == false {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Restart Shell"),
                    systemImage: "arrow.clockwise",
                    shortcut: "⌘R"
                ) { [weak self] in
                    self?.restartSelectedTab(focus: inTerminalMode)
                })
        } else if selectedTab?.isRunning == true {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Stop Command"),
                    systemImage: "stop.fill",
                    shortcut: shortcutDisplay(for: .stopCommand)
                ) { [weak self] in
                    self?.stopSelectedTab()
                })
        } else if selectedTab?.lastCommand != nil {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Rerun Last Command"),
                    systemImage: "arrow.clockwise",
                    shortcut: "⌘R"
                ) { [weak self] in
                    self?.rerunSelectedTab()
                })
        }

        if inTerminalMode {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "New Tab"),
                    systemImage: "plus",
                    startsSection: !items.isEmpty,
                    shortcut: shortcutDisplay(for: .newTab)
                ) { [weak self] in
                    self?.newTab(focus: true)
                })
            items.append(
                PopoverMenuItem(
                    title: externalTerminalActionTitle(hasCommand: false),
                    systemImage: "arrow.up.forward.app",
                    shortcut: shortcutDisplay(for: .openExternalTerminal)
                ) { [weak self] in
                    _ = self?.continueInExternalTerminal()
                })
        } else {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Switch to Terminal Mode"),
                    systemImage: "apple.terminal",
                    startsSection: !items.isEmpty,
                    shortcut: shortcutDisplay(for: .switchToTerminal)
                ) { [weak self] in
                    self?.navigateToTerminal(carrying: command, executeImmediately: false)
                })
            items.append(
                PopoverMenuItem(
                    title: externalTerminalActionTitle(hasCommand: !trimmed.isEmpty),
                    systemImage: "arrow.up.forward.app",
                    shortcut: shortcutDisplay(for: .openExternalTerminal)
                ) { [weak self] in
                    _ = self?.continueInExternalTerminal(explicitCommand: command)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "New Tab"),
                    systemImage: "plus",
                    shortcut: shortcutDisplay(for: .newTab)
                ) { [weak self] in
                    self?.newTab(focus: false)
                })
        }

        if selectedTab?.hasOutput == true {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy Latest Output"),
                    systemImage: "doc.on.doc",
                    startsSection: true,
                    shortcut: shortcutDisplay(for: .copyLastOutput)
                ) { [weak self] in
                    self?.copyLatestOutput()
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy All Output"),
                    systemImage: "doc.plaintext"
                ) { [weak self] in
                    self?.copyAllOutput()
                })
        }

        items.append(
            PopoverMenuItem(
                title: String(localized: "Clear Output"),
                systemImage: "eraser",
                startsSection: selectedTab?.hasOutput != true,
                shortcut: shortcutDisplay(for: .clearOutput)
            ) { [weak self] in
                self?.clearSelectedTab()
            })

        let cycleShortcut: String? =
            if inTerminalMode,
                settings.terminalShortcuts.chord(for: .cycleFolder)
                    == TerminalShortcutAction.cycleFolder.defaultChord
            {
                nil
            } else {
                shortcutDisplay(for: .cycleFolder)
            }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Cycle Recent Folder"),
                systemImage: "folder",
                startsSection: true,
                shortcut: cycleShortcut
            ) { [weak self] in
                _ = self?.handleShiftTab()
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Select Folder…"),
                systemImage: "folder.badge.plus"
            ) { [weak self] in
                self?.chooseFolderFromDialog(reopeningPalette: true)
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Show Folder in Finder"),
                systemImage: "finder",
                shortcut: "⌘F"
            ) { [weak self] in
                self?.showActiveDirectoryInFinder()
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Copy Folder Path"),
                systemImage: "link",
                shortcut: "⌃⌘C"
            ) { [weak self] in
                self?.copyActiveDirectory()
            })

        if !store.tabs.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Close Tab"),
                    systemImage: "xmark",
                    startsSection: true,
                    shortcut: shortcutDisplay(for: .closeTab),
                    isDestructive: true
                ) { [weak self] in
                    self?.closeSelectedTab()
                })
            if store.tabs.count > 1 {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Close All Tabs"),
                        systemImage: "xmark.circle",
                        shortcut: "⌃⇧X",
                        isDestructive: true
                    ) { [weak self] in
                        self?.closeAllTabs()
                    })
            }
        }

        if inTerminalMode {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Switch to Hybrid Mode"),
                    systemImage: "apple.terminal",
                    startsSection: true,
                    shortcut: shortcutDisplay(for: .switchToTerminal)
                ) { [weak self] in
                    _ = self?.toggleLauncherAndTerminal()
                })
        } else {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Switch to Standard Mode"),
                    systemImage: "magnifyingglass",
                    startsSection: true,
                    shortcut: shortcutDisplay(for: .toggleTerminalMode)
                ) { [weak self] in
                    _ = self?.toggleLauncherTerminalMode()
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Terminal Settings"),
                systemImage: "gearshape",
                shortcut: "⌥⌘,"
            ) { [weak self] in
                self?.showTerminalSettings()
            })
        return PopoverMenuContent(items: items)
    }

    func prepareForTermination() {
        scanTask?.cancel()
        store.closeAllTabs()
    }

    @discardableResult
    func ensureActiveInteractiveTab(focus: Bool = true) -> TerminalTab {
        if let tab = store.selectedTab {
            if !tab.isSessionAlive {
                startInteractiveSession(in: tab)
            }
            if focus {
                tab.requestFocus()
            }
            return tab
        }
        let created = store.createTab(workingDirectory: store.activeWorkingDirectory)
        startInteractiveSession(in: created)
        if focus {
            created.requestFocus()
        }
        return created
    }

    private func startInteractiveSession(in tab: TerminalTab) {
        tab.terminateSession()
        tab.markSessionStarted()
        store.recordUsedFolder(tab.workingDirectory)

        let handle = TerminalSessionRunner.startInteractive(
            workingDirectory: tab.workingDirectory,
            homeDirectory: store.homeDirectory,
            loadsShellEnvironment: settings.terminalLoadsShellEnvironment,
            rows: tab.emulator.rows,
            cols: tab.emulator.cols)
        tab.writeBytesHandler = handle.writeBytes
        tab.resizeHandler = handle.resize
        tab.interruptHandler = handle.interrupt
        tab.terminateHandler = handle.terminate
        tab.hasChildProcessesHandler = handle.hasChildProcesses

        tab.promptFallbackTask = Task { @MainActor [weak tab] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            tab?.markPromptReady()
        }

        let tabID = tab.id
        let homeDir = store.homeDirectory
        tab.drainTask = Task { @MainActor [weak self, weak tab] in
            for await event in handle.events {
                guard !Task.isCancelled, let self, let tab else { break }
                switch event {
                case .output(let bytes):
                    tab.receiveOutput(
                        bytes,
                        homeDirectory: homeDir,
                        onDirectoryChanged: { newDir in
                            self.store.recordUsedFolder(newDir)
                            if self.store.selectedTabID == tabID {
                                self.store.activeWorkingDirectory = newDir
                            }
                        },
                        onCommandStarted: { cmd in
                            self.store.recordCommand(cmd)
                        },
                        onPromptInputCaptured: { captured in
                            guard self.palette.mode == .launcher,
                                self.store.isLauncherTerminalMode,
                                let baseline = self.pendingCapturedInputBaseline
                            else { return }
                            self.pendingCapturedInputBaseline = nil
                            if self.palette.query == baseline, captured != self.palette.query {
                                self.suppressedAutoOpenQuery = captured
                                self.palette.rewriteQuery(captured)
                            }
                        })
                case .exited(let status):
                    tab.handleSessionExited(status: status)
                case .launchFailed(let message):
                    tab.handleLaunchFailed(message)
                }
            }
        }
    }
}
