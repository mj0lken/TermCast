import Combine
import SwiftUI

/// The ⌘⇥ switcher's pane; its switch is its own, apart from Navigation's palette commands.
struct WindowPickerSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core
    @State private var isAccessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var hasScreenRecording = Permissions.hasScreenRecording()
    @State private var isWalkingGrants = false
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.windowPickerEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .windowSwitcherWindowSwitcher, title: "Enable the window switcher",
                        subtitle: "Hold the modifier and press the key to walk every open window.")
                }
                .onChange(of: settings.windowPickerEnabled) {
                    core.windowPickerCoordinator.requestPermissions()
                }
            }
            .settingsAnchor(.windowSwitcherWindowSwitcher)

            Section {
                grantRow(
                    "Accessibility", detail: "Captures the shortcut and switches windows.",
                    isGranted: isAccessibilityTrusted, grant: grantAccessibility)
                if settings.windowPickerShowsPreviews {
                    grantRow(
                        "Screen Recording", detail: "Draws the window previews.",
                        isGranted: hasScreenRecording, grant: grantScreenRecording)
                }
            } header: {
                SettingsSectionHeader(.windowSwitcherPermissions)
            }
            .settingsEnabled(settings.windowPickerEnabled)

            Section {
                chordPicker(
                    $settings.windowPickerChord, key: "⇥",
                    title: SettingsRowTitle(.windowSwitcherShortcuts, "All windows"))
                chordPicker(
                    $settings.windowPickerAppChord, key: "`",
                    title: SettingsRowTitle(.windowSwitcherShortcuts, "Front app’s windows"))
            } header: {
                SettingsSectionHeader(.windowSwitcherShortcuts)
            }
            .settingsEnabled(settings.windowPickerEnabled)

            Section {
                Toggle(isOn: $settings.windowPickerShowsPreviews) {
                    SettingsRowTitle(.windowSwitcherOptions, "Show window previews")
                    Text("Needs Screen Recording access. Without it, tiles show the app icon.")
                }
                Toggle(isOn: $settings.windowPickerGroupsByApp) {
                    SettingsRowTitle(.windowSwitcherOptions, "Group windows by app")
                    Text("Tap left ⇧ while the switcher is open to switch between the two.")
                }
                Picker(selection: $settings.windowPickerGroupDelay) {
                    ForEach(WindowPickerGroupDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                } label: {
                    SettingsRowTitle(.windowSwitcherOptions, "Open a selected group after")
                    Text("Tap right ⇧ to open or close one at once.")
                }
            } header: {
                SettingsSectionHeader(.windowSwitcherOptions)
            }
            .settingsEnabled(settings.windowPickerEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.windowSwitcher)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var needsScreenRecording: Bool {
        settings.windowPickerShowsPreviews && !hasScreenRecording
    }

    private func grantRow(
        _ name: LocalizedStringKey, detail: LocalizedStringKey, isGranted: Bool,
        grant: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.lg) {
                Label(
                    isGranted ? "Granted" : "Not granted",
                    systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(isGranted ? .green : .orange)
                if !isGranted { Button("Grant Access…", action: grant) }
            }
        } label: {
            Text(name)
            Text(detail)
        }
    }

    /// System Settings shows one pane at a time, so the second opens once the first is granted.
    private func grantAccessibility() {
        isWalkingGrants = true
        Permissions.ensureAccessibility()
        Permissions.openAccessibilitySettings()
    }

    private func grantScreenRecording() {
        isWalkingGrants = false
        Permissions.requestScreenRecording()
        Permissions.openScreenRecordingSettings()
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        let recording = Permissions.hasScreenRecording()
        guard trusted != isAccessibilityTrusted || recording != hasScreenRecording else { return }
        isAccessibilityTrusted = trusted
        hasScreenRecording = recording
        guard isWalkingGrants, trusted else { return }
        if needsScreenRecording { grantScreenRecording() }
        isWalkingGrants = false
    }

    private func chordPicker(
        _ selection: Binding<WindowPickerChord>, key: String, title: SettingsRowTitle
    ) -> some View {
        Picker(selection: selection) {
            ForEach(WindowPickerChord.allCases) { chord in
                if let symbol = chord.symbol {
                    Text(verbatim: symbol + key).tag(chord)
                } else {
                    Text("Off").tag(chord)
                }
            }
        } label: {
            title
        }
    }
}
