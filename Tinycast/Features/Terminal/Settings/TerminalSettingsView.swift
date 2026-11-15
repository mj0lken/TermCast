import SwiftUI

struct TerminalSettingsView: View {
    @Environment(TerminalStore.self) private var store
    @Environment(TerminalCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var recordingShortcut: TerminalShortcutAction?

    var body: some View {
        @Bindable var settings = settings
        let installedApps = availableExternalApps
        let autoDetectedName = ExternalTerminalLauncher.resolvedApp(for: .automatic).displayName
        return Form {
            FeatureSwitchSection(
                anchor: .terminalTerminal,
                enableTitle: "Enable Terminal",
                enableSubtitle: "Run shell commands in tabs with >, or directly from the launcher.",
                isEnabled: $settings.terminalEnabled,
                showsInLauncher: $settings.terminalShowInLauncher,
                showsHeader: false)

            Section {
                Picker(selection: $settings.terminalDetectionBehavior) {
                    Text("Show in Hybrid Mode").tag(TerminalDetectionBehavior.topResult)
                    Text("Switch to Terminal Mode automatically")
                        .tag(TerminalDetectionBehavior.openTerminal)
                } label: {
                    SettingsRowTitle(.terminalOptions, "Detected commands")
                    Text("How Standard Mode responds when your query looks like a shell command.")
                }

                Picker(selection: $settings.terminalColorTheme) {
                    ForEach(TerminalColorTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                } label: {
                    SettingsRowTitle(.terminalOptions, "Terminal look")
                    Text("Visual theme and ANSI color palette for the internal terminal.")
                }

                Picker(selection: $settings.terminalExternalApp) {
                    Text("Automatic (\(autoDetectedName))").tag(ExternalTerminalApp.automatic)
                    ForEach(installedApps, id: \.self) { app in
                        Text(verbatim: app.displayName).tag(app)
                    }
                } label: {
                    SettingsRowTitle(.terminalOptions, "External terminal")
                    Text("App used when handing off a folder or command with External Terminal.")
                }

                Toggle(isOn: $settings.terminalLoadsShellEnvironment) {
                    SettingsRowTitle(.terminalOptions, "Load shell environment")
                    Text("Sources ~/.zshrc in /bin/zsh so your aliases and PATH are available.")
                }

                LabeledContent {
                    HStack(spacing: 8) {
                        if coordinator.hasShellConfig {
                            Button {
                                coordinator.revealShellConfigInFinder()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .help(String(localized: "Show in Finder"))
                        }
                        Button {
                            coordinator.createAndOpenShellConfig()
                        } label: {
                            Text(
                                coordinator.hasShellConfig
                                    ? String(localized: "Edit Config")
                                    : String(localized: "Create Config"))
                        }
                    }
                } label: {
                    SettingsRowTitle(.terminalOptions, "Recommended shell config")
                    Text("Lightweight ~/.config/termcast/init.zsh for readable colorized ls, git, and grep.")
                }
            } header: {
                SettingsSectionHeader(.terminalOptions)
            }
            .settingsEnabled(settings.terminalEnabled)

            FeatureCommandsSection(owner: .terminal, anchor: .terminalCommands)
                .settingsEnabled(settings.terminalEnabled)

            Section {
                shortcutRow(.toggleTerminalMode) {
                    SettingsRowTitle(.terminalShortcuts, "Toggle Hybrid Mode")
                }
                shortcutRow(.switchToTerminal) {
                    SettingsRowTitle(.terminalShortcuts, "Switch Hybrid / Terminal Mode")
                }
                shortcutRow(.copyLastOutput) {
                    SettingsRowTitle(.terminalShortcuts, "Copy Latest Output")
                }
                shortcutRow(.openExternalTerminal) {
                    SettingsRowTitle(.terminalShortcuts, "Continue in External Terminal")
                }
                shortcutRow(.runInTerminal) {
                    SettingsRowTitle(.terminalShortcuts, "Run in New Tab")
                }
                shortcutRow(.cycleFolder) {
                    SettingsRowTitle(.terminalShortcuts, "Cycle Recent Folder")
                }
                shortcutRow(.newTab) {
                    SettingsRowTitle(.terminalShortcuts, "New Tab")
                }
                shortcutRow(.closeTab) {
                    SettingsRowTitle(.terminalShortcuts, "Close Tab")
                }
                shortcutRow(.stopCommand) {
                    SettingsRowTitle(.terminalShortcuts, "Stop Command")
                }
                shortcutRow(.clearOutput) {
                    SettingsRowTitle(.terminalShortcuts, "Clear Output")
                }

                Button {
                    recordingShortcut = nil
                    settings.terminalShortcuts = .defaults
                } label: {
                    SettingsRowTitle(.terminalShortcuts, "Reset Shortcuts to Defaults")
                }
                .disabled(settings.terminalShortcuts.isDefault)
            } header: {
                SettingsSectionHeader(.terminalShortcuts)
            } footer: {
                Text("Active while the launcher or Terminal panel is open. Supports Hyper Key chords.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.terminalEnabled)

            Section {
                LabeledContent {
                    Text(verbatim: store.commandHistory.count.formatted())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } label: {
                    Text("Saved commands")
                    Text("Press ↑ and ↓ in Terminal to browse previous commands (prefix-filtered when typing).")
                }

                Button(role: .destructive) {
                    store.clearCommandHistory()
                } label: {
                    SettingsRowTitle(.terminalHistory, "Clear Command History")
                }
                .disabled(store.commandHistory.isEmpty)
            } header: {
                SettingsSectionHeader(.terminalHistory)
            }
            .settingsEnabled(settings.terminalEnabled)

            Section {
                ForEach(store.recentFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(RecentFolders.displayPath(folder, homeDirectory: store.homeDirectory))
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if store.recentFolders.count > 1 {
                            Button {
                                store.removeRecentFolder(folder)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove Folder")
                        }
                    }
                }
                Button {
                    coordinator.chooseFolderFromDialog(reopeningPalette: false)
                } label: {
                    SettingsRowTitle(.terminalRecentFolders, "Add Folder…")
                }
                Button(role: .destructive) {
                    store.clearRecentFolders()
                } label: {
                    SettingsRowTitle(.terminalRecentFolders, "Clear Recent Folders")
                }
                .disabled(store.recentFolders.count <= 1)
            } header: {
                SettingsSectionHeader(.terminalRecentFolders)
            } footer: {
                Text(recentFoldersFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.terminalEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.terminal)
    }

    private var availableExternalApps: [ExternalTerminalApp] {
        var apps = ExternalTerminalLauncher.installedApps()
        if settings.terminalExternalApp != .automatic,
            !apps.contains(settings.terminalExternalApp)
        {
            apps.append(settings.terminalExternalApp)
        }
        return apps
    }

    private func shortcutRow<Title: View>(
        _ action: TerminalShortcutAction,
        @ViewBuilder title: () -> Title
    ) -> some View {
        LabeledContent {
            TerminalShortcutRecorder(action: action, recordingAction: $recordingShortcut)
        } label: {
            title()
            Text(action.localizedSubtitle)
        }
    }

    private var recentFoldersFooter: String {
        if let keys = coordinator.shortcutDisplay(for: .cycleFolder) {
            return String(
                localized:
                    "Press \(keys) under the launcher or terminal input to cycle recent folders.")
        }
        return String(localized: "Choose or add folders used as the working directory for Terminal tabs.")
    }
}
