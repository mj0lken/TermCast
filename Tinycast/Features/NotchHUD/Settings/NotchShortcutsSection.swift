import SwiftUI

/// The open notch's header buttons: which ones, in what order, and as many as the header holds.
struct NotchShortcutsSection: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    private var limit: Int { NotchShortcut.limit(showsBattery: settings.notchShowsBattery) }

    var body: some View {
        Section {
            ForEach(settings.notchShortcuts, id: \.self) { shortcut in
                row(shortcut)
            }
            Menu {
                ForEach(available, id: \.self) { shortcut in
                    Button {
                        add(shortcut)
                    } label: {
                        label(shortcut)
                    }
                }
            } label: {
                Label("Add Shortcut", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(settings.notchShortcuts.count >= limit || available.isEmpty)
        } header: {
            SettingsSectionHeader(.notchShortcuts)
        } footer: {
            Text(
                """
                The header holds \(limit) shortcuts beside the notch. The battery indicator takes one \
                slot while it shows.
                """)
        }
    }

    private var available: [NotchShortcut] {
        NotchShortcut.allCases.filter { !settings.notchShortcuts.contains($0) }
    }

    private func row(_ shortcut: NotchShortcut) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            label(shortcut)
            if let pane = disabledFeaturePane(of: shortcut) {
                Text("Off").foregroundStyle(.secondary)
                Button("Turn On…") { core.settingsCoordinator.showSettings(tab: pane) }
                    .buttonStyle(.link)
                    .labelStyle(.titleOnly)
            } else if isOverLimit(shortcut) {
                Text("No room").foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.lg)
            SettingsRowIconButton("Move Up", systemImage: "chevron.up") { move(shortcut, by: -1) }
                .disabled(settings.notchShortcuts.first == shortcut)
            SettingsRowIconButton("Move Down", systemImage: "chevron.down") { move(shortcut, by: 1) }
                .disabled(settings.notchShortcuts.last == shortcut)
            SettingsRowIconButton("Remove", systemImage: "minus.circle.fill") {
                settings.notchShortcuts.removeAll { $0 == shortcut }
            }
            .foregroundStyle(Theme.Colors.destructive)
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
    }

    /// The pane that switches the shortcut's own feature on, when that feature is off.
    private func disabledFeaturePane(of shortcut: NotchShortcut) -> SettingsTab? {
        switch shortcut {
        case .clipboard: settings.clipboardEnabled ? nil : .clipboard
        case .notebook: settings.notesEnabled ? nil : .notes
        case .windowManagement: settings.windowManagementEnabled ? nil : .windowManagement
        case .camera, .timer, .settings: nil
        }
    }

    /// Past the header's width once the battery indicator has taken its slot.
    private func isOverLimit(_ shortcut: NotchShortcut) -> Bool {
        let drawn = settings.notchShortcuts.filter { disabledFeaturePane(of: $0) == nil }
        guard let index = drawn.firstIndex(of: shortcut) else { return false }
        return index >= limit
    }

    private func label(_ shortcut: NotchShortcut) -> some View {
        Label {
            Text(verbatim: shortcut.title)
        } icon: {
            SymbolImage(name: shortcut.symbol, size: Theme.Size.settingsRowIcon)
                .environment(\.symbolVariants, .none)
                .foregroundStyle(.secondary)
        }
        .labelStyle(.titleAndIcon)
    }

    private func add(_ shortcut: NotchShortcut) {
        guard settings.notchShortcuts.count < limit, !settings.notchShortcuts.contains(shortcut) else { return }
        settings.notchShortcuts.append(shortcut)
    }

    private func move(_ shortcut: NotchShortcut, by step: Int) {
        guard let index = settings.notchShortcuts.firstIndex(of: shortcut) else { return }
        let destination = index + step
        guard settings.notchShortcuts.indices.contains(destination) else { return }
        settings.notchShortcuts.swapAt(index, destination)
    }
}
