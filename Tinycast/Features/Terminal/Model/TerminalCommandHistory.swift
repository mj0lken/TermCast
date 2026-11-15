import Foundation

enum TerminalCommandHistory {
    static let maxEntries = 500

    static func sanitized(_ stored: [String], limit: Int = maxEntries) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in stored {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
            if result.count >= limit { break }
        }
        return result
    }

    static func record(_ command: String, in history: [String], limit: Int = maxEntries) -> [String] {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return history }
        var updated = history.filter { $0 != trimmed }
        updated.insert(trimmed, at: 0)
        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }
        return updated
    }
}

struct TerminalHistoryNavigator: Equatable, Sendable {
    enum StepResult: Equatable, Sendable {
        case updated(String)
        case boundary
        case inactive
    }

    private(set) var draft = ""
    private(set) var cursor: Int?
    private(set) var matches: [String] = []

    var isBrowsing: Bool { cursor != nil }

    mutating func stepOlder(currentInput: String, history: [String]) -> StepResult {
        if let current = cursor {
            let next = current + 1
            guard matches.indices.contains(next) else { return .boundary }
            cursor = next
            return .updated(matches[next])
        }
        let filtered =
            currentInput.isEmpty
            ? history
            : history.filter { $0.hasPrefix(currentInput) && $0 != currentInput }
        guard !filtered.isEmpty else { return .inactive }
        draft = currentInput
        matches = filtered
        cursor = 0
        return .updated(filtered[0])
    }

    mutating func stepNewer() -> StepResult {
        guard let current = cursor else { return .inactive }
        if current > 0 {
            let next = current - 1
            cursor = next
            return .updated(matches[next])
        }
        let restored = draft
        reset()
        return .updated(restored)
    }

    mutating func reset() {
        draft = ""
        cursor = nil
        matches = []
    }
}
