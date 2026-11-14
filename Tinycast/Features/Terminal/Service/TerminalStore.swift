import Foundation
import Observation

@MainActor
@Observable
final class TerminalTab: Identifiable {
    let id: UUID
    var workingDirectory: String
    var lastCommand: String?
    private(set) var isRunning = false
    private(set) var lastTermination: ShellCommandTermination?
    private(set) var log = ""
    private(set) var delta = ""
    private(set) var revision = 0
    private(set) var generation = 0

    @ObservationIgnored var sendInputHandler: (@Sendable (String) -> Void)?
    @ObservationIgnored var stopHandler: (@Sendable () -> Void)?
    @ObservationIgnored var drainTask: Task<Void, Never>?

    init(id: UUID = UUID(), workingDirectory: String) {
        self.id = id
        self.workingDirectory = workingDirectory
    }

    func title(homeDirectory: String) -> String {
        TerminalTabFormatting.title(
            lastCommand: lastCommand,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory)
    }

    func beginCommand(_ command: String, homeDirectory: String) {
        lastCommand = command
        isRunning = true
        lastTermination = nil
        append(
            TerminalTabFormatting.commandHeader(
                command: command,
                workingDirectory: workingDirectory,
                homeDirectory: homeDirectory))
    }

    func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        log.append(chunk)
        let trimmed = TerminalTabFormatting.trimLogIfNeeded(log)
        if trimmed.didTrim {
            log = trimmed.trimmed
            delta = ""
            generation &+= 1
        } else {
            delta = chunk
        }
        revision &+= 1
    }

    func finish(termination: ShellCommandTermination, updatedDirectory: String?, homeDirectory: String) {
        isRunning = false
        lastTermination = termination
        sendInputHandler = nil
        stopHandler = nil
        drainTask = nil
        if let updatedDirectory {
            workingDirectory = RecentFolders.normalize(updatedDirectory, homeDirectory: homeDirectory)
        }
        switch termination {
        case .exited(let status):
            append(TerminalTabFormatting.exitFooter(status: status))
        case .stopped:
            append("\n\u{1B}[33m[stopped]\u{1B}[0m\n\n")
        case .launchFailed(let message):
            append("\u{1B}[31m\(message)\u{1B}[0m\n\n")
        }
    }

    func clearOutput() {
        log = ""
        delta = ""
        generation &+= 1
        revision &+= 1
    }

    func stop() {
        stopHandler?()
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
    private(set) var executableNames: Set<String> = []
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
    }

    var selectedTab: TerminalTab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    var displayActiveDirectory: String {
        RecentFolders.displayPath(activeWorkingDirectory, homeDirectory: homeDirectory)
    }

    func setExecutableNames(_ names: Set<String>) {
        executableNames = names
    }

    func selectFolder(_ path: String, recordUsage: Bool) {
        let normalized = RecentFolders.normalize(path, homeDirectory: homeDirectory)
        activeWorkingDirectory = normalized
        if let tab = selectedTab, !tab.isRunning {
            tab.workingDirectory = normalized
        }
        if recordUsage || !recentFolders.contains(normalized) {
            recentFolders = RecentFolders.record(
                normalized, in: recentFolders, homeDirectory: homeDirectory)
            persistRecentFolders()
        }
    }

    func cycleRecentFolder(reverse: Bool = false) {
        let next = RecentFolders.cycle(
            from: activeWorkingDirectory,
            in: recentFolders,
            reverse: reverse,
            homeDirectory: homeDirectory)
        activeWorkingDirectory = next
        if let tab = selectedTab, !tab.isRunning {
            tab.workingDirectory = next
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

    func selectTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTabID = tab.id
        activeWorkingDirectory = tab.workingDirectory
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectTab(id: tabs[index].id)
    }

    func cycleSelectedTab(backwards: Bool = false) {
        guard tabs.count > 1 else { return }
        let currentIndex = selectedTab.flatMap { sel in tabs.firstIndex { $0.id == sel.id } } ?? 0
        let step = backwards ? -1 : 1
        let next = (currentIndex + step + tabs.count) % tabs.count
        selectTab(at: next)
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: index)
        removed.stop()
        removed.drainTask?.cancel()
        if selectedTabID == id {
            if tabs.isEmpty {
                selectedTabID = nil
            } else {
                let nextIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[nextIndex].id
                activeWorkingDirectory = tabs[nextIndex].workingDirectory
            }
        }
    }

    func closeAllTabs() {
        for tab in tabs {
            tab.stop()
            tab.drainTask?.cancel()
        }
        tabs.removeAll()
        selectedTabID = nil
    }

    private func persistRecentFolders() {
        defaults.set(recentFolders, forKey: AppSettingsKey.terminalRecentFolders.rawValue)
    }
}
