import Foundation

struct TerminalSessionSummary: Equatable, Sendable {
    let activeCount: Int
    let idleCount: Int

    var totalLiveTabs: Int {
        activeCount + idleCount
    }

    var showsBadge: Bool {
        totalLiveTabs > 0
    }

    var displayedNumber: Int? {
        activeCount > 0 ? activeCount : nil
    }

    var tooltipText: String {
        if activeCount > 0 && idleCount > 0 {
            let activeLine = String(localized: "\(activeCount) active")
            let idleLine =
                idleCount == 1
                ? String(localized: "1 idle tab")
                : String(localized: "\(idleCount) idle tabs")
            return "\(activeLine)\n\(idleLine)"
        }
        if activeCount > 0 {
            return activeCount == 1
                ? String(localized: "1 active tab")
                : String(localized: "\(activeCount) active tabs")
        }
        return idleCount == 1
            ? String(localized: "1 idle tab")
            : String(localized: "\(idleCount) idle tabs")
    }
}

enum TerminalTabFormatting {
    static let maxLogScalarCount = 262_144
    static let trimTargetScalarCount = 196_608

    static func title(lastCommand: String?, workingDirectory: String, homeDirectory: String) -> String {
        if let command = lastCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
            !command.isEmpty
        {
            let singleLine = command.replacingOccurrences(of: "\n", with: " ")
            if singleLine.count <= 24 { return singleLine }
            return String(singleLine.prefix(23)) + "…"
        }
        return RecentFolders.shortName(workingDirectory, homeDirectory: homeDirectory)
    }

    static func sessionSummary(
        tabs: [(isAlive: Bool, isRunning: Bool)]
    ) -> TerminalSessionSummary {
        var active = 0
        var idle = 0
        for tab in tabs where tab.isAlive {
            if tab.isRunning {
                active += 1
            } else {
                idle += 1
            }
        }
        return TerminalSessionSummary(activeCount: active, idleCount: idle)
    }

    static func requiresCloseConfirmation(isRunning: Bool) -> Bool {
        isRunning
    }

    static func commandHeader(
        command: String,
        workingDirectory: String,
        homeDirectory: String,
        gitBranch: String? = nil,
        hasLeadingContent: Bool = false
    ) -> String {
        let folder = RecentFolders.displayPath(workingDirectory, homeDirectory: homeDirectory)
        let prefix = hasLeadingContent ? "\u{1B}[2m────────────────────────────────────────\u{1B}[0m\n" : ""
        let branchSegment =
            if let branch = gitBranch, !branch.isEmpty {
                " \u{1B}[35m⎇ \(branch)\u{1B}[0m"
            } else {
                ""
            }
        return "\(prefix)\u{1B}[1;34m\(folder)\u{1B}[0m\(branchSegment) \u{1B}[1;32m❯\u{1B}[0m \u{1B}[1m\(command)\u{1B}[0m\n"
    }

    static func exitFooter(status: Int32, elapsedMilliseconds: Int? = nil) -> String {
        let formattedDuration = elapsedMilliseconds.flatMap { ms -> String? in
            guard ms >= 0 else { return nil }
            return formatDuration(milliseconds: ms)
        }
        if status == 0 {
            if let duration = formattedDuration, let ms = elapsedMilliseconds, ms >= 500 {
                return "\u{1B}[2m✓ \(duration)\u{1B}[0m\n\n"
            }
            return "\n"
        }
        if let duration = formattedDuration {
            return "\n\u{1B}[31m✗ exit \(status)\u{1B}[0m \u{1B}[2m· \(duration)\u{1B}[0m\n\n"
        }
        return "\n\u{1B}[31m✗ exit \(status)\u{1B}[0m\n\n"
    }

    static func formatDuration(milliseconds: Int) -> String {
        if milliseconds < 1_000 {
            return "\(milliseconds)ms"
        }
        if milliseconds < 60_000 {
            let tenths = (milliseconds + 50) / 100
            return "\(tenths / 10).\(tenths % 10)s"
        }
        let totalSeconds = milliseconds / 1_000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(seconds)s"
    }

    static func parseGitHead(_ rawHead: String) -> String? {
        let trimmed = rawHead.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let refPrefix = "ref: refs/heads/"
        if trimmed.hasPrefix(refPrefix) {
            let branch = String(trimmed.dropFirst(refPrefix.count))
            return branch.isEmpty ? nil : branch
        }
        if trimmed.hasPrefix("ref: ") {
            let ref = String(trimmed.dropFirst(5))
            return ref.split(separator: "/").last.map(String.init)
        }
        if trimmed.count >= 7, trimmed.allSatisfy(\.isHexDigit) {
            return String(trimmed.prefix(7))
        }
        return nil
    }

    static func trimLogIfNeeded(_ text: String) -> (trimmed: String, didTrim: Bool) {
        let scalars = text.unicodeScalars
        guard scalars.count > maxLogScalarCount else { return (text, false) }
        let dropCount = scalars.count - trimTargetScalarCount
        let start = scalars.index(scalars.startIndex, offsetBy: dropCount)
        if let newline = scalars[start...].firstIndex(of: "\n") {
            let next = scalars.index(after: newline)
            return (String(scalars[next...]), true)
        }
        return (String(scalars[start...]), true)
    }
}
