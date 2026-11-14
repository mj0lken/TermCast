import Foundation

enum TerminalCommandMatch: Equatable, Sendable {
    case prefix(String)
    case detected(String)

    var command: String {
        switch self {
        case .prefix(let text), .detected(let text): return text
        }
    }
}

enum TerminalCommandDetector {
    static let shellBuiltins: Set<String> = [
        "cd", "pwd", "export", "unset", "alias", "unalias", "source", "history",
        "type", "which", "echo", "printf", "clear", "jobs", "fg", "bg", "kill",
        "ulimit", "umask", "eval", "exec", "pushd", "popd", "dirs"
    ]

    // Single-word CLI verbs that never collide with ordinary macOS app names like Mail or Notes.
    static let unambiguousCLICommands: Set<String> = [
        "ls", "ll", "la", "cat", "head", "tail", "less", "grep", "rg", "ag", "ack",
        "sed", "awk", "cut", "tr", "wc", "sort", "uniq", "tee", "xargs", "find", "fd",
        "chmod", "chown", "mkdir", "rmdir", "rm", "cp", "mv", "ln", "touch", "stat",
        "tar", "zip", "unzip", "gzip", "gunzip", "curl", "wget", "ssh", "scp", "rsync",
        "ping", "dig", "nslookup", "nc", "lsof", "ps", "top", "htop", "killall", "pkill",
        "df", "du", "uname", "whoami", "env", "printenv", "git", "gh", "brew", "npm",
        "npx", "pnpm", "yarn", "bun", "deno", "node", "python", "python3", "pip", "pip3",
        "uv", "poetry", "cargo", "rustc", "go", "swift", "swiftc", "xcodebuild", "xcodegen",
        "xcrun", "make", "cmake", "ninja", "docker", "kubectl", "helm", "terraform", "aws",
        "gcloud", "az", "tmux", "zsh", "bash", "sh", "jq", "yq", "bat", "eza", "fzf",
        "man", "pbcopy", "pbpaste", "defaults", "plutil", "launchctl", "diskutil",
        "networksetup", "scutil", "sw_vers", "codesign", "spctl", "otool", "sudo"
    ]

    static func stripExplicitPrefix(_ raw: String) -> String? {
        guard raw.hasPrefix(">") else { return nil }
        let rest = raw.dropFirst()
        if rest.first == " " { return String(rest.dropFirst()) }
        return String(rest)
    }

    static func detect(
        _ raw: String,
        executables: Set<String>,
        hasCalculatorOrColorMatch: Bool = false
    ) -> TerminalCommandMatch? {
        if let stripped = stripExplicitPrefix(raw) {
            return .prefix(stripped.trimmingCharacters(in: .whitespaces))
        }
        guard !hasCalculatorOrColorMatch else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return nil }

        if isPathInvocation(trimmed) {
            return .detected(trimmed)
        }
        if hasLeadingEnvAssignment(trimmed) {
            return .detected(trimmed)
        }
        if hasShellOperator(trimmed) {
            return .detected(trimmed)
        }

        let (firstToken, remainder) = splitFirstToken(trimmed)
        guard !firstToken.isEmpty else { return nil }

        // Lowercase check avoids flagging Title-Case app queries like "Finder" or "Calendar".
        let isLowercaseToken = firstToken == firstToken.lowercased()
        let hasTrailingSpaceOrArgs = !remainder.isEmpty || raw.last?.isWhitespace == true

        if isLowercaseToken,
            shellBuiltins.contains(firstToken) || unambiguousCLICommands.contains(firstToken)
        {
            return .detected(trimmed)
        }

        if hasTrailingSpaceOrArgs, isLowercaseToken, executables.contains(firstToken) {
            return .detected(trimmed)
        }

        return nil
    }

    private static func isPathInvocation(_ text: String) -> Bool {
        if text.hasPrefix("./") || text.hasPrefix("../") || text.hasPrefix("~/") {
            return text.count > 2
        }
        if text.hasPrefix("/") {
            return text.count > 1 && !text.dropFirst().hasPrefix(" ")
        }
        return false
    }

    private static func hasLeadingEnvAssignment(_ text: String) -> Bool {
        guard let equals = text.firstIndex(of: "="), equals != text.startIndex else { return false }
        let name = text[..<equals]
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return false }
        let after = text[text.index(after: equals)...]
        return after.contains(where: \.isWhitespace)
    }

    private static func hasShellOperator(_ text: String) -> Bool {
        let operators = [" | ", " && ", " || ", " >> ", " > ", " 2>&1", "$(", " ; "]
        if operators.contains(where: { text.contains($0) }) { return true }
        return text.hasSuffix(";") && text.count > 1
    }

    private static func splitFirstToken(_ text: String) -> (String, Substring) {
        guard let space = text.firstIndex(where: \.isWhitespace) else {
            return (text, "")
        }
        let rest = text[space...].drop(while: \.isWhitespace)
        return (String(text[..<space]), rest)
    }
}
