import Foundation

/// Where each settings.json key lives; exhaustive, so a new key fails to build until it is bound.
@MainActor
enum SettingsFileSchema {
    static func bindings(
        settings: AppSettings, ai: AISettingsStore, quickActions: QuickActionSettingsStore,
        shortcuts: HotKeySettingsFile, launcher: LauncherSettingsFile,
        windowManagement: WindowManagementSettingsFile
    ) -> [SettingsFileBinding] {
        SettingsFileKey.allCases.map { key in
            binding(
                for: key, settings: settings, ai: ai, quickActions: quickActions,
                shortcuts: shortcuts, launcher: launcher, windowManagement: windowManagement)
        }
    }

    private static func binding(
        for key: SettingsFileKey, settings: AppSettings, ai: AISettingsStore,
        quickActions: QuickActionSettingsStore, shortcuts: HotKeySettingsFile,
        launcher: LauncherSettingsFile, windowManagement: WindowManagementSettingsFile
    ) -> SettingsFileBinding {
        func bind<Root: AnyObject, Value: SettingsFileValue>(
            _ root: Root, _ path: ReferenceWritableKeyPath<Root, Value>,
            accept: @escaping (Value) -> Value? = { $0 }
        ) -> SettingsFileBinding {
            SettingsFileBinding(key, root, path, accept: accept)
        }

        switch key {
        case .launcherShortcut:
            return shortcuts.binding(
                for: key, action: .togglePalette, name: String(localized: "App Launcher"))
        case .showInMenuBar: return bind(settings, \.showInMenuBar)
        case .automaticallyCheckForUpdates: return bind(settings, \.automaticallyCheckForUpdates)
        case .popToRootTimeout: return bind(settings, \.popToRootTimeout)
        case .escapeKeyBehavior: return bind(settings, \.escapeKeyBehavior)
        case .autoSwitchInputSource: return bind(settings, \.autoSwitchInputSourceID)
        case .language: return bind(settings, \.language)
        case .appearance: return bind(settings, \.appearance)
        case .animationsEnabled: return bind(settings, \.animationsEnabled)
        case .interfaceSize: return bind(settings, \.interfaceSize)
        case .compactMode: return bind(settings, \.compactMode)
        case .compactBarCommands:
            return bind(settings, \.compactBarCommands) {
                CommandID.validCompactBarCommands($0) ? $0 : nil
            }
        case .openOnCursorScreen: return bind(settings, \.openOnCursorScreen)
        case .paletteDraggable: return bind(settings, \.paletteDraggable)
        case .notchHUDEnabled: return bind(settings, \.notchHUDEnabled)
        case .notchShelfEnabled: return bind(settings, \.notchShelfEnabled)
        case .notchOpenOnHover: return bind(settings, \.notchOpenOnHover)
        case .notchHoverDelayMs:
            return bind(settings, \.notchHoverDelayMs) { (100...1000).contains($0) ? $0 : nil }
        case .notchHapticsEnabled: return bind(settings, \.notchHapticsEnabled)
        case .notchRemembersLastTab: return bind(settings, \.notchRemembersLastTab)
        case .notchBatteryNotifications: return bind(settings, \.notchBatteryNotifications)
        case .notchShowsPercentage: return bind(settings, \.notchShowsPercentage)
        case .notchTintsAccent: return bind(settings, \.notchTintsAccent)
        case .notchShowsMedia: return bind(settings, \.notchShowsMedia)
        case .notchShowsCalendar: return bind(settings, \.notchShowsCalendar)
        case .notchHidesAllDayEvents: return bind(settings, \.notchHidesAllDayEvents)
        case .notchShowsBattery: return bind(settings, \.notchShowsBattery)
        case .notchShortcuts:
            return bind(settings, \.notchShortcuts) {
                NotchShortcut.isValid($0) ? $0 : nil
            }
        case .notchShortcutsBeforeNotch:
            return bind(settings, \.notchShortcutsBeforeNotch) {
                NotchShortcut.isValid($0) ? $0 : nil
            }
        case .notchShortcutsAfterNotch:
            return bind(settings, \.notchShortcutsAfterNotch) {
                NotchShortcut.isValid($0) ? $0 : nil
            }
        case .notchShowsLiveActivities: return bind(settings, \.notchShowsLiveActivities)
        case .notchInputSourceNotifications: return bind(settings, \.notchInputSourceNotifications)
        case .hyperKey: return bind(settings, \.hyperKey)
        case .hyperKeyIncludesShift: return bind(settings, \.hyperKeyIncludesShift)
        case .hyperKeyQuickPress: return bind(settings, \.hyperKeyQuickPress)
        case .hyperKeySecureInputCompatibility:
            return bind(settings, \.hyperKeySecureInputCompatibility)
        case .hyperKeyTrackpadSliders:
            return bind(settings, \.hyperKeyTrackpadSliders)
        case .calcNumberStyle: return bind(settings, \.calcNumberStyle)
        case .launcherShowsSuggestions: return bind(settings, \.launcherShowsSuggestions)
        case .rootSearchSensitivity: return bind(settings, \.rootSearchSensitivity)
        case .applicationsEnabled: return launcher.kindBinding(for: key, kind: .application)
        case .searchScopes: return bind(settings, \.searchScopes) { SearchScopes.normalize($0) }
        case .applications: return launcher.appsBinding(for: key)
        case .systemSettingsEnabled: return launcher.kindBinding(for: key, kind: .systemSettings)
        case .systemSettings: return launcher.panesBinding(for: key)
        case .systemActionsEnabled: return launcher.kindBinding(for: key, kind: .systemAction)
        case .systemActions: return launcher.systemActionsBinding(for: key)
        case .builtInCommandsEnabled: return launcher.kindBinding(for: key, kind: .command)
        case .builtInCommands: return launcher.commandsBinding(for: key, owner: nil)
        case .customCommandsEnabled: return bind(settings, \.customCommandsEnabled)
        case .customCommandsShowInLauncher: return bind(settings, \.customCommandsShowInLauncher)
        case .quicklinksEnabled: return bind(settings, \.quicklinksEnabled)
        case .quicklinksShowInLauncher: return bind(settings, \.quicklinksShowInLauncher)
        case .quicklinkOpensNewWindow: return bind(settings, \.quicklinkOpensNewWindow)
        case .quicklinkPassesSelectedText: return bind(settings, \.quicklinkPassesSelectedText)
        case .quicklinkConfirmsBeforeDelete: return bind(settings, \.quicklinkConfirmsBeforeDelete)
        case .quicklinkCommands: return launcher.commandsBinding(for: key, owner: .quicklinks)
        case .appleShortcutsEnabled: return bind(settings, \.appleShortcutsEnabled)
        case .aiEnabled: return bind(settings, \.aiEnabled)
        case .aiWebSearch: return bind(ai, \.webSearchEnabled)
        case .aiChoices: return bind(ai, \.choicesEnabled)
        case .aiExpandsReasoning: return bind(ai, \.expandsReasoning)
        case .aiSystemPrompt: return bind(ai, \.systemPrompt)
        case .aiSystemPromptEnabled: return bind(ai, \.systemPromptEnabled)
        case .aiRetention: return bind(ai, \.retention)
        case .aiOpensTo: return bind(ai, \.opensTo)
        case .aiNewChatAfter: return bind(ai, \.newChatAfter)
        case .aiToolRounds: return bind(ai, \.toolRounds)
        case .aiCommands: return launcher.commandsBinding(for: key, owner: .ai)
        case .quickActionLanguage: return bind(quickActions, \.settings.targetLanguage)
        case .quickActionCommands: return launcher.commandsBinding(for: key, owner: .quickActions)
        case .fileSearchEnabled: return bind(settings, \.fileSearchEnabled)
        case .fileSearchScopes: return bind(settings, \.fileSearchScopes)
        case .fileSearchIgnorePatterns: return bind(settings, \.fileSearchIgnorePatterns)
        case .fileSearchRemovedDefaultPatterns:
            return bind(settings, \.fileSearchRemovedDefaultPatterns)
        case .fileSearchShowInLauncher: return bind(settings, \.fileSearchShowInLauncher)
        case .fileSearchCommands: return launcher.commandsBinding(for: key, owner: .fileSearch)
        case .notesEnabled: return bind(settings, \.notesEnabled)
        case .notesRendersMarkdown: return bind(settings, \.notesRendersMarkdown)
        case .notesShowsFormattingBar: return bind(settings, \.notesShowsFormattingBar)
        case .notesShowsInMenuBar: return bind(settings, \.notesShowsInMenuBar)
        case .notesFolder: return bind(settings, \.notesFolder, accept: folder)
        case .notesCommands: return launcher.commandsBinding(for: key, owner: .notes)
        case .dictationMode: return bind(settings, \.dictationMode)
        case .dictationShortcut:
            return shortcuts.binding(for: key, action: .dictation, name: String(localized: "Dictation"))
        case .dictationPlaysSounds: return bind(settings, \.dictationPlaysSounds)
        case .dictationModel: return bind(settings, \.dictationModel)
        case .dictationMicrophone: return bind(settings, \.dictationMicrophone)
        case .dictationDestination: return bind(settings, \.dictationDestination)
        case .dictationAdaptsCapitalization: return bind(settings, \.dictationAdaptsCapitalization)
        case .dictationLiveInsertion: return bind(settings, \.dictationLiveInsertion)
        case .dictationIdleRelease: return bind(settings, \.dictationIdleRelease)
        case .dictationLanguage:
            return bind(settings, \.dictationLanguage) { language in
                guard let language else { return .some(nil) }
                return DictationLanguage(rawValue: language) == nil ? nil : .some(language)
            }
        case .snippetsShowInLauncher: return bind(settings, \.snippetsShowInLauncher)
        case .snippetsFolder: return bind(settings, \.snippetsFolder, accept: folder)
        case .snippetDefaultAction: return bind(settings, \.snippetDefaultAction)
        case .snippetsCommands: return launcher.commandsBinding(for: key, owner: .snippets)
        case .navigationEnabled: return bind(settings, \.navigationEnabled)
        case .menuSearchShowsAppleMenu: return bind(settings, \.menuSearchShowsAppleMenu)
        case .menuSearchDisabledApps: return bind(settings, \.menuSearchDisabledApps)
        case .navigationCommands: return launcher.commandsBinding(for: key, owner: .navigation)
        case .windowPickerChord: return bind(settings, \.windowPickerChord)
        case .windowPickerAppChord: return bind(settings, \.windowPickerAppChord)
        case .windowPickerShowsPreviews: return bind(settings, \.windowPickerShowsPreviews)
        case .windowPickerStartMode: return bind(settings, \.windowPickerStartMode)
        case .windowPickerStackDelay: return bind(settings, \.windowPickerStackDelay)
        case .windowPickerMaxColumns: return bind(settings, \.windowPickerMaxColumns)
        case .windowPickerMaxRows: return bind(settings, \.windowPickerMaxRows)
        case .windowPickerSearchEnabled: return bind(settings, \.windowPickerSearchEnabled)
        case .windowPickerShowsHints: return bind(settings, \.windowPickerShowsHints)
        case .windowPickerTileSize: return bind(settings, \.windowPickerTileSize)
        case .windowPickerMaxWidth: return bind(settings, \.windowPickerMaxWidth)
        case .windowPickerMaxHeight: return bind(settings, \.windowPickerMaxHeight)
        case .windowManagementEnabled: return bind(settings, \.windowManagementEnabled)
        case .windowManagementShowInLauncher:
            return bind(settings, \.windowManagementShowInLauncher)
        case .windowSnapByDragging: return bind(settings, \.windowSnapByDragging)
        case .windowRestoreOnDrag: return bind(settings, \.windowRestoreOnDrag)
        case .windowHighlightActivationAreas:
            return bind(settings, \.windowHighlightActivationAreas)
        case .windowActivationEdgeWidth:
            return bind(settings, \.windowActivationEdgeWidth) {
                WindowDragSnap.edgeWidthRange.contains($0) ? $0 : nil
            }
        case .windowActivationAreaScale:
            return bind(settings, \.windowActivationAreaScale) {
                WindowDragSnap.areaScaleRange.contains($0) ? $0 : nil
            }
        case .windowDisabledActivationAreas:
            return bind(settings, \.windowDisabledActivationAreas) {
                WindowDragSnap.normalizedDisabledZones($0)
            }
        case .windowGreenButtonMenu: return bind(settings, \.windowGreenButtonMenu)
        case .windowGreenButtonTarget: return bind(settings, \.windowGreenButtonTarget)
        case .windowGreenButtonHoverDelay:
            return bind(settings, \.windowGreenButtonHoverDelay) {
                WindowTrafficLightButton.hoverDelayRange.contains($0) ? $0 : nil
            }
        case .windowGap:
            return bind(settings, \.windowGap) {
                WindowPlacementEngine.gapRange.contains($0) ? $0 : nil
            }
        case .windowFitTightlyToEdges: return bind(settings, \.windowFitTightlyToEdges)
        case .windowCycle: return bind(settings, \.windowCycle)
        case .windowWrapsDisplays: return bind(settings, \.windowWrapsDisplays)
        case .windowKeepsProportions: return bind(settings, \.windowKeepsProportions)
        case .windowLayoutsShowInLauncher: return bind(settings, \.windowLayoutsShowInLauncher)
        case .windowRoomsShowInLauncher: return bind(settings, \.windowRoomsShowInLauncher)
        case .windowShortcuts: return windowManagement.commandShortcutsBinding(for: key)
        case .windowAliases: return windowManagement.commandAliasesBinding(for: key)
        case .customWindowSizes: return windowManagement.customSizesBinding(for: key)
        case .windowLayouts: return windowManagement.layoutsBinding(for: key)
        case .windowRooms: return windowManagement.roomsBinding(for: key)
        case .windowManagementCommands:
            return launcher.commandsBinding(for: key, owner: .windowManagement)
        case .clipboardEnabled: return bind(settings, \.clipboardEnabled)
        case .clipboardRetention: return bind(settings, \.clipboardRetention)
        case .clipboardDefaultAction: return bind(settings, \.clipboardDefaultAction)
        case .clipboardShowsEmptyCategories: return bind(settings, \.clipboardShowsEmptyCategories)
        case .clipboardDisabledApps: return bind(settings, \.clipboardDisabledApps)
        case .clipboardCommands: return launcher.commandsBinding(for: key, owner: .clipboard)
        case .emojiSkinTone: return bind(settings, \.emojiSkinTone)
        case .emojiGridColumns: return bind(settings, \.emojiGridColumns)
        case .emojiCommands: return launcher.commandsBinding(for: key, owner: .emoji)
        case .calendarShowInLauncher: return bind(settings, \.calendarShowInLauncher)
        case .calendarLauncherLimit: return bind(settings, \.calendarLauncherLimit)
        case .calendarSpan: return bind(settings, \.calendarSpan)
        case .joinWindowMinutes: return bind(settings, \.joinWindowMinutes)
        case .autoJoinConfirms: return bind(settings, \.autoJoinConfirms)
        case .autoJoinNamedProvidersOnly: return bind(settings, \.autoJoinNamedProvidersOnly)
        case .meetingBrowser: return bind(settings, \.meetingBrowserBundleID)
        case .calendarMenuBarDisplay: return bind(settings, \.calendarMenuBarDisplay)
        case .menuBarEvents: return bind(settings, \.menuBarEvents)
        case .menuBarLinkedEventsOnly: return bind(settings, \.menuBarLinkedEventsOnly)
        case .calendarMenuBarHidesWhenEmpty: return bind(settings, \.calendarMenuBarHidesWhenEmpty)
        case .hideCurrentEvent: return bind(settings, \.hideCurrentEvent)
        case .calendarCommands: return launcher.commandsBinding(for: key, owner: .calendar)
        case .terminalShowInLauncher: return bind(settings, \.terminalShowInLauncher)
        case .terminalLoadsShellEnvironment: return bind(settings, \.terminalLoadsShellEnvironment)
        case .terminalDetectionBehavior: return bind(settings, \.terminalDetectionBehavior)
        case .terminalColorTheme: return bind(settings, \.terminalColorTheme)
        case .terminalExternalApp: return bind(settings, \.terminalExternalApp)
        case .terminalShortcuts: return bind(settings, \.terminalShortcuts)
        case .terminalCommands: return launcher.commandsBinding(for: key, owner: .terminal)
        case .extensionsShowInLauncher: return bind(settings, \.extensionsShowInLauncher)
        }
    }

    /// A folder is absolute or under `~/`; null puts it back in Application Support.
    private static func folder(_ path: String?) -> String?? {
        guard let path else { return .some(nil) }
        return AppPaths.isFolderPath(path) ? path : nil
    }
}

extension PopToRootTimeout: SettingsFileRawValue {}
extension EscapeKeyBehavior: SettingsFileRawValue {}
extension CommandID: SettingsFileRawValue {}
extension NotchShortcut: SettingsFileRawValue {}
extension AppAppearance: SettingsFileRawValue {}
extension AppLanguage: SettingsFileRawValue {}
extension InterfaceSize: SettingsFileRawValue {}
extension HyperKeyPhysicalKey: SettingsFileRawValue {}
extension HyperKeyQuickPress: SettingsFileRawValue {}
extension CalcNumberStyle: SettingsFileRawValue {}
extension SearchSensitivity: SettingsFileRawValue {}
extension WindowCycle: SettingsFileRawValue {}
extension WindowPickerChord: SettingsFileRawValue {}
extension WindowPickerStackDelay: SettingsFileRawValue {}
extension WindowPickerGridLimit: SettingsFileRawValue {}
extension WindowPickerMode: SettingsFileRawValue {}
extension WindowPickerTileSize: SettingsFileRawValue {}
extension WindowPickerScreenShare: SettingsFileRawValue {}
extension WindowTrafficLightButton: SettingsFileRawValue {}
extension ClipboardDefaultAction: SettingsFileRawValue {}
extension SnippetDefaultAction: SettingsFileRawValue {}
extension EmojiSkinTone: SettingsFileRawValue {}
extension EmojiGridColumns: SettingsFileRawValue {}
extension DictationModel: SettingsFileRawValue {}
extension DictationMode: SettingsFileRawValue {}
extension DictationDestination: SettingsFileRawValue {}
extension DictationIdleRelease: SettingsFileRawValue {}
extension JoinWindow: SettingsFileRawValue {}
extension TerminalDetectionBehavior: SettingsFileRawValue {}
extension TerminalColorTheme: SettingsFileRawValue {}
extension ExternalTerminalApp: SettingsFileRawValue {}

extension TerminalShortcuts: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let members = settingsJSON.members else { return nil }
        var parsed: [TerminalShortcutAction: TerminalKeyChord?] = [:]
        for member in members {
            guard let action = TerminalShortcutAction(rawValue: member.key),
                parsed[action] == nil
            else { return nil }
            if member.value == .null {
                parsed[action] = .some(nil)
            } else if let text = member.value.string, let chord = TerminalKeyChord(text: text) {
                parsed[action] = .some(chord)
            } else {
                return nil
            }
        }
        self.init(bindings: parsed)
    }

    var settingsJSON: SettingsFileJSON {
        .object(
            TerminalShortcutAction.allCases.map { action in
                SettingsFileJSON.Member(
                    key: action.rawValue,
                    value: chord(for: action).map { .string($0.text) } ?? .null)
            })
    }
}

extension ClipboardRetention: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .sixMonths: 180
        case .year: 365
        case .forever: "forever"
        }
    }
}

extension AIRetention: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .forever: "forever"
        }
    }
}

extension AIOpensTo: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .recent: "recent"
        case .newConversation: "newConversation"
        }
    }
}

extension AINewChatAfter: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .twoMinutes: 2
        case .fiveMinutes: 5
        case .tenMinutes: 10
        case .thirtyMinutes: 30
        case .never: "never"
        }
    }
}

extension AIToolRounds: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .ten: 10
        case .twentyFive: 25
        case .fifty: 50
        case .hundred: 100
        case .unlimited: "unlimited"
        }
    }
}

extension CalendarLauncherLimit: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .one: 1
        case .three: 3
        case .five: 5
        case .all: "all"
        }
    }
}

extension MeetingSpan: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .today: "today"
        case .todayAndTomorrow: "todayAndTomorrow"
        case .nextSevenDays: "nextSevenDays"
        }
    }
}

extension CalendarMenuBarDisplay: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .disabled: "disabled"
        case .meetingIcon: "meetingIcon"
        case .meetingTitle: "meetingTitle"
        }
    }
}

extension MenuBarEvents: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .today: "today"
        case .two: 2
        case .five: 5
        case .ten: 10
        case .thirty: 30
        }
    }
}

extension HideCurrentEvent: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .dontHide: "never"
        case .automatically: 0
        case .afterFive: 5
        case .afterTen: 10
        case .afterThirty: 30
        }
    }
}
