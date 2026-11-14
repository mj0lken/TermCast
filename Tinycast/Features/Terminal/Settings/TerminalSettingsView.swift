import SwiftUI

struct TerminalSettingsView: View {
    @Environment(TerminalStore.self) private var store
    @Environment(TerminalCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .terminalTerminal,
                enableTitle: "Enable Terminal",
                enableSubtitle: "Run shell commands in tabs with >, or press ⇧↵ from the launcher.",
                isEnabled: $settings.terminalEnabled,
                showsInLauncher: $settings.terminalShowInLauncher,
                showsHeader: false)

            Section {
                Toggle(isOn: $settings.terminalLoadsShellEnvironment) {
                    SettingsRowTitle(.terminalOptions, "Load shell environment")
                    Text("Sources ~/.zshrc in /bin/zsh so your aliases and PATH are available.")
                }
            } header: {
                SettingsSectionHeader(.terminalOptions)
            }
            .settingsEnabled(settings.terminalEnabled)

            FeatureCommandsSection(owner: .terminal, anchor: .terminalCommands)
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
                Text("Press ⇧⇥ under the launcher or terminal input to cycle recent folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.terminalEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.terminal)
    }
}
