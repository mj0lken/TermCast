import SwiftUI

struct NotchSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    private static let hoverDelaysMs = [150, 250, 350, 500, 750]

    private var manager: NotchHUDManager { core.notchHUD }

    private var hudEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.notchHUDEnabled },
            set: { next in
                guard next != settings.notchHUDEnabled else { return }
                settings.notchHUDEnabled = next
                if next {
                    Permissions.ensureAccessibility()
                }
            })
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: hudEnabledBinding) {
                    SettingsFeatureToggleLabel(
                        anchor: .notchNotch,
                        title: "Replace system volume & brightness HUD",
                        subtitle: "Shows volume, screen brightness and keyboard backlight inline around the notch.")
                }

                if settings.notchHUDEnabled {
                    NotchHUDStatusRow(status: manager.status)
                }

                Toggle(isOn: $settings.notchShowsPercentage) {
                    SettingsRowTitle(.notchNotch, "Show percentage")
                }
                .settingsEnabled(settings.notchHUDEnabled)

                Toggle(isOn: $settings.notchTintsAccent) {
                    SettingsRowTitle(.notchNotch, "Tint progress bar with accent colour")
                }
                .settingsEnabled(settings.notchHUDEnabled)

                Toggle(isOn: $settings.notchBatteryNotifications) {
                    SettingsRowTitle(.notchNotch, "Show power & charging notifications")
                    Text("Displays a brief notch notification when plugging in or unplugging power.")
                }
                .settingsEnabled(settings.notchHUDEnabled || settings.notchShelfEnabled)
            }
            .settingsAnchor(.notchNotch)

            Section {
                Toggle(isOn: $settings.notchShelfEnabled) {
                    SettingsRowTitle(.notchShelf, "Enable Open Notch (Media, Calendar & Shelf)")
                    Text("Expands the notch into Now Playing controls, upcoming meetings and an AirDrop file shelf.")
                }

                Toggle(isOn: $settings.notchOpenOnHover) {
                    SettingsRowTitle(.notchShelf, "Open notch on hover")
                    Text("Hover over the camera notch or drag files onto it to open.")
                }
                .settingsEnabled(settings.notchShelfEnabled)

                Picker(selection: $settings.notchHoverDelayMs) {
                    ForEach(Self.hoverDelaysMs, id: \.self) { ms in
                        let seconds = (Double(ms) / 1000.0).formatted(.number.precision(.fractionLength(2)))
                        Text("\(seconds)s").tag(ms)
                    }
                } label: {
                    SettingsRowTitle(.notchShelf, "Hover delay")
                }
                .settingsEnabled(settings.notchShelfEnabled && settings.notchOpenOnHover)

                Toggle(isOn: $settings.notchHapticsEnabled) {
                    SettingsRowTitle(.notchShelf, "Haptic feedback")
                }
                .settingsEnabled(settings.notchShelfEnabled)

                Toggle(isOn: $settings.notchRemembersLastTab) {
                    SettingsRowTitle(.notchShelf, "Remember last tab")
                }
                .settingsEnabled(settings.notchShelfEnabled)
            } header: {
                SettingsSectionHeader(.notchShelf)
            }

            Section {
                Toggle(isOn: $settings.notchShowsMedia) {
                    SettingsRowTitle(.notchContent, "Show Now Playing")
                }
                Toggle(isOn: $settings.notchShowsCalendar) {
                    SettingsRowTitle(.notchContent, "Show calendar")
                }
                Toggle(isOn: $settings.notchHidesAllDayEvents) {
                    SettingsRowTitle(.notchContent, "Hide all-day events")
                }
                .settingsEnabled(settings.notchShowsCalendar)
                Toggle(isOn: $settings.notchShowsBattery) {
                    SettingsRowTitle(.notchContent, "Show battery indicator")
                }
                Toggle(isOn: $settings.notchShowsClipboard) {
                    SettingsRowTitle(.notchContent, "Show clipboard button")
                    Text("Adds a quick Clipboard History button in the notch header.")
                }
                .settingsEnabled(settings.clipboardEnabled)
            } header: {
                SettingsSectionHeader(.notchContent)
            }
            .settingsEnabled(settings.notchShelfEnabled)

            Section {
                LabeledContent {
                    Button("Preview") {
                        manager.showPreview()
                    }
                } label: {
                    SettingsRowTitle(.notchPreview, "Preview Notch HUD")
                    Text("Cycles volume, screen brightness and keyboard backlight in the notch.")
                }

                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("Open Home") {
                            manager.openTrayPreview(tab: .home)
                        }
                        Button("Open Shelf") {
                            manager.openTrayPreview(tab: .shelf)
                        }
                    }
                } label: {
                    SettingsRowTitle(.notchPreview, "Preview Open Notch")
                    Text("Opens the expanded Media, Calendar or Shelf tray immediately.")
                }
            } header: {
                SettingsSectionHeader(.notchPreview)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notch)
    }

    private struct NotchHUDStatusRow: View {
        let status: NotchHUDManager.Status

        var body: some View {
            SettingsRow(title: String(localized: "Status")) {
                HStack(spacing: Theme.Spacing.sm) {
                    ColorDot(color: tint)
                    Text(title).foregroundStyle(.secondary)
                    if status == .needsAccessibility {
                        Button("Grant Access…") {
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            }
        }

        private var title: String {
            switch status {
            case .off:
                String(localized: "Off")
            case .active:
                String(localized: "Active")
            case .needsAccessibility:
                String(localized: "Needs Accessibility")
            case .paused:
                String(localized: "Paused")
            }
        }

        private var tint: Color {
            switch status {
            case .active:
                Theme.Colors.success
            case .needsAccessibility:
                Theme.Colors.warning
            case .off, .paused:
                Theme.Colors.textSecondary
            }
        }
    }
}
