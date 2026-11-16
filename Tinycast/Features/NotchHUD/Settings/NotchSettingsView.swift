import SwiftUI

struct NotchSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    private var manager: NotchHUDManager { core.notchHUD }

    private var enabledBinding: Binding<Bool> {
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
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsFeatureToggleLabel(
                        anchor: .notchNotch,
                        title: "Replace system volume & brightness HUD",
                        subtitle: "Shows volume, screen brightness and keyboard backlight inline around the notch.")
                }

                if settings.notchHUDEnabled {
                    NotchHUDStatusRow(status: manager.status)
                }
            }
            .settingsAnchor(.notchNotch)

            Section {
                LabeledContent {
                    Button("Preview") {
                        manager.showPreview()
                    }
                } label: {
                    SettingsRowTitle(.notchPreview, "Preview Notch HUD")
                    Text("Cycles volume, screen brightness and keyboard backlight in the notch.")
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
