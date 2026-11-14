import Foundation

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

    static func commandHeader(command: String, workingDirectory: String, homeDirectory: String) -> String {
        let folder = RecentFolders.displayPath(workingDirectory, homeDirectory: homeDirectory)
        return "\u{1B}[2m\(folder)\u{1B}[0m \u{1B}[1;32m❯\u{1B}[0m \u{1B}[1m\(command)\u{1B}[0m\n"
    }

    static func exitFooter(status: Int32) -> String {
        guard status != 0 else { return "\n" }
        return "\n\u{1B}[31m[exit \(status)]\u{1B}[0m\n\n"
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
