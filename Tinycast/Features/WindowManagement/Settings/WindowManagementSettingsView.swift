import SwiftUI

struct WindowManagementSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core
    @State private var editor: WindowLayoutEditRequest?
    @State private var pendingDeletion: WindowLayout?
    @State private var customSizeEdit: CustomWindowSizeEditRequest?
    @State private var chosenPreset: WindowShortcutPreset?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .windowManagementWindowManagement,
                enableTitle: "Enable window management",
                enableSubtitle: "Moves the last window you used. Needs Accessibility.",
                isEnabled: $settings.windowManagementEnabled,
                showsInLauncher: $settings.windowManagementShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            if settings.windowManagementEnabled,
                settings.windowSnapByDragging || settings.windowRestoreOnDrag
                    || settings.windowGreenButtonMenu,
                core.windowDragMonitor.needsAccessibility
                    || core.windowGreenButtonMonitor.needsAccessibility
            {
                Section {
                    HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(width: Theme.Size.settingsRowIcon)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text("Accessibility permission required")
                                .foregroundStyle(.orange)
                            Text("Needed to snap and resize other apps' windows.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Theme.Spacing.lg)
                        Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                    }
                }
            }

            Group {
                mouse
                greenButton
                options
                WindowLayoutsSection(
                    onEdit: { editor = WindowLayoutEditRequest(layout: $0) },
                    onDelete: { pendingDeletion = $0 })
                RoomsSection()
                FeatureCommandsSection(
                    owner: .windowManagement, anchor: .windowManagementLayoutCommands)
                CustomWindowSizesSection(onEdit: {
                    customSizeEdit = CustomWindowSizeEditRequest(size: $0)
                })
                commands
            }
            .settingsEnabled(settings.windowManagementEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.windowManagement)
        .settingsEditorPanel(item: $editor) { request in
            WindowLayoutEditorPanel(request: request)
        }
        .onChange(of: core.pendingWindowLayoutEdit?.id, initial: true) { _, _ in
            guard let request = core.pendingWindowLayoutEdit else { return }
            editor = request
            core.pendingWindowLayoutEdit = nil
        }
        .settingsEditorPanel(item: $customSizeEdit) { request in
            CustomWindowSizeEditorPanel(request: request)
        }
        .alert(item: $pendingDeletion) { layout in
            Alert(
                title: Text("Delete \u{201C}\(layout.name)\u{201D}?"),
                message: Text("Its global shortcut and launcher references go with it."),
                primaryButton: .destructive(Text("Delete")) {
                    core.windowLayoutCoordinator.deleteWindowLayout(id: layout.id)
                },
                secondaryButton: .cancel())
        }
    }

    private var mouse: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.windowSnapByDragging) {
                SettingsRowTitle(.windowManagementMouse, "Snap windows by dragging")
                Text("Drag a window to a screen edge or corner to tile it.")
            }

            Toggle(isOn: $settings.windowRestoreOnDrag) {
                SettingsRowTitle(.windowManagementMouse, "Restore windows to original size")
                Text("Dragging a tiled window away restores its previous size.")
            }

            Group {
                Toggle(isOn: $settings.windowHighlightActivationAreas) {
                    SettingsRowTitle(.windowManagementMouse, "Highlight activation areas when dragging")
                    Text("Shows active snap zones along screen edges while dragging.")
                }

                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("\(settings.windowActivationEdgeWidth) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper(
                            "Screen edge width", value: $settings.windowActivationEdgeWidth,
                            in: WindowDragSnap.edgeWidthRange, step: 1
                        )
                        .labelsHidden()
                    }
                } label: {
                    SettingsRowTitle(.windowManagementMouse, "Screen edge width")
                    Text("How close the pointer must get to an outer screen edge.")
                }

                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("\(settings.windowActivationAreaScale)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper(
                            "Activation area scale", value: $settings.windowActivationAreaScale,
                            in: WindowDragSnap.areaScaleRange, step: 5
                        )
                        .labelsHidden()
                    }
                } label: {
                    SettingsRowTitle(.windowManagementMouse, "Activation area scale")
                    Text("Size of corner and upper/lower side snap zones.")
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        SettingsRowTitle(.windowManagementMouse, "Activation areas")
                        Text("Click an edge or corner zone to turn it on or off.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    WindowActivationAreasPicker()
                }
            }
            .settingsEnabled(settings.windowSnapByDragging)
        } header: {
            SettingsSectionHeader(.windowManagementMouse)
        }
    }

    private var greenButton: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.windowGreenButtonMenu) {
                SettingsRowTitle(.windowManagementGreenButton, "Show green button menu")
                Text("Hover over a window's traffic-light button to open a tiling menu.")
            }

            Group {
                Picker(selection: $settings.windowGreenButtonTarget) {
                    ForEach(WindowTrafficLightButton.allCases) { target in
                        Text(target.title).tag(target)
                    }
                } label: {
                    SettingsRowTitle(.windowManagementGreenButton, "Hover button")
                    Text("Choose the green zoom button or the yellow minimize button.")
                }

                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("\(settings.windowGreenButtonHoverDelay) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper(
                            "Green button hover delay", value: $settings.windowGreenButtonHoverDelay,
                            in: WindowTrafficLightButton.hoverDelayRange, step: 50
                        )
                        .labelsHidden()
                    }
                } label: {
                    SettingsRowTitle(.windowManagementGreenButton, "Green button hover delay")
                    Text("How long the pointer rests on the button before the menu opens.")
                }
            }
            .settingsEnabled(settings.windowGreenButtonMenu)
        } header: {
            SettingsSectionHeader(.windowManagementGreenButton)
        }
    }

    private var options: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.windowCycle) {
                ForEach(WindowCycle.allCases) { cycle in
                    Text(cycle.title).tag(cycle)
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, "Cycling")
                Text(settings.windowCycle.detail)
            }

            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("\(settings.windowGap) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper(
                        "Gap between windows", value: $settings.windowGap,
                        in: WindowPlacementEngine.gapRange, step: 2
                    )
                    .labelsHidden()
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, "Gap between windows")
                Text("Between tiled windows and screen edges.")
            }

            Toggle(isOn: $settings.windowFitTightlyToEdges) {
                SettingsRowTitle(.windowManagementOptions, "Fit tightly to screen edges")
                Text("Applies gaps only between tiled windows, not at screen edges.")
            }

            Toggle(isOn: $settings.windowWrapsDisplays) {
                SettingsRowTitle(.windowManagementOptions, "Wrap around displays")
                Text("Moving past the last display returns to the first.")
            }

            Toggle(isOn: $settings.windowKeepsProportions) {
                SettingsRowTitle(.windowManagementOptions, "Keep aspect ratio")
                Text("Off keeps a window's size when it moves to another display.")
            }

            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Picker("Shortcut preset", selection: $chosenPreset) {
                        Text("Choose…").tag(WindowShortcutPreset?.none)
                        ForEach(WindowShortcutPreset.allCases) { preset in
                            Text(preset.title).tag(Optional(preset))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Apply") {
                        guard let chosenPreset else { return }
                        Task { await core.windowShortcutPresetCoordinator.apply(chosenPreset) }
                    }
                    // Live bindings decide, so one edit to an applied preset re-enables it.
                    .disabled(
                        chosenPreset == nil
                            || chosenPreset == core.windowShortcutPresetCoordinator.matchingPreset)
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, "Shortcut preset")
                Text("Fills in another app's shortcuts. Others stay as they are.")
            }
        } header: {
            SettingsSectionHeader(.windowManagementOptions)
        }
    }

    /// One section per catalog group, so the sidebar's own grouping carries the headings.
    private var commands: some View {
        ForEach(WindowCommandCatalog.grouped(), id: \.group) { section in
            Section {
                ForEach(section.commands) { command in
                    WindowCommandSettingsRow(
                        command: command, showsInLauncher: settings.windowManagementShowInLauncher)
                }
            } header: {
                Text(section.group.title)
            }
        }
    }
}

private struct WindowCommandSettingsRow: View {
    let command: WindowCommand
    let showsInLauncher: Bool
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        let entry = AppEntry(command)
        let isVisible = visibility.isItemVisible(entry)
        SettingsRow(title: command.name) {
            WindowCommandIcon(command: command)
        } trailing: {
            // The ranker never sees a hidden entry, so typing here would match nothing.
            AliasField(entry: entry)
                .settingsEnabled(showsInLauncher && isVisible)

            ShortcutRecorder(action: .windowCommand(id: command.id))

            Toggle(
                "", isOn: Binding(get: { isVisible }, set: { visibility.setItemVisible($0, for: entry) })
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .launcherVisibilityHelp()
            .accessibilityLabel("Show \(command.name) in launcher")
        }
    }
}
