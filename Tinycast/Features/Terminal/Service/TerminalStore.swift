import Foundation
import Observation

@MainActor
@Observable
final class TerminalTab: Identifiable {
    let id: UUID
    var workingDirectory: String
    var lastCommand: String?
    var sessionTitle: String?
    private(set) var isSessionAlive = false
    private(set) var isRunningCommand = false
    private(set) var backgroundJobCount = 0
    private(set) var isAlternateScreen = false
    private(set) var lastExitStatus: Int32 = 0
    private(set) var launchFailureMessage: String?
    private(set) var revision = 0
    private(set) var focusToken = 0

    @ObservationIgnored let emulator = TerminalEmulator()
    @ObservationIgnored var writeBytesHandler: (@Sendable ([UInt8]) -> Void)?
    @ObservationIgnored var resizeHandler: (@Sendable (Int, Int) -> Void)?
    @ObservationIgnored var interruptHandler: (@Sendable () -> Void)?
    @ObservationIgnored var terminateHandler: (@Sendable () -> Void)?
    @ObservationIgnored var hasChildProcessesHandler: (@Sendable () -> Bool)?
    @ObservationIgnored var drainTask: Task<Void, Never>?
    @ObservationIgnored var promptFallbackTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundWatchTask: Task<Void, Never>?
    @ObservationIgnored private var isPromptReady = false
    @ObservationIgnored private var pendingPromptBytes: [UInt8] = []
    @ObservationIgnored private var sawFirstPrompt = false

    init(id: UUID = UUID(), workingDirectory: String) {
        self.id = id
        self.workingDirectory = workingDirectory
    }

    var isRunning: Bool {
        isSessionAlive && (isRunningCommand || backgroundJobCount > 0 || isAlternateScreen)
    }

    var isIdleAtPrompt: Bool {
        isSessionAlive && !isRunningCommand && !isAlternateScreen
    }

    var hasOutput: Bool {
        emulator.hasText
    }

    func title(homeDirectory: String) -> String {
        if isRunningCommand, let cmd = lastCommand {
            return TerminalTabFormatting.title(
                lastCommand: cmd, workingDirectory: workingDirectory, homeDirectory: homeDirectory)
        }
        return RecentFolders.shortName(workingDirectory, homeDirectory: homeDirectory)
    }

    func requestFocus() {
        focusToken &+= 1
    }

    func markSessionStarted() {
        isSessionAlive = true
        isRunningCommand = false
        backgroundJobCount = 0
        isAlternateScreen = false
        launchFailureMessage = nil
        isPromptReady = false
        sawFirstPrompt = false
        revision &+= 1
    }

    func queueOrSendInput(_ text: String) {
        guard !text.isEmpty else { return }
        queueOrSendBytes(Array(text.utf8))
    }

    func queueOrSendBytes(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        if isPromptReady {
            writeBytesHandler?(bytes)
        } else {
            pendingPromptBytes.append(contentsOf: bytes)
        }
    }

    func sendBytesImmediately(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        writeBytesHandler?(bytes)
    }

    func sendTextImmediately(_ text: String) {
        guard !text.isEmpty else { return }
        sendBytesImmediately(Array(text.utf8))
    }

    func takePromptInputForLauncher() -> String {
        if !isPromptReady, !pendingPromptBytes.isEmpty {
            var raw = String(bytes: pendingPromptBytes, encoding: .utf8) ?? ""
            pendingPromptBytes.removeAll()
            if raw.hasPrefix("\u{15}") { raw.removeFirst() }
            if raw.hasSuffix("\r") { raw.removeLast() }
            return raw
        }
        guard isIdleAtPrompt else { return "" }
        let initial = emulator.currentPromptInput()
        sendBytesImmediately(Array("\u{1B}[99~".utf8))
        return initial
    }

    func resizeTerminal(cols: Int, rows: Int) {
        let clampedCols = min(max(cols, 10), 400)
        let clampedRows = min(max(rows, 2), 200)
        guard clampedCols != emulator.cols || clampedRows != emulator.rows else { return }
        emulator.resize(cols: clampedCols, rows: clampedRows)
        resizeHandler?(clampedRows, clampedCols)
        revision &+= 1
    }

    func receiveOutput(
        _ bytes: [UInt8],
        homeDirectory: String,
        onDirectoryChanged: (String) -> Void,
        onCommandStarted: (String) -> Void,
        onPromptInputCaptured: (String) -> Void = { _ in }
    ) {
        guard !bytes.isEmpty else { return }
        emulator.feed(bytes)

        for response in emulator.takePendingResponses() {
            writeBytesHandler?(response)
        }

        for event in emulator.takeShellEvents() {
            switch event {
            case .commandStarted(let cmd):
                isRunningCommand = true
                stopBackgroundJobWatcher()
                let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lastCommand = trimmed
                    onCommandStarted(trimmed)
                }
            case .commandFinished(let status):
                isRunningCommand = false
                if sawFirstPrompt {
                    lastExitStatus = status
                }
                sawFirstPrompt = true
                markPromptReady()
                syncBackgroundJobWatcher()
            case .backgroundJobCountChanged(let count):
                backgroundJobCount = count
                syncBackgroundJobWatcher()
            case .directoryChanged(let dir):
                let normalized = RecentFolders.normalize(dir, homeDirectory: homeDirectory)
                if workingDirectory != normalized {
                    workingDirectory = normalized
                    onDirectoryChanged(normalized)
                }
            case .titleChanged(let title):
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                sessionTitle = trimmed.isEmpty ? nil : trimmed
            case .promptInputCaptured(let captured):
                onPromptInputCaptured(captured)
            }
        }

        if isAlternateScreen != emulator.isAlternateScreen {
            isAlternateScreen = emulator.isAlternateScreen
        }

        if !isPromptReady && emulator.bracketedPaste {
            sawFirstPrompt = true
            markPromptReady()
        }

        revision &+= 1
    }

    private func syncBackgroundJobWatcher() {
        guard isSessionAlive, !isRunningCommand, backgroundJobCount > 0 else {
            stopBackgroundJobWatcher()
            return
        }
        guard backgroundWatchTask == nil else { return }
        backgroundWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.isSessionAlive,
                    !self.isRunningCommand, self.backgroundJobCount > 0,
                    let check = self.hasChildProcessesHandler
                else { break }
                let stillAlive = await Task.detached { check() }.value
                guard !Task.isCancelled else { break }
                if !stillAlive {
                    self.backgroundJobCount = 0
                    self.revision &+= 1
                    break
                }
            }
            self?.backgroundWatchTask = nil
        }
    }

    private func stopBackgroundJobWatcher() {
        backgroundWatchTask?.cancel()
        backgroundWatchTask = nil
    }

    func markPromptReady() {
        guard !isPromptReady else { return }
        isPromptReady = true
        promptFallbackTask?.cancel()
        promptFallbackTask = nil
        if !pendingPromptBytes.isEmpty {
            let queued = pendingPromptBytes
            pendingPromptBytes.removeAll()
            writeBytesHandler?(queued)
        }
    }

    func handleSessionExited(status: Int32) {
        isSessionAlive = false
        isRunningCommand = false
        backgroundJobCount = 0
        isAlternateScreen = false
        isPromptReady = false
        pendingPromptBytes.removeAll()
        promptFallbackTask?.cancel()
        promptFallbackTask = nil
        stopBackgroundJobWatcher()
        writeBytesHandler = nil
        resizeHandler = nil
        interruptHandler = nil
        terminateHandler = nil
        hasChildProcessesHandler = nil
        drainTask = nil
        lastExitStatus = status
        revision &+= 1
    }

    func handleLaunchFailed(_ reason: String) {
        isSessionAlive = false
        isRunningCommand = false
        backgroundJobCount = 0
        isAlternateScreen = false
        isPromptReady = false
        pendingPromptBytes.removeAll()
        promptFallbackTask?.cancel()
        promptFallbackTask = nil
        stopBackgroundJobWatcher()
        launchFailureMessage = reason
        emulator.feed("\u{1B}[31m\(reason)\u{1B}[0m\r\n")
        revision &+= 1
    }

    func changeDirectoryInIdleShell(_ path: String) {
        workingDirectory = path
        guard isIdleAtPrompt else { return }
        let escaped = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "\u{1B}q cd -- \(escaped)\r"
        queueOrSendInput(command)
    }

    func clearOutput() {
        emulator.clearScrollback()
        if isIdleAtPrompt {
            sendBytesImmediately([0x0C])
        } else {
            emulator.feed("\u{1B}[2J\u{1B}[H")
        }
        revision &+= 1
    }

    func interrupt() {
        if isSessionAlive {
            interruptHandler?()
        }
    }

    func terminateSession() {
        promptFallbackTask?.cancel()
        promptFallbackTask = nil
        stopBackgroundJobWatcher()
        terminateHandler?()
        writeBytesHandler = nil
        resizeHandler = nil
        interruptHandler = nil
        terminateHandler = nil
        hasChildProcessesHandler = nil
        drainTask?.cancel()
        drainTask = nil
        isSessionAlive = false
        isRunningCommand = false
        backgroundJobCount = 0
        isAlternateScreen = false
    }
}

@MainActor
@Observable
final class TerminalStore {
    @ObservationIgnored private let defaults = UserDefaults.standard
    let homeDirectory: String

    private(set) var tabs: [TerminalTab] = []
    var selectedTabID: UUID?
    var activeWorkingDirectory: String
    private(set) var recentFolders: [String]
    private(set) var commandHistory: [String]
    private(set) var executableNames: Set<String> = []
    var isLauncherTerminalMode = false
    var launcherFolderPinned = false

    init(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.homeDirectory = homeDirectory
        let stored = defaults.stringArray(forKey: AppSettingsKey.terminalRecentFolders.rawValue) ?? []
        let initialFolders = RecentFolders.seeded(
            stored: stored,
            homeDirectory: homeDirectory,
            currentDirectory: FileManager.default.currentDirectoryPath,
            directoryExists: { path in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                    && isDir.boolValue
            })
        self.recentFolders = initialFolders
        self.activeWorkingDirectory = initialFolders.first ?? homeDirectory
        let storedHistory =
            defaults.stringArray(forKey: AppSettingsKey.terminalCommandHistory.rawValue) ?? []
        self.commandHistory = TerminalCommandHistory.sanitized(storedHistory)
    }

    var selectedTab: TerminalTab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    var sessionSummary: TerminalSessionSummary {
        TerminalTabFormatting.sessionSummary(
            tabs: tabs.map { (isAlive: $0.isSessionAlive, isRunning: $0.isRunning) })
    }

    var activeSessionCount: Int {
        sessionSummary.activeCount
    }

    var displayActiveDirectory: String {
        RecentFolders.displayPath(activeWorkingDirectory, homeDirectory: homeDirectory)
    }

    func setExecutableNames(_ names: Set<String>) {
        executableNames = names
    }

    func selectFolder(_ path: String, recordUsage: Bool, syncIdleTab: Bool = true) {
        let normalized = RecentFolders.normalize(path, homeDirectory: homeDirectory)
        activeWorkingDirectory = normalized
        if syncIdleTab, let tab = selectedTab, tab.isIdleAtPrompt {
            tab.changeDirectoryInIdleShell(normalized)
        }
        if recordUsage || !recentFolders.contains(normalized) {
            recentFolders = RecentFolders.record(
                normalized, in: recentFolders, homeDirectory: homeDirectory)
            persistRecentFolders()
        }
    }

    func cycleRecentFolder(reverse: Bool = false, syncIdleTab: Bool = true) {
        let next = RecentFolders.cycle(
            from: activeWorkingDirectory,
            in: recentFolders,
            reverse: reverse,
            homeDirectory: homeDirectory)
        activeWorkingDirectory = next
        if syncIdleTab, let tab = selectedTab, tab.isIdleAtPrompt {
            tab.changeDirectoryInIdleShell(next)
        }
    }

    func recordUsedFolder(_ path: String) {
        let normalized = RecentFolders.normalize(path, homeDirectory: homeDirectory)
        activeWorkingDirectory = normalized
        recentFolders = RecentFolders.record(
            normalized, in: recentFolders, homeDirectory: homeDirectory)
        persistRecentFolders()
    }

    func removeRecentFolder(_ path: String) {
        let normalized = RecentFolders.normalize(path, homeDirectory: homeDirectory)
        recentFolders.removeAll { $0 == normalized }
        if recentFolders.isEmpty {
            recentFolders = [RecentFolders.normalize(homeDirectory, homeDirectory: homeDirectory)]
        }
        if activeWorkingDirectory == normalized {
            activeWorkingDirectory = recentFolders[0]
        }
        persistRecentFolders()
    }

    func clearRecentFolders() {
        let home = RecentFolders.normalize(homeDirectory, homeDirectory: homeDirectory)
        recentFolders = [home]
        activeWorkingDirectory = home
        persistRecentFolders()
    }

    @discardableResult
    func createTab(workingDirectory: String? = nil) -> TerminalTab {
        let dir = RecentFolders.normalize(
            workingDirectory ?? activeWorkingDirectory,
            homeDirectory: homeDirectory)
        let tab = TerminalTab(workingDirectory: dir)
        tabs.append(tab)
        selectedTabID = tab.id
        activeWorkingDirectory = dir
        return tab
    }

    func selectTab(id: UUID, focus: Bool = true) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTabID = tab.id
        activeWorkingDirectory = tab.workingDirectory
        if focus {
            tab.requestFocus()
        }
    }

    func selectTab(at index: Int, focus: Bool = true) {
        guard tabs.indices.contains(index) else { return }
        selectTab(id: tabs[index].id, focus: focus)
    }

    func cycleSelectedTab(backwards: Bool = false, focus: Bool = true) {
        guard tabs.count > 1 else { return }
        let currentIndex = selectedTab.flatMap { sel in tabs.firstIndex { $0.id == sel.id } } ?? 0
        let step = backwards ? -1 : 1
        let next = (currentIndex + step + tabs.count) % tabs.count
        selectTab(at: next, focus: focus)
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: index)
        removed.terminateSession()
        if selectedTabID == id {
            if tabs.isEmpty {
                selectedTabID = nil
            } else {
                let nextIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[nextIndex].id
                activeWorkingDirectory = tabs[nextIndex].workingDirectory
                tabs[nextIndex].requestFocus()
            }
        }
    }

    func closeAllTabs() {
        for tab in tabs {
            tab.terminateSession()
        }
        tabs.removeAll()
        selectedTabID = nil
    }

    /// The other process wrote these, so adopt them instead of writing a stale copy back.
    func reloadPersisted() {
        let folders = defaults.stringArray(forKey: AppSettingsKey.terminalRecentFolders.rawValue) ?? []
        if !folders.isEmpty, folders != recentFolders { recentFolders = folders }
        let history = TerminalCommandHistory.sanitized(
            defaults.stringArray(forKey: AppSettingsKey.terminalCommandHistory.rawValue) ?? [])
        if history != commandHistory { commandHistory = history }
    }

    private func persistRecentFolders() {
        defaults.set(recentFolders, forKey: AppSettingsKey.terminalRecentFolders.rawValue)
    }

    func recordCommand(_ command: String) {
        let updated = TerminalCommandHistory.record(command, in: commandHistory)
        guard updated != commandHistory else { return }
        commandHistory = updated
        defaults.set(commandHistory, forKey: AppSettingsKey.terminalCommandHistory.rawValue)
    }

    func clearCommandHistory() {
        guard !commandHistory.isEmpty else { return }
        commandHistory = []
        defaults.removeObject(forKey: AppSettingsKey.terminalCommandHistory.rawValue)
    }
}
