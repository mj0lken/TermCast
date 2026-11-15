import Foundation

enum ExternalTerminalApp: String, CaseIterable, Codable, Sendable {
    case automatic
    case appleTerminal
    case ghostty
    case iterm2
    case warp
    case kitty
    case alacritty
    case wezterm

    static let detectionOrder: [ExternalTerminalApp] = [
        .ghostty, .iterm2, .warp, .kitty, .alacritty, .wezterm, .appleTerminal
    ]

    var bundleIdentifier: String? {
        switch self {
        case .automatic: nil
        case .appleTerminal: "com.apple.Terminal"
        case .ghostty: "com.mitchellh.ghostty"
        case .iterm2: "com.googlecode.iterm2"
        case .warp: "dev.warp.Warp-Stable"
        case .kitty: "net.kovidgoyal.kitty"
        case .alacritty: "org.alacritty"
        case .wezterm: "com.github.wez.wezterm"
        }
    }

    var displayName: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .appleTerminal: "Terminal"
        case .ghostty: "Ghostty"
        case .iterm2: "iTerm2"
        case .warp: "Warp"
        case .kitty: "kitty"
        case .alacritty: "Alacritty"
        case .wezterm: "WezTerm"
        }
    }

    var usesCommandScriptFile: Bool {
        switch self {
        case .automatic, .appleTerminal, .ghostty, .iterm2, .warp:
            true
        case .kitty, .alacritty, .wezterm:
            false
        }
    }

    var executableName: String? {
        switch self {
        case .kitty: "kitty"
        case .alacritty: "alacritty"
        case .wezterm: "wezterm-gui"
        default: nil
        }
    }

    static func resolve(
        preference: ExternalTerminalApp,
        installedBundleIDs: Set<String>
    ) -> ExternalTerminalApp {
        if preference != .automatic,
            let bundleID = preference.bundleIdentifier,
            installedBundleIDs.contains(bundleID)
        {
            return preference
        }
        for candidate in detectionOrder {
            if let bundleID = candidate.bundleIdentifier, installedBundleIDs.contains(bundleID) {
                return candidate
            }
        }
        return .appleTerminal
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func handoffScript(
        command: String,
        workingDirectory: String,
        displayDirectory: String
    ) -> String {
        let quotedDir = shellQuote(workingDirectory)
        let quotedDisplay = shellQuote(displayDirectory)
        let quotedCommand = shellQuote(command)
        return """
            #!/bin/zsh
            trap 'rm -f -- "$0"' EXIT INT TERM
            cd -- \(quotedDir) || exit 1
            clear
            printf '\\033[2m%s\\033[0m \\033[1;32m❯\\033[0m \\033[1m%s\\033[0m\\n' \(quotedDisplay) \(quotedCommand)
            /bin/zsh -ilc \(quotedCommand)
            rm -f -- "$0"
            exec "${SHELL:-/bin/zsh}" -il
            """ + "\n"
    }

    func directLaunchArguments(workingDirectory: String, command: String?) -> [String] {
        let trimmed = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shellTail: [String] =
            trimmed.isEmpty
            ? []
            : [
                "/bin/zsh", "-ilc",
                "\(trimmed); exec \"${SHELL:-/bin/zsh}\" -il"
            ]
        switch self {
        case .kitty:
            return ["--directory", workingDirectory] + shellTail
        case .alacritty:
            var args = ["--working-directory", workingDirectory]
            if !shellTail.isEmpty { args += ["-e"] + shellTail }
            return args
        case .wezterm:
            var args = ["start", "--cwd", workingDirectory]
            if !shellTail.isEmpty { args += ["--"] + shellTail }
            return args
        default:
            return []
        }
    }
}
