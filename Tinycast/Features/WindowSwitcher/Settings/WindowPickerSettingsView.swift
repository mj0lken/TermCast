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
                    $settings.windowPickerAppChord, key: Self.frontAppKey,
                    title: SettingsRowTitle(.windowSwitcherShortcuts, "Front app’s windows"))
            } header: {
                SettingsSectionHeader(.windowSwitcherShortcuts)
            } footer: {
                Text("The second shortcut walks only the windows of the app in front.")
            }
            .settingsEnabled(settings.windowPickerEnabled)

            Section {
                optionPicker(
                    $settings.windowPickerTileSize, titles: \.title,
                    label: SettingsRowTitle(.windowSwitcherLayout, "Window size"))
                optionPicker(
                    $settings.windowPickerMaxColumns, titles: \.title,
                    label: SettingsRowTitle(.windowSwitcherLayout, "Windows per row"))
                optionPicker(
                    $settings.windowPickerMaxRows, titles: \.title,
                    label: SettingsRowTitle(.windowSwitcherLayout, "Rows"))
                optionPicker(
                    $settings.windowPickerMaxWidth, titles: \.title,
                    label: SettingsRowTitle(.windowSwitcherLayout, "Maximum width"))
                optionPicker(
                    $settings.windowPickerMaxHeight, titles: \.title,
                    label: SettingsRowTitle(.windowSwitcherLayout, "Maximum height"))
            } header: {
                SettingsSectionHeader(.windowSwitcherLayout)
            } footer: {
                Text("Width and height are shares of the screen; extra windows add rows.")
            }
            .settingsEnabled(settings.windowPickerEnabled)

            Section {
                Toggle(isOn: $settings.windowPickerShowsPreviews) {
                    SettingsRowTitle(.windowSwitcherOptions, "Show window previews")
                    Text("Needs Screen Recording access. Without it, tiles show the app icon.")
                }
                Toggle(isOn: $settings.windowPickerSearchEnabled) {
                    SettingsRowTitle(.windowSwitcherOptions, "Type to search")
                    Text(
                        settings.windowPickerSearchEnabled
                            ? "Close, quit and hide are now ⇧W, ⇧Q and ⇧H, so every letter can be typed."
                            : "Letters bring matching windows to the front of the grid.")
                }
                Toggle(isOn: $settings.windowPickerStacksByApp) {
                    SettingsRowTitle(.windowSwitcherOptions, "Stack windows by app")
                    Text("Tap left ⇧ while the switcher is open to switch between the two.")
                }
                Picker(selection: $settings.windowPickerStackDelay) {
                    ForEach(WindowPickerStackDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                } label: {
                    SettingsRowTitle(.windowSwitcherOptions, "Open a selected stack after")
                    Text("Tap right ⇧ to open or close one at once.")
                }
            } header: {
                SettingsSectionHeader(.windowSwitcherOptions)
            }
            .settingsEnabled(settings.windowPickerEnabled)

            Section {
                keyRow("Next or previous window", keys: "⇥   ⇧⇥")
                keyRow("Move in the grid", keys: "←  →  ↑  ↓")
                keyRow("Switch to a numbered window", keys: "1 – 9")
                keyRow("Switch to the selected window", keys: "↵")
                keyRow("Stack or unstack by app", keys: String(localized: "Left ⇧"))
                keyRow("Open or close the selected stack", keys: String(localized: "Right ⇧"))
                keyRow("Step back, then cancel", keys: "esc")
                keyRow(
                    "Close the window, quit or hide its app",
                    keys: settings.windowPickerSearchEnabled ? "⇧W   ⇧Q   ⇧H" : "W   Q   H")
                if settings.windowPickerSearchEnabled {
                    keyRow("Search by app or window title", keys: "A – Z")
                }
            } header: {
                SettingsSectionHeader(.windowSwitcherKeys)
            } footer: {
                Text("These work while the switcher is open and the modifier is held.")
            }
            .settingsEnabled(settings.windowPickerEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.windowSwitcher)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    /// What the key types on this keyboard: the backtick's position holds § or < elsewhere.
    private static var frontAppKey: String {
        let keyCode = Int(WindowPickerKeyEngine.KeyCode.grave)
        return ASCIIKeyboardLayout.character(for: keyCode)?.uppercased() ?? "`"
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

    private func keyRow(_ action: LocalizedStringKey, keys: String) -> some View {
        LabeledContent {
            Text(verbatim: keys)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } label: {
            Text(action)
        }
    }

    private func optionPicker<Option: CaseIterable & Identifiable & Hashable>(
        _ selection: Binding<Option>, titles: KeyPath<Option, String>, label: SettingsRowTitle
    ) -> some View where Option.AllCases: RandomAccessCollection {
        Picker(selection: selection) {
            ForEach(Option.allCases) { option in
                Text(verbatim: option[keyPath: titles]).tag(option)
            }
        } label: {
            label
        }
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
