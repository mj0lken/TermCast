import Foundation

struct TerminalCompletionEntry: Equatable, Sendable {
    let name: String
    let isDirectory: Bool
}

struct TerminalCompletionCandidate: Equatable, Identifiable, Sendable {
    let id: String
    let display: String
    let replacementToken: String
    let isDirectory: Bool
    let appendsSpace: Bool

    var appliedToken: String {
        appendsSpace ? replacementToken + " " : replacementToken
    }
}

struct TerminalCompletionQuery: Equatable, Sendable {
    let prefixBeforeToken: String
    let rawToken: String
    let candidates: [TerminalCompletionCandidate]
}

struct TerminalCompletionSession: Sendable {
    private(set) var baseInput: String = ""
    private(set) var prefixBeforeToken: String = ""
    private(set) var candidates: [TerminalCompletionCandidate] = []
    private(set) var selectedIndex: Int?
    private var lastAppliedInput: String?

    var isActive: Bool { !candidates.isEmpty }

    mutating func reset() {
        baseInput = ""
        prefixBeforeToken = ""
        candidates = []
        selectedIndex = nil
        lastAppliedInput = nil
    }

    mutating func noteInputChanged(_ currentInput: String) {
        if currentInput != lastAppliedInput {
            reset()
        }
    }

    enum StepOutcome: Equatable, Sendable {
        case none
        case completed(String)
        case cycling(String)
    }

    mutating func step(
        currentInput: String,
        backwards: Bool,
        buildQuery: (String) -> TerminalCompletionQuery?
    ) -> StepOutcome {
        if isActive, currentInput == lastAppliedInput || currentInput == baseInput {
            return advanceCycle(backwards: backwards)
        }
        reset()

        guard let query = buildQuery(currentInput), !query.candidates.isEmpty else {
            return .none
        }

        if query.candidates.count == 1 {
            let completed = query.prefixBeforeToken + query.candidates[0].appliedToken
            return .completed(completed)
        }

        let commonReplacement = Self.commonPrefix(
            of: query.candidates.map(\.replacementToken))
        baseInput = currentInput
        prefixBeforeToken = query.prefixBeforeToken
        candidates = query.candidates

        if commonReplacement.count > query.rawToken.count,
            commonReplacement.lowercased().hasPrefix(query.rawToken.lowercased())
        {
            let expanded = query.prefixBeforeToken + commonReplacement
            baseInput = expanded
            lastAppliedInput = expanded
            selectedIndex = nil
            return .cycling(expanded)
        }

        return advanceCycle(backwards: backwards)
    }

    mutating func applyCandidate(at index: Int) -> String? {
        guard candidates.indices.contains(index) else { return nil }
        let applied = prefixBeforeToken + candidates[index].appliedToken
        reset()
        return applied
    }

    private mutating func advanceCycle(backwards: Bool) -> StepOutcome {
        guard !candidates.isEmpty else { return .none }
        let nextIndex: Int
        if let current = selectedIndex {
            let delta = backwards ? -1 : 1
            nextIndex = (current + delta + candidates.count) % candidates.count
        } else {
            nextIndex = backwards ? candidates.count - 1 : 0
        }
        selectedIndex = nextIndex
        let candidate = candidates[nextIndex]
        let updated = prefixBeforeToken + candidate.appliedToken
        lastAppliedInput = updated
        return .cycling(updated)
    }

    private static func commonPrefix(of values: [String]) -> String {
        guard var prefix = values.first else { return "" }
        for value in values.dropFirst() {
            while !value.lowercased().hasPrefix(prefix.lowercased()) {
                prefix.removeLast()
                if prefix.isEmpty { return "" }
            }
        }
        return prefix
    }
}

enum TerminalTabCompleter {
    static let maxCandidates = 40

    private static let commandWrappers: Set<String> = [
        "sudo", "env", "time", "nohup", "xargs", "command", "builtin", "exec"
    ]

    private static let directoryOnlyCommands: Set<String> = [
        "cd", "pushd", "rmdir"
    ]

    private static let gitSubcommands: [String] = [
        "add", "bisect", "branch", "checkout", "cherry-pick", "clean", "clone",
        "commit", "diff", "fetch", "init", "log", "merge", "mv", "pull", "push",
        "rebase", "remote", "reset", "restore", "revert", "rm", "show", "stash",
        "status", "switch", "tag", "worktree"
    ]

    private static let builtinCommands: [String] = [
        "alias", "bg", "cd", "clear", "echo", "env", "eval", "exec", "exit",
        "export", "fg", "history", "jobs", "kill", "printf", "pushd", "popd",
        "pwd", "read", "set", "source", "test", "time", "type", "umask",
        "unalias", "unset", "wait", "which"
    ]

    static func complete(
        input: String,
        workingDirectory: String,
        homeDirectory: String,
        executables: Set<String>,
        listDirectory: (String) -> [TerminalCompletionEntry]
    ) -> TerminalCompletionQuery? {
        let parsed = parseActiveSegment(input)
        let rawToken = parsed.rawToken
        let unescaped = unescapeToken(rawToken, quote: parsed.openQuote)

        if unescaped.hasPrefix("-") {
            return nil
        }

        let isPathLike =
            unescaped.contains("/")
            || unescaped.hasPrefix(".")
            || unescaped.hasPrefix("~")

        if parsed.isCommandPosition, !isPathLike {
            guard !unescaped.isEmpty else { return nil }
            let candidates = completeExecutables(
                prefix: unescaped,
                executables: executables,
                openQuote: parsed.openQuote)
            guard !candidates.isEmpty else { return nil }
            return TerminalCompletionQuery(
                prefixBeforeToken: parsed.prefixBeforeToken,
                rawToken: rawToken,
                candidates: candidates)
        }

        if let command = parsed.leadingCommand,
            command == "git",
            parsed.argumentIndex == 1,
            !isPathLike
        {
            let matches = gitSubcommands
                .filter { $0.hasPrefix(unescaped.lowercased()) }
                .prefix(maxCandidates)
                .map { sub in
                    TerminalCompletionCandidate(
                        id: "git:\(sub)",
                        display: sub,
                        replacementToken: formatReplacement(sub, openQuote: parsed.openQuote),
                        isDirectory: false,
                        appendsSpace: parsed.openQuote == nil)
                }
            if !matches.isEmpty {
                return TerminalCompletionQuery(
                    prefixBeforeToken: parsed.prefixBeforeToken,
                    rawToken: rawToken,
                    candidates: Array(matches))
            }
        }

        let directoriesOnly = parsed.leadingCommand.map { directoryOnlyCommands.contains($0) } ?? false
        let pathCandidates = completePaths(
            unescapedToken: unescaped,
            openQuote: parsed.openQuote,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory,
            directoriesOnly: directoriesOnly,
            listDirectory: listDirectory)
        guard !pathCandidates.isEmpty else { return nil }
        return TerminalCompletionQuery(
            prefixBeforeToken: parsed.prefixBeforeToken,
            rawToken: rawToken,
            candidates: pathCandidates)
    }

    private static func completeExecutables(
        prefix: String,
        executables: Set<String>,
        openQuote: Character?
    ) -> [TerminalCompletionCandidate] {
        let lower = prefix.lowercased()
        var pool = executables
        for builtin in builtinCommands {
            pool.insert(builtin)
        }
        let sorted = pool
            .filter { $0.lowercased().hasPrefix(lower) }
            .sorted { lhs, rhs in
                let lhsExactCase = lhs.hasPrefix(prefix)
                let rhsExactCase = rhs.hasPrefix(prefix)
                if lhsExactCase != rhsExactCase { return lhsExactCase }
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .prefix(maxCandidates)

        return sorted.map { name in
            TerminalCompletionCandidate(
                id: "cmd:\(name)",
                display: name,
                replacementToken: formatReplacement(name, openQuote: openQuote),
                isDirectory: false,
                appendsSpace: openQuote == nil)
        }
    }

    private static func completePaths(
        unescapedToken: String,
        openQuote: Character?,
        workingDirectory: String,
        homeDirectory: String,
        directoriesOnly: Bool,
        listDirectory: (String) -> [TerminalCompletionEntry]
    ) -> [TerminalCompletionCandidate] {
        let (typedDirectoryPrefix, namePrefix) = splitDirectoryAndName(unescapedToken)
        let resolvedDirectory = resolveSearchDirectory(
            typedDirectoryPrefix: typedDirectoryPrefix,
            workingDirectory: workingDirectory,
            homeDirectory: homeDirectory)
        let includeDotfiles = namePrefix.hasPrefix(".")
        let lowerPrefix = namePrefix.lowercased()

        let entries = listDirectory(resolvedDirectory)
            .filter { entry in
                if directoriesOnly && !entry.isDirectory { return false }
                if !includeDotfiles && entry.name.hasPrefix(".") { return false }
                if lowerPrefix.isEmpty { return true }
                return entry.name.lowercased().hasPrefix(lowerPrefix)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                let lhsCase = lhs.name.hasPrefix(namePrefix)
                let rhsCase = rhs.name.hasPrefix(namePrefix)
                if lhsCase != rhsCase { return lhsCase }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(maxCandidates)

        return entries.map { entry in
            let suffix = entry.isDirectory ? "/" : ""
            let rawPath = typedDirectoryPrefix + entry.name + suffix
            let display = entry.name + suffix
            let replacement = formatPathReplacement(rawPath, openQuote: openQuote)
            return TerminalCompletionCandidate(
                id: "path:\(rawPath)",
                display: display,
                replacementToken: replacement,
                isDirectory: entry.isDirectory,
                appendsSpace: !entry.isDirectory && openQuote == nil)
        }
    }

    private static func splitDirectoryAndName(_ token: String) -> (directory: String, name: String) {
        if token == "~" {
            return ("~/", "")
        }
        guard let slash = token.lastIndex(of: "/") else {
            return ("", token)
        }
        let next = token.index(after: slash)
        return (String(token[..<next]), String(token[next...]))
    }

    private static func resolveSearchDirectory(
        typedDirectoryPrefix: String,
        workingDirectory: String,
        homeDirectory: String
    ) -> String {
        let cleanHome = homeDirectory.hasSuffix("/")
            ? String(homeDirectory.dropLast())
            : homeDirectory
        if typedDirectoryPrefix.isEmpty {
            return workingDirectory
        }
        if typedDirectoryPrefix == "~/" {
            return cleanHome
        }
        if typedDirectoryPrefix.hasPrefix("~/") {
            let rest = String(typedDirectoryPrefix.dropFirst(2))
            return URL(fileURLWithPath: cleanHome)
                .appendingPathComponent(rest)
                .standardizedFileURL.path
        }
        if typedDirectoryPrefix.hasPrefix("/") {
            return URL(fileURLWithPath: typedDirectoryPrefix).standardizedFileURL.path
        }
        return URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent(typedDirectoryPrefix)
            .standardizedFileURL.path
    }

    private static func formatReplacement(_ value: String, openQuote: Character?) -> String {
        if let quote = openQuote {
            return String(quote) + value + String(quote)
        }
        return escapeSpaces(value)
    }

    private static func formatPathReplacement(_ rawPath: String, openQuote: Character?) -> String {
        if let quote = openQuote {
            return String(quote) + rawPath
        }
        if rawPath.hasPrefix("~/") {
            return "~/" + escapeSpaces(String(rawPath.dropFirst(2)))
        }
        return escapeSpaces(rawPath)
    }

    private static func escapeSpaces(_ value: String) -> String {
        var out = ""
        for ch in value {
            if ch == " " {
                out.append("\\ ")
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private struct ParsedSegment {
        let prefixBeforeToken: String
        let rawToken: String
        let openQuote: Character?
        let isCommandPosition: Bool
        let leadingCommand: String?
        let argumentIndex: Int
    }

    private static func parseActiveSegment(_ input: String) -> ParsedSegment {
        var tokens: [(start: String.Index, end: String.Index, quote: Character?)] = []
        var segmentStart = input.startIndex
        var index = input.startIndex
        var currentStart: String.Index?
        var activeQuote: Character?
        var tokenQuote: Character?

        while index < input.endIndex {
            let ch = input[index]
            if let quote = activeQuote {
                if ch == "\\" && quote == "\"" {
                    index = input.index(after: index)
                    if index < input.endIndex {
                        index = input.index(after: index)
                    }
                    continue
                }
                if ch == quote {
                    activeQuote = nil
                }
                index = input.index(after: index)
                continue
            }

            if ch == "\\" {
                if currentStart == nil { currentStart = index }
                index = input.index(after: index)
                if index < input.endIndex {
                    index = input.index(after: index)
                }
                continue
            }

            if ch == "\"" || ch == "'" {
                if currentStart == nil {
                    currentStart = index
                    tokenQuote = ch
                }
                activeQuote = ch
                index = input.index(after: index)
                continue
            }

            if ch == "|" || ch == ";" || ch == "&" || ch == "(" {
                tokens.removeAll()
                currentStart = nil
                tokenQuote = nil
                index = input.index(after: index)
                segmentStart = index
                continue
            }

            if ch.isWhitespace {
                if let start = currentStart {
                    tokens.append((start, index, tokenQuote))
                    currentStart = nil
                    tokenQuote = nil
                }
                index = input.index(after: index)
                continue
            }

            if currentStart == nil {
                currentStart = index
                tokenQuote = nil
            }
            index = input.index(after: index)
        }

        let tokenStart: String.Index
        let rawToken: String
        if let start = currentStart {
            tokenStart = start
            rawToken = String(input[start..<input.endIndex])
        } else {
            tokenStart = input.endIndex
            rawToken = ""
        }

        let priorWords = tokens.map { span in
            unescapeToken(String(input[span.start..<span.end]), quote: span.quote)
        }

        var effectiveWords: [String] = []
        for word in priorWords {
            if effectiveWords.isEmpty {
                if isEnvironmentAssignment(word) || commandWrappers.contains(word) {
                    continue
                }
            }
            effectiveWords.append(word)
        }

        _ = segmentStart
        let isCommand = effectiveWords.isEmpty
        let leading = effectiveWords.first?.lowercased()
        return ParsedSegment(
            prefixBeforeToken: String(input[..<tokenStart]),
            rawToken: rawToken,
            openQuote: activeQuote,
            isCommandPosition: isCommand,
            leadingCommand: leading,
            argumentIndex: effectiveWords.count)
    }

    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        guard let eq = token.firstIndex(of: "="), eq > token.startIndex else { return false }
        let name = token[..<eq]
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func unescapeToken(_ raw: String, quote: Character?) -> String {
        var slice = raw[...]
        if let first = slice.first, first == "\"" || first == "'" {
            slice = slice.dropFirst()
            if quote == nil, let last = slice.last, last == first {
                slice = slice.dropLast()
            }
        }
        var out = ""
        var idx = slice.startIndex
        while idx < slice.endIndex {
            let ch = slice[idx]
            if ch == "\\", quote != "'" {
                let next = slice.index(after: idx)
                if next < slice.endIndex {
                    out.append(slice[next])
                    idx = slice.index(after: next)
                    continue
                }
            }
            out.append(ch)
            idx = slice.index(after: idx)
        }
        return out
    }
}
