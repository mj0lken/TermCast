import SwiftUI

struct NotchSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(MainAppLink.self) private var mainApp
    @Environment(AppSettings.self) private var settings
    @Environment(CalendarStore.self) private var calendarStore

    private static let hoverDelaysMs = [150, 250, 350, 500, 750]

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

    /// The notch only shows what Calendar reads, so switching it on here switches Calendar on too.
    private var showsCalendarBinding: Binding<Bool> {
        Binding(
            get: { settings.notchShowsCalendar },
            set: { next in
                settings.notchShowsCalendar = next
                if next, needsCalendar { enableCalendar() }
            })
    }

    /// A grant can leave the switch where it was, so the main app is told to read access again.
    private func enableCalendar() {
        Task {
            guard await core.calendarCoordinator.setCalendarEnabled(true) else { return }
            calendarStore.start()
            mainApp.send(.reloadCalendar)
        }
    }

    private var needsCalendar: Bool {
        !settings.calendarEnabled || calendarStore.access != .granted
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
                    NotchHUDStatusRow(status: mainApp.status.notch)
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

                Toggle(isOn: $settings.notchInputSourceNotifications) {
                    SettingsRowTitle(.notchNotch, "Show input source changes")
                    Text("Names the keyboard layout in the notch each time you switch to another one.")
                }
                .settingsEnabled(settings.notchHUDEnabled)
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

                Toggle(isOn: $settings.notchShowsLiveActivities) {
                    SettingsRowTitle(.notchShelf, "Show live activities around the closed notch")
                    Text(
                        """
                        Keeps music, an upcoming meeting, a timer, dictation, running terminal sessions and \
                        microphone or camera use visible beside the notch.
                        """)
                }
                .settingsEnabled(settings.notchShelfEnabled)
            } header: {
                SettingsSectionHeader(.notchShelf)
            }

            Section {
                Toggle(isOn: $settings.notchShowsMedia) {
                    SettingsRowTitle(.notchContent, "Show Now Playing")
                }
                Toggle(isOn: showsCalendarBinding) {
                    SettingsRowTitle(.notchContent, "Show calendar")
                    Text("Shows this week's events and counts down to the next meeting. Needs the Calendar feature.")
                }
                if settings.notchShowsCalendar, needsCalendar {
                    LabeledContent {
                        Button("Enable Calendar…", action: enableCalendar)
                    } label: {
                        Text("Calendar is off, so the notch has no events to show.")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $settings.notchHidesAllDayEvents) {
                    SettingsRowTitle(.notchContent, "Hide all-day events")
                }
                .settingsEnabled(settings.notchShowsCalendar)
                Toggle(isOn: $settings.notchShowsBattery) {
                    SettingsRowTitle(.notchContent, "Show battery indicator")
                }
            } header: {
                SettingsSectionHeader(.notchContent)
            }
            .settingsEnabled(settings.notchShelfEnabled)

            NotchShortcutsSection()
                .settingsEnabled(settings.notchShelfEnabled)

            Section {
                LabeledContent {
                    Button("Preview") {
                        mainApp.send(.previewNotchHUD)
                    }
                } label: {
                    SettingsRowTitle(.notchPreview, "Preview Notch HUD")
                    Text("Cycles volume, screen brightness and keyboard backlight in the notch.")
                }

                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("Open Home") {
                            mainApp.send(.previewNotchTray(.home))
                        }
                        Button("Open Shelf") {
                            mainApp.send(.previewNotchTray(.shelf))
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
