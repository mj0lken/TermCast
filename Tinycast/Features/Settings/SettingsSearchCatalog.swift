import Foundation

struct SettingsSearchEntry: Identifiable, Hashable, Sendable {
    let tab: SettingsTab
    /// Where picking this result lands; nil for the pane itself, which is its own result.
    let target: SettingsTarget?
    let title: String
    let keywords: [String]

    /// Taking the pane from the target is what makes a row filed under the wrong pane unwritable.
    private init(_ target: SettingsTarget, _ title: String, _ keywords: [String]) {
        self.tab = target.tab
        self.target = target
        self.title = title
        self.keywords = keywords
    }

    /// One setting, which its pane marks with a matching `SettingsRowTitle`.
    init(_ anchor: SettingsAnchor, _ title: LocalizedStringResource, keywords: [String] = []) {
        let localized = title.resolved()
        let english = title.key.replacingOccurrences(of: "Tinycast", with: "Termcast")
        self.init(.row(anchor, localized), localized, keywords + [english])
    }

    /// A whole group, for a result no single row answers — a list, or a section's master switch.
    init(group anchor: SettingsAnchor, _ title: LocalizedStringResource, keywords: [String] = []) {
        let english = title.key.replacingOccurrences(of: "Tinycast", with: "Termcast")
        self.init(.section(anchor), title.resolved(), keywords + [english])
    }

    init(pane: SettingsTab, keywords: [String] = []) {
        self.tab = pane
        self.target = nil
        self.title = pane.title
        self.keywords = keywords
    }

    var anchor: SettingsAnchor? { target?.anchor }

    var id: String { "\(tab.title)/\(anchor?.title ?? "")/\(title)" }

    var breadcrumb: String {
        guard let anchor, anchor.title != tab.title else { return tab.title }
        return "\(tab.title) › \(anchor.title)"
    }
}

/// What Settings offers to search. Hand-written: a `Form` can't be asked what rows it holds, so a
/// new row is searchable only once it is listed here.
enum SettingsSearchCatalog {
    struct Query: Sendable {
        let terms: [FuzzyMatch.Query]

        init(_ raw: String) {
            terms = raw.split(whereSeparator: \Character.isWhitespace).map {
                FuzzyMatch.Query(String($0))
            }
        }

        var isEmpty: Bool { terms.isEmpty }
    }

    static func results(for raw: String, limit: Int = 50) -> [SettingsSearchEntry] {
        let query = Query(raw)
        guard !query.isEmpty else { return [] }
        // Catalog order is the tie-break, so results don't reshuffle between equal-scoring rows.
        return
            entries
            .enumerated()
            .compactMap { item -> (entry: SettingsSearchEntry, score: Int, rank: Int)? in
                guard let score = score(query, item.element) else { return nil }
                return (item.element, score, item.offset)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.rank < $1.rank }
            .prefix(limit)
            .map(\.entry)
    }

    /// Every term must land somewhere; a term matched in the title outranks one found off it.
    private static func score(_ query: Query, _ entry: SettingsSearchEntry) -> Int? {
        var titleScore = 0
        var titleMatches = 0
        for term in query.terms {
            if let match = FuzzyMatch.match(term, candidate: entry.title) {
                titleMatches += 1
                titleScore += match.score
                continue
            }
            guard
                entry.keywords.contains(where: { FuzzyMatch.match(term, candidate: $0) != nil })
                    || FuzzyMatch.match(term, candidate: entry.breadcrumb) != nil
            else { return nil }
        }

        let band: Int
        if titleMatches == query.terms.count {
            band = 2_000_000
        } else if titleMatches > 0 {
            band = 1_000_000
        } else {
            band = 0
        }
        // A pane outranks its own rows, so a bare "clipboard" lands on the pane rather than a row.
        return band + titleScore + (entry.anchor == nil ? 500_000 : 0)
    }

    // MARK: - The index
    // Pane order, then section order within a pane, so this reads as a table of contents.

    static let entries: [SettingsSearchEntry] =
        general + applications + systemSettings + systemActions + commands + quicklinks
        + appleShortcuts + fallbacks + clipboard + snippets + terminal + fileSearch
        + windowManagement + notch + navigation + windowSwitcher + notes + calendar + emoji + ai
        + quickActions + dictation + extensions + permissions
        + backup + about

    private static let general: [SettingsSearchEntry] = [
        .init(pane: .general, keywords: ["preferences", "settings"]),
        .init(
            .generalGlobalShortcuts, "Show Launcher",
            keywords: ["hotkey", "shortcut", "summon", "palette"]),
        .init(
            .generalGeneral, "Language",
            keywords: ["localization", "translation", "locale", "region"]),
        .init(
            .generalGeneral, "Launch at login",
            keywords: ["startup", "login item", "start", "boot"]),
        .init(
            .generalGeneral, "Show in menu bar",
            keywords: ["menubar", "status item", "icon", "hide"]),
        .init(
            .generalGeneral, "Automatically check for updates",
            keywords: ["software", "update", "automatic", "disable", "popup"]),
        .init(
            .generalGeneral, "Pop to Root Search",
            keywords: ["reset", "timeout", "back"]),
        .init(
            .generalGeneral, "Escape Key Behavior",
            keywords: ["escape", "esc", "back", "close", "navigate"]),
        .init(
            .generalGeneral, "Auto-switch input source",
            keywords: ["keyboard", "layout", "language", "abc"]),
        .init(
            .generalAppearance, "Appearance",
            keywords: ["dark", "light", "mode", "theme"]),
        .init(
            .generalAppearance, "Show animations",
            keywords: ["motion", "transitions", "reduce motion", "effects", "instant"]),
        .init(
            .generalAppearance, "Interface size",
            keywords: ["text size", "font size", "scale", "zoom", "bigger", "larger", "legible"]),
        .init(
            .generalAppearance, "Window mode",
            keywords: ["compact", "expanded", "slim", "search bar", "small"]),
        .init(
            group: .generalCompactShortcuts, "Compact Shortcuts",
            keywords: ["slots", "buttons", "reorder", "clipboard", "emoji", "notes", "schedule", "quick ai"]),
        .init(
            .generalAppearance, "Follow the cursor across displays",
            keywords: ["monitor", "screen", "pointer", "multi display"]),
        .init(
            .generalAppearance, "Drag to move the launcher",
            keywords: ["move", "position", "window"]),
        .init(
            .generalHyperKey, "Hyper Key",
            keywords: ["modifier", "remap", "caps lock", "capslock"]),
        .init(
            .generalHyperKey, "Quick Press",
            keywords: ["tap", "escape", "single press"]),
        .init(
            .generalHyperKey, "Include Shift (⇧)",
            keywords: ["modifier", "chord"]),
        .init(
            .generalHyperKey, "Secure Input Compatibility",
            keywords: ["password", "secure input", "right control"]),
        .init(
            .generalHyperKey, "Trackpad Scroll Sliders",
            keywords: ["brightness", "backlight", "volume", "sound", "touchpad", "scroll", "gesture"]),
        .init(
            .generalCalculator, "Number format",
            keywords: ["decimal", "comma", "separator", "locale", "region", "thousands"]),
        .init(
            .generalSearch, "Show suggestions",
            keywords: ["frequent", "recent", "recommended", "empty", "root search"]),
        .init(
            .generalSearch, "Search sensitivity",
            keywords: ["fuzzy", "strict", "loose", "matching", "typo", "root search"]),
        .init(
            .generalSearch, "Learned ranking",
            keywords: ["reset", "history", "order", "privacy"]),
        .init(
            group: .generalDeepLinks, "Deeplinks",
            keywords: [
                "link", "url", "termcast://", "tinycast://", "allow", "karabiner", "shortcuts",
                "automation"
            ])
    ]

    private static let applications: [SettingsSearchEntry] = [
        .init(pane: .applications, keywords: ["apps", "index", "launcher"]),
        .init(
            .applicationsApplications, "Enable Applications",
            keywords: ["hide apps", "visibility"]),
        .init(
            group: .applicationsSearchScopes, "Search Scopes",
            keywords: ["folders", "indexed", "locations", "add folder"]),
        .init(
            group: .applicationsApplications, "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "per app", "hide"])
    ]

    private static let systemSettings: [SettingsSearchEntry] = [
        .init(
            pane: .systemSettings,
            keywords: ["panes", "preferences", "macos"]),
        .init(
            .systemSettingsSystemSettings, "Enable System Settings",
            keywords: ["hide panes", "visibility"])
    ]

    private static let systemActions: [SettingsSearchEntry] = [
        .init(
            pane: .systemActions,
            keywords: ["sleep", "lock", "restart", "shut down", "empty trash"]),
        .init(
            .systemActionsSystemActions, "Enable System Actions",
            keywords: ["hide", "visibility"])
    ]

    private static let commands: [SettingsSearchEntry] = [
        .init(
            pane: .commands,
            keywords: ["custom", "script", "shell", "terminal"]),
        .init(
            .commandsCommands, "Enable Commands",
            keywords: ["hide", "visibility"]),
        .init(
            .commandsCustomCommands, "Enable custom commands",
            keywords: ["script", "shell"]),
        .init(
            .commandsCustomCommands, "Add Custom Command",
            keywords: ["new", "script", "shell", "shortcut"]),
        .init(
            .commandsCustomCommands, "Import Raycast Scripts",
            keywords: ["raycast", "script", "folder", "directory", "migrate"])
    ]

    private static let quicklinks: [SettingsSearchEntry] = [
        .init(pane: .quicklinks, keywords: ["url", "bookmark", "link"]),
        .init(
            .quicklinksQuicklinks, "Enable quicklinks",
            keywords: ["url", "bookmark"]),
        .init(
            .quicklinksQuicklinks, "Add Quicklink",
            keywords: ["new", "url", "bookmark", "alias"]),
        .init(
            group: .quicklinksCommands, "Quicklink commands",
            keywords: ["shortcut", "launcher", "search", "import", "export"]),
        .init(
            .quicklinksBehaviour, "Open in a new window",
            keywords: ["browser", "tab"]),
        .init(
            .quicklinksBehaviour, "Pass selected text as argument",
            keywords: ["selection", "hotkey", "shortcut", "argument"]),
        .init(
            .quicklinksBehaviour, "Confirm before deleting",
            keywords: ["ask", "delete", "prompt"]),
        .init(
            .quicklinksImportExport, "Import quicklinks",
            keywords: ["json", "restore"]),
        .init(
            .quicklinksImportExport, "Export quicklinks",
            keywords: ["json", "backup"])
    ]

    private static let appleShortcuts: [SettingsSearchEntry] = [
        .init(pane: .appleShortcuts, keywords: ["shortcuts app", "automation", "workflow"]),
        .init(
            .appleShortcutsAppleShortcuts, "Enable Apple Shortcuts",
            keywords: ["shortcuts app", "automation", "workflow"]),
        .init(
            group: .appleShortcutsShortcuts, "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "hide"])
    ]

    private static let fallbacks: [SettingsSearchEntry] = [
        .init(
            pane: .fallbacks,
            keywords: ["no results", "empty", "search web", "order"])
    ]

    private static let ai: [SettingsSearchEntry] = [
        .init(
            pane: .ai,
            keywords: [
                "chat", "quick ai", "llm", "model", "openai", "anthropic", "gemini", "antigravity"
            ]),
        .init(.aiAI, "Enable AI", keywords: ["chat", "llm"]),
        .init(
            .aiProviders, "Providers",
            keywords: [
                "sign in", "connect", "codex", "claude", "antigravity", "agy", "gemini", "grok",
                "xai", "opencode", "cursor", "agent", "api key", "connection", "base url",
                "openai", "anthropic", "google", "ollama", "models", "hide models"
            ]),
        .init(
            .aiDefault, "Default model",
            keywords: ["llm", "gpt", "claude", "antigravity", "gemini", "grok"]),
        .init(.aiDefault, "Reasoning effort", keywords: ["thinking", "effort", "deepseek"]),
        .init(.aiChat, "Web search", keywords: ["browse", "internet"]),
        .init(.aiChat, "Suggested replies", keywords: ["choices", "chips", "follow-up", "buttons"]),
        .init(.aiChat, "Expand thinking", keywords: ["reasoning", "thoughts", "collapse", "fold", "unfold"]),
        .init(.aiChat, "Tool call rounds", keywords: ["mcp", "tools", "limit", "loop", "agent", "unlimited"]),
        .init(
            .aiConversations, "Opens to",
            keywords: ["new chat", "last", "summon", "resume", "window", "quick ai"]),
        .init(
            .aiConversations, "Start a new conversation after",
            keywords: ["idle", "timeout", "fresh"]),
        .init(
            .aiConversations, "Keep conversations",
            keywords: ["retention", "delete", "history", "privacy"]),
        .init(
            .aiSystemPrompt, "Send a system prompt",
            keywords: ["instructions", "persona"]),
        .init(
            group: .aiChatPresets, "Chat Presets",
            keywords: ["persona", "instructions", "system prompt"]),
        .init(
            .aiChatPresets, "Add Chat Preset",
            keywords: ["new", "persona", "instructions", "system prompt"]),
        .init(
            .aiMCPServers, "Enable MCP servers",
            keywords: ["tools", "model context protocol"]),
        .init(
            .aiMCPServers, "Add MCP Server",
            keywords: ["tools", "model context protocol", "stdio"]),
        .init(
            group: .aiCommands, "AI commands",
            keywords: ["shortcut", "launcher", "chat"])
    ]

    private static let quickActions: [SettingsSearchEntry] = [
        .init(
            pane: .quickActions,
            keywords: ["selected text", "rewrite", "translate", "summarize"]),
        .init(
            .quickActionsQuickActions, "Enable Quick Actions",
            keywords: ["selected text", "accessibility"]),
        .init(
            group: .quickActionsActions, "Actions",
            keywords: ["shortcut", "replace", "preview", "customize"]),
        .init(
            .quickActionsActions, "Add Quick Action",
            keywords: ["new", "custom", "prompt", "instructions", "alias"]),
        .init(
            .quickActionsModel, "Model",
            keywords: ["llm", "ai", "default"]),
        .init(
            .quickActionsTranslate, "Translate to",
            keywords: ["language", "locale"])
    ]

    private static let dictation: [SettingsSearchEntry] = [
        .init(pane: .dictation, keywords: ["speech", "voice", "transcription", "microphone"]),
        .init(.dictationDictation, "Enable Dictation"),
        .init(.dictationCommands, "Shortcut behavior"),
        .init(.dictationCommands, "Shortcut"),
        .init(.dictationCommands, "Play sounds", keywords: ["sound", "chime", "beep", "audio", "feedback"]),
        .init(.dictationModel, "Model"),
        .init(.dictationModel, "Engine", keywords: ["parakeet", "redux", "ultra", "qwen"]),
        .init(.dictationModel, "Language"),
        .init(.dictationMemory, "Release model from memory"),
        .init(.dictationOutput, "Microphone"),
        .init(.dictationOutput, "When finished"),
        .init(.dictationOutput, "Adapt capitalization", keywords: ["uppercase", "lowercase", "sentence"]),
        .init(.dictationOutput, "Insert while recording", keywords: ["live", "streaming", "chunk", "pause"])
    ]

    private static let fileSearch: [SettingsSearchEntry] = [
        .init(
            pane: .fileSearch,
            keywords: ["files", "folders", "find", "disk"]),
        .init(
            .fileSearchFileSearch, "Enable File Search",
            keywords: ["index", "disk", "show in launcher", "root search"]),
        .init(
            group: .fileSearchFullDiskAccess, "Full Disk Access",
            keywords: ["permission", "privacy", "grant", "fda"]),
        .init(
            group: .fileSearchIndex, "File index",
            keywords: ["rebuild", "refresh", "reindex", "indexed files"]),
        .init(
            group: .fileSearchCommands, "File search commands",
            keywords: ["shortcut", "launcher"]),
        .init(
            group: .fileSearchSearchScopes, "Search Scopes",
            keywords: ["folders", "locations", "home", "whole disk", "add folder"]),
        .init(
            group: .fileSearchIgnorePatterns, "Ignore Patterns",
            keywords: ["exclude", "glob", "node_modules", "skip", "ignore folder"])
    ]

    private static let notes: [SettingsSearchEntry] = [
        .init(pane: .notes, keywords: ["markdown", "scratchpad", "floating"]),
        .init(
            .notesNotes, "Enable Notes",
            keywords: ["markdown", "scratchpad"]),
        .init(
            .notesOptions, "Render Markdown",
            keywords: ["markdown", "formatting", "preview", "raw", "source"]),
        .init(
            .notesOptions, "Show Formatting Bar",
            keywords: ["toolbar", "format bar", "buttons", "bold", "heading", "markdown"]),
        .init(
            .notesOptions, "Show in Menu Bar",
            keywords: ["status bar", "menu bar icon", "status item", "toolbar icon"]),
        .init(
            .notesOptions, "Notes Folder",
            keywords: ["location", "path", "dotfiles", "files", "markdown"]),
        .init(
            group: .notesCommands, "Notes commands",
            keywords: ["shortcut", "new note", "search notes"])
    ]

    private static let snippets: [SettingsSearchEntry] = [
        .init(
            pane: .snippets,
            keywords: ["expansion", "keyword", "text replacement", "template"]),
        .init(
            .snippetsSnippets, "Enable snippets",
            keywords: ["expansion", "keystrokes", "accessibility"]),
        .init(
            .snippetsSnippets, "Default action",
            keywords: ["enter", "return", "paste", "copy", "primary"]),
        .init(
            group: .snippetsCommands, "Snippet commands",
            keywords: ["shortcut", "hotkey", "launcher", "browser"]),
        .init(
            .snippetsLibrary, "New Snippet",
            keywords: ["add", "keyword", "expansion"]),
        .init(
            .snippetsLibrary, "Snippets Folder",
            keywords: ["reveal", "finder", "markdown", "files", "location", "path", "dotfiles"])
    ]

    private static let notch: [SettingsSearchEntry] = [
        .init(
            pane: .notch,
            keywords: ["notch", "hud", "osd", "volume", "brightness", "backlight", "dynamic island", "shelf"]),
        .init(
            .notchNotch, "Replace system volume & brightness HUD",
            keywords: ["notch", "hud", "osd", "volume", "brightness", "backlight", "dynamic island", "sound"]),
        .init(
            .notchNotch, "Show power & charging notifications",
            keywords: ["battery", "magsafe", "charger", "plugged", "power"]),
        .init(
            .notchNotch, "Show input source changes",
            keywords: ["keyboard", "language", "layout", "input", "switch"]),
        .init(
            .notchShelf, "Show live activities around the closed notch",
            keywords: [
                "live", "activity", "music", "equalizer", "meeting", "countdown", "timer", "dictation",
                "microphone", "camera", "terminal", "dynamic island"
            ]),
        .init(
            .notchShelf, "Enable Open Notch (Media, Calendar & Shelf)",
            keywords: ["now playing", "music", "spotify", "calendar", "upcoming", "shelf", "airdrop", "tray"]),
        .init(
            .notchShelf, "Open notch on hover",
            keywords: ["hover", "cursor", "mouse", "expand"]),
        .init(
            .notchShelf, "Hover delay",
            keywords: ["delay", "dwell", "hover"]),
        .init(
            .notchShelf, "Haptic feedback",
            keywords: ["trackpad", "vibration", "taptic"]),
        .init(
            .notchShelf, "Remember last tab",
            keywords: ["tab", "home", "shelf"]),
        .init(
            .notchNotch, "Show percentage",
            keywords: ["percent", "number", "hud"]),
        .init(
            .notchNotch, "Tint progress bar with accent colour",
            keywords: ["accent", "color", "colour", "tint", "bar"]),
        .init(
            .notchContent, "Show Now Playing",
            keywords: ["media", "music", "spotify", "player"]),
        .init(
            .notchContent, "Show calendar",
            keywords: ["events", "meetings", "agenda"]),
        .init(
            .notchContent, "Hide all-day events",
            keywords: ["all day", "birthdays", "holidays"]),
        .init(
            .notchContent, "Show battery indicator",
            keywords: ["battery", "charge", "power"]),
        .init(
            group: .notchShortcuts, "Shortcuts",
            keywords: [
                "buttons", "header", "clipboard", "notebook", "notes", "camera", "window management",
                "timer", "settings", "cog", "reorder"
            ]),
        .init(
            .notchPreview, "Preview Notch HUD",
            keywords: ["notch", "hud", "test", "preview"]),
        .init(
            .notchPreview, "Preview Open Notch",
            keywords: ["open", "tray", "shelf", "media", "preview"])
    ]

    private static let navigation: [SettingsSearchEntry] = [
        .init(
            pane: .navigation,
            keywords: ["window", "switch", "menu bar", "focus", "raise"]),
        .init(
            .navigationNavigation, "Enable navigation",
            keywords: ["window switcher", "menu bar", "accessibility"]),
        .init(
            group: .navigationCommands, "Navigation commands",
            keywords: ["shortcut", "hotkey", "alias", "launcher"]),
        .init(
            .navigationMenuSearch, "Show Apple menu items",
            keywords: ["apple menu", "about this mac", "recent items", "sleep", "logo"]),
        .init(
            .navigationMenuSearch, "Excluded Applications",
            keywords: ["exclude", "password manager", "ignore", "privacy", "menu bar"])
    ]

    private static let windowSwitcher: [SettingsSearchEntry] = [
        .init(
            pane: .windowSwitcher,
            keywords: ["command tab", "cmd tab", "alt tab", "thumbnails", "previews", "windows"]),
        .init(
            .windowSwitcherWindowSwitcher, "Enable the window switcher",
            keywords: ["command tab", "cmd tab", "alt tab", "switch", "windows", "thumbnails"]),
        .init(
            .windowSwitcherShortcuts, "All windows",
            keywords: ["command tab", "shortcut", "hotkey", "modifier", "key binding"]),
        .init(
            .windowSwitcherShortcuts, "Front app’s windows",
            keywords: ["cycle", "same app", "shortcut", "hotkey", "modifier", "key binding"]),
        .init(
            .windowSwitcherLayout, "Window size",
            keywords: ["tile", "thumbnail", "small", "large", "scale"]),
        .init(
            .windowSwitcherLayout, "Windows per row",
            keywords: ["columns", "grid", "maximum"]),
        .init(
            .windowSwitcherLayout, "Rows",
            keywords: ["grid", "maximum"]),
        .init(
            .windowSwitcherLayout, "Maximum width",
            keywords: ["panel", "screen", "percent", "size"]),
        .init(
            .windowSwitcherLayout, "Maximum height",
            keywords: ["panel", "screen", "percent", "size"]),
        .init(
            .windowSwitcherOptions, "Show window previews",
            keywords: ["thumbnails", "screen recording", "screenshots", "live"]),
        .init(
            .windowSwitcherOptions, "Group windows by app",
            keywords: ["stack", "grouping", "shift", "collapse"]),
        .init(
            .windowSwitcherOptions, "Open a selected group after",
            keywords: ["delay", "milliseconds", "expand", "dwell", "group"])
    ]

    private static let windowManagement: [SettingsSearchEntry] = [
        .init(
            pane: .windowManagement,
            keywords: ["tile", "halves", "thirds", "maximize", "snap", "layouts", "arrangement"]),
        .init(
            .windowManagementWindowManagement, "Enable window management",
            keywords: ["tile", "accessibility"]),
        .init(
            .windowManagementMouse, "Snap windows by dragging",
            keywords: ["mouse", "drag", "edges", "corners", "magnet", "preview", "tile"]),
        .init(
            .windowManagementMouse, "Restore windows to original size",
            keywords: ["mouse", "drag", "unsnap", "restore", "resize", "original"]),
        .init(
            .windowManagementMouse, "Highlight activation areas when dragging",
            keywords: ["mouse", "drag", "activation", "zones", "edges", "pills", "magnet"]),
        .init(
            .windowManagementMouse, "Screen edge width",
            keywords: ["mouse", "drag", "activation", "margin", "sensitivity", "edges", "magnet"]),
        .init(
            .windowManagementMouse, "Activation area scale",
            keywords: ["mouse", "drag", "activation", "corners", "zones", "scale", "magnet"]),
        .init(
            .windowManagementMouse, "Activation areas",
            keywords: [
                "mouse", "drag", "zones", "corners", "thirds", "quarters", "halves", "magnet"
            ]),
        .init(
            .windowManagementGreenButton, "Show green button menu",
            keywords: [
                "zoom", "traffic light", "fullscreen button", "hover", "dropdown", "magnet"
            ]),
        .init(
            .windowManagementGreenButton, "Hover button",
            keywords: ["green", "yellow", "zoom", "minimize", "traffic light", "magnet"]),
        .init(
            .windowManagementGreenButton, "Green button hover delay",
            keywords: ["zoom", "traffic light", "hover", "delay", "milliseconds", "magnet"]),
        .init(
            .windowManagementOptions, "Cycling",
            keywords: ["repeat", "thirds", "halves", "displays", "monitor", "screens"]),
        .init(
            .windowManagementOptions, "Gap between windows",
            keywords: ["padding", "spacing", "margin", "points"]),
        .init(
            .windowManagementOptions, "Fit tightly to screen edges",
            keywords: ["gap", "outer", "margins", "padding", "edges", "inner", "magnet"]),
        .init(
            .windowManagementOptions, "Wrap around displays",
            keywords: ["next display", "previous display", "monitor", "screens", "loop"]),
        .init(
            .windowManagementOptions, "Keep aspect ratio",
            keywords: ["next display", "previous display", "monitor", "scale", "resize"]),
        .init(
            .windowManagementOptions, "Shortcut preset",
            keywords: ["rectangle", "magnet", "spectacle", "defaults", "import", "shortcuts"]),
        .init(
            group: .windowManagementOptions, "Window commands",
            keywords: ["shortcut", "alias", "left half", "maximize", "center"]),
        .init(
            group: .windowManagementLayoutCommands, "Layout and room commands",
            keywords: [
                "shortcut", "launcher", "create layout", "capture", "switch room", "create room"
            ]),
        .init(
            group: .windowManagementLayouts, "Window Layouts",
            keywords: [
                "layout", "arrangement", "workspace", "preset", "restore windows",
                "multi display", "monitor", "alias"
            ]),
        .init(
            .windowManagementLayouts, "Show layouts in launcher",
            keywords: ["hide", "visibility", "search"]),
        .init(
            .windowManagementLayouts, "New Layout",
            keywords: ["add", "create", "arrangement", "preset"]),
        .init(
            .windowManagementLayouts, "Create Layout from Current Windows",
            keywords: ["capture", "snapshot", "current", "save arrangement"]),
        .init(
            group: .windowManagementRooms, "Rooms",
            keywords: [
                "room", "project", "workspace", "tile", "focus", "columns", "grid", "stack",
                "hide other apps", "switch project", "alias"
            ]),
        .init(
            .windowManagementRooms, "Show rooms in launcher",
            keywords: ["hide", "visibility", "search"]),
        .init(
            .windowManagementRooms, "New Room",
            keywords: ["add", "create", "project", "windows"]),
        .init(
            group: .windowManagementCustomSizes, "Custom Sizes",
            keywords: [
                "custom", "size", "resize", "dimensions", "pixels", "points", "percent",
                "fractional", "grid", "cells", "alias"
            ]),
        .init(
            .windowManagementCustomSizes, "New Custom Size",
            keywords: ["add", "create", "resize", "window size"])
    ]

    private static let clipboard: [SettingsSearchEntry] = [
        .init(
            pane: .clipboard,
            keywords: ["paste", "history", "copy", "pasteboard"]),
        .init(
            .clipboardClipboard, "Enable Clipboard History",
            keywords: ["disable", "turn off", "monitor", "record", "privacy"]),
        .init(
            group: .clipboardCommands, "Clipboard commands",
            keywords: ["shortcut", "hotkey", "launcher", "paste", "browser"]),
        .init(
            .clipboardHistory, "Keep history for",
            keywords: ["retention", "delete", "privacy", "expire"]),
        .init(
            .clipboardHistory, "Search text in images and PDFs",
            keywords: ["OCR", "recognize", "scan", "screenshot", "background", "idle"]),
        .init(
            .clipboardHistory, "Default action",
            keywords: ["enter", "return", "paste", "copy", "primary"]),
        .init(
            .clipboardHistory, "Show empty categories",
            keywords: ["sidebar", "filter", "apps", "code", "documents", "files", "hidden", "all"]),
        .init(
            group: .clipboardDisabledApplications, "Excluded Applications",
            keywords: ["exclude", "password manager", "ignore", "privacy"]),
        .init(
            .clipboardDisabledApplications, "Clear history",
            keywords: ["delete", "erase", "wipe"])
    ]

    private static let emoji: [SettingsSearchEntry] = [
        .init(
            pane: .emoji,
            keywords: ["picker", "character", "unicode", "smiley"]),
        .init(
            group: .emojiCommands, "Emoji commands",
            keywords: ["shortcut", "hotkey", "launcher", "picker"]),
        .init(
            .emojiAppearance, "Emoji Skin Tone",
            keywords: ["colour", "color", "fitzpatrick", "default"]),
        .init(
            .emojiAppearance, "Column Count",
            keywords: ["columns", "density", "zoom", "six", "eight", "ten"])
    ]

    private static let terminal: [SettingsSearchEntry] = [
        .init(
            pane: .terminal,
            keywords: ["shell", "zsh", "bash", "cli", "command", "tabs"]),
        .init(
            .terminalTerminal, "Enable Terminal",
            keywords: ["shell", "zsh", "tabs", "shift enter"]),
        .init(
            .terminalOptions, "Detected commands",
            keywords: ["auto open", "top result", "launcher", "cli", "shell"]),
        .init(
            .terminalOptions, "Terminal look",
            keywords: [
                "color theme", "appearance", "default", "paper", "slate", "midnight",
                "light", "dark", "ansi", "truecolor", "palette"
            ]),
        .init(
            .terminalOptions, "External terminal",
            keywords: ["ghostty", "iterm", "warp", "kitty", "alacritty", "wezterm", "handoff"]),
        .init(
            .terminalOptions, "Load shell environment",
            keywords: ["zshrc", "aliases", "path", "shell"]),
        .init(
            .terminalOptions, "Recommended shell config",
            keywords: ["init.zsh", "oh my zsh", "colors", "ls", "aliases", "readability"]),
        .init(
            group: .terminalCommands, "Terminal commands",
            keywords: ["shortcut", "hotkey", "open terminal", "hyper"]),
        .init(
            .terminalShortcuts, "Toggle Hybrid Mode",
            keywords: ["shortcut", "hotkey", "cmd t", "hybrid mode", "terminal mode", "launcher"]),
        .init(
            .terminalShortcuts, "Switch Hybrid / Terminal Mode",
            keywords: ["shortcut", "hotkey", "cmd i", "switch", "hyper", "hybrid", "terminal mode"]),
        .init(
            .terminalShortcuts, "Copy Latest Output",
            keywords: ["shortcut", "hotkey", "shift cmd c", "copy", "output", "clipboard"]),
        .init(
            .terminalShortcuts, "Continue in External Terminal",
            keywords: ["shortcut", "hotkey", "cmd o", "ghostty", "warp", "iterm", "handoff"]),
        .init(
            .terminalShortcuts, "Run in New Tab",
            keywords: ["shortcut", "shift return", "enter", "new tab"]),
        .init(
            .terminalShortcuts, "Cycle Recent Folder",
            keywords: ["shortcut", "shift tab", "working directory", "cwd"]),
        .init(
            .terminalShortcuts, "New Tab",
            keywords: ["shortcut", "cmd n", "tab"]),
        .init(
            .terminalShortcuts, "Close Tab",
            keywords: ["shortcut", "ctrl x", "tab"]),
        .init(
            .terminalShortcuts, "Stop Command",
            keywords: ["shortcut", "sigint", "cancel", "interrupt"]),
        .init(
            .terminalShortcuts, "Clear Output",
            keywords: ["shortcut", "scrollback", "log", "erase"]),
        .init(
            .terminalShortcuts, "Reset Shortcuts to Defaults",
            keywords: ["default", "restore", "keybindings"]),
        .init(
            .terminalHistory, "Clear Command History",
            keywords: ["up arrow", "down arrow", "previous commands", "recall"]),
        .init(
            .terminalRecentFolders, "Add Folder…",
            keywords: ["working directory", "cwd", "path", "folder"]),
        .init(
            .terminalRecentFolders, "Clear Recent Folders",
            keywords: ["working directory", "cwd", "reset", "history"])
    ]

    private static let calendar: [SettingsSearchEntry] = [
        .init(
            pane: .calendar,
            keywords: ["meetings", "events", "zoom", "join", "schedule"]),
        .init(
            .calendarCalendar, "Join meetings from Tinycast",
            keywords: ["zoom", "meet", "teams", "permission"]),
        .init(
            .calendarCalendar, "Upcoming meetings in launcher",
            keywords: ["count", "limit", "events"]),
        .init(
            .calendarJoining, "Show the meeting card",
            keywords: ["hud", "timing", "early", "reminder"]),
        .init(
            .calendarJoining, "Auto Join Meetings",
            keywords: ["automatic", "start"]),
        .init(
            .calendarJoining, "Only join known meeting services",
            keywords: ["zoom", "meet", "teams", "links", "placeholder", "skip"]),
        .init(
            .calendarJoining, "Confirm before joining",
            keywords: ["ask", "prompt"]),
        .init(
            .calendarJoining, "Camera Preview",
            keywords: ["webcam", "mirror", "video", "check"]),
        .init(
            .calendarJoining, "Open Meeting Links In",
            keywords: ["browser", "chrome", "safari", "firefox", "meet", "web"]),
        .init(
            .calendarMenuBar, "Calendar in Menu Bar",
            keywords: ["status item", "menubar", "date"]),
        .init(
            .calendarMenuBar, "Days to Show",
            keywords: ["tomorrow", "week", "next 7 days", "range", "agenda", "schedule"]),
        .init(
            .calendarMenuBar, "Show Upcoming Events",
            keywords: ["menubar", "next event", "title"]),
        .init(
            .calendarMenuBar, "Only show events with meetings",
            keywords: ["links", "filter", "menubar"]),
        .init(
            .calendarMenuBar, "Hide when there are no upcoming events",
            keywords: ["empty", "idle", "menubar", "space"]),
        .init(
            .calendarMenuBar, "Hide Current Event",
            keywords: ["started", "time left", "menubar"]),
        .init(
            group: .calendarCommands, "Calendar commands",
            keywords: ["shortcut", "launcher", "join", "schedule", "create event"]),
        .init(
            group: .calendarCalendars, "Calendars",
            keywords: ["accounts", "sources", "choose", "icloud", "google"])
    ]

    private static let extensions: [SettingsSearchEntry] = [
        .init(
            pane: .extensions,
            keywords: ["raycast", "plugins", "store", "javascript"]),
        .init(
            .extensionsExtensions, "Enable extensions",
            keywords: ["raycast", "third party", "javascript"]),
        .init(
            .extensionsInstall, "Search extensions",
            keywords: ["store", "browse", "install"]),
        .init(
            .extensionsInstall, "Install from GitHub",
            keywords: ["source", "build", "repository", "package manager", "pnpm", "npm", "yarn", "bun"]),
        .init(
            .extensionsInstall, "Import from Raycast",
            keywords: ["migrate", "existing"]),
        .init(
            .extensionsInstall, "Add from folder",
            keywords: ["local", "develop", "sideload"]),
        .init(
            group: .extensionsInstalled, "Installed extensions",
            keywords: [
                "library", "uninstall", "update", "preferences", "appearance", "alias", "shortcut"
            ]),
        .init(
            group: .extensionsCompatibility, "Compatibility",
            keywords: ["supported", "unsupported", "raycast api"]),
        .init(
            .extensionsStorage, "Leftover files",
            keywords: ["clean up", "disk", "reclaim", "cache"])
    ]

    private static let permissions: [SettingsSearchEntry] = [
        .init(
            pane: .permissions,
            keywords: ["privacy", "tcc", "access", "grant"]),
        .init(
            .permissionsAccessibility, "Accessibility",
            keywords: ["paste", "keystrokes", "privacy", "grant"]),
        .init(
            .permissionsFullDiskAccess, "Full Disk Access",
            keywords: ["files", "folders", "uninstall", "leftovers", "privacy", "grant", "fda"]),
        .init(
            .permissionsCalendars, "Calendars",
            keywords: ["events", "privacy", "grant", "eventkit"]),
        .init(
            .permissionsMicrophone, "Microphone",
            keywords: ["dictation", "recording", "privacy", "grant"])
    ]

    private static let backup: [SettingsSearchEntry] = [
        .init(
            pane: .backup,
            keywords: ["export", "import", "restore", "migrate", "raycast"]),
        .init(
            .backupExport, "Export Backup",
            keywords: ["save", "termcast file", "tinycast file", "archive"]),
        .init(
            .backupImport, "Backup File",
            keywords: ["restore", "choose", "termcast file", "tinycast file"]),
        .init(
            .backupImportFromRaycast, "Raycast Export",
            keywords: ["migrate", "rayconfig", "passphrase"]),
        .init(
            .backupSettingsFile, "Sync settings file",
            keywords: ["settings.json", "config", "json", "dotfiles", ".config", "edit"])
    ]

    private static let about: [SettingsSearchEntry] = [
        .init(
            pane: .about,
            keywords: ["version", "licence", "license", "credits"]),
        .init(
            .aboutAbout, "Check for Updates",
            keywords: ["version", "upgrade", "release"]),
        .init(
            group: .aboutTermcast, "Termcast",
            keywords: ["links", "github", "source", "issues", "website"]),
        .init(
            group: .aboutTinycast, "A Tinycast fork",
            keywords: ["links", "upstream", "github", "website", "tinycast"])
    ]
}
