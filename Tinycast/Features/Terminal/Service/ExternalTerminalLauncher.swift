import AppKit
import Foundation

@MainActor
enum ExternalTerminalLauncher {
    static func installedBundleIDs() -> Set<String> {
        var found: Set<String> = []
        for candidate in ExternalTerminalApp.detectionOrder {
            if let bundleID = candidate.bundleIdentifier,
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
            {
                found.insert(bundleID)
            }
        }
        return found
    }

    static func installedApps() -> [ExternalTerminalApp] {
        let installed = installedBundleIDs()
        return ExternalTerminalApp.detectionOrder.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return installed.contains(bundleID)
        }
    }

    static func resolvedApp(for preference: ExternalTerminalApp) -> ExternalTerminalApp {
        ExternalTerminalApp.resolve(preference: preference, installedBundleIDs: installedBundleIDs())
    }

    @discardableResult
    static func launch(
        preference: ExternalTerminalApp,
        workingDirectory: String,
        homeDirectory: String,
        command: String?
    ) -> Bool {
        let resolved = resolvedApp(for: preference)
        guard let bundleID = resolved.bundleIdentifier,
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }

        let expandedDir = (workingDirectory as NSString).expandingTildeInPath
        let trimmedCommand = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedCommand.isEmpty {
            let folderURL = URL(fileURLWithPath: expandedDir, isDirectory: true)
            NSWorkspace.shared.open(
                [folderURL],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration())
            return true
        }

        if !resolved.usesCommandScriptFile,
            let executableName = resolved.executableName
        {
            let binaryURL = appURL
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(executableName)
            if FileManager.default.isExecutableFile(atPath: binaryURL.path) {
                let process = Process()
                process.executableURL = binaryURL
                process.currentDirectoryURL = URL(fileURLWithPath: expandedDir, isDirectory: true)
                process.arguments = resolved.directLaunchArguments(
                    workingDirectory: expandedDir, command: trimmedCommand)
                if (try? process.run()) != nil {
                    return true
                }
            }
        }

        let displayDir = RecentFolders.displayPath(expandedDir, homeDirectory: homeDirectory)
        let script = ExternalTerminalApp.handoffScript(
            command: trimmedCommand,
            workingDirectory: expandedDir,
            displayDirectory: displayDir)
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("termcast-\(UUID().uuidString.prefix(8)).command")

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            NSWorkspace.shared.open(
                [scriptURL],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            let folderURL = URL(fileURLWithPath: expandedDir, isDirectory: true)
            NSWorkspace.shared.open(
                [folderURL],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration())
            return true
        }
    }
}
