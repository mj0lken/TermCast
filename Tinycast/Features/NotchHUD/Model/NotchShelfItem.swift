import Foundation

/// Pure staged item held in the Notch Shelf tray (local file, web link or text snippet).
struct NotchShelfItem: Identifiable, Codable, Equatable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        case file(URL)
        case link(URL)
        case text(String)
    }

    static let maxItems = 24

    let id: UUID
    let kind: Kind
    let createdAt: Date

    init(id: UUID = UUID(), kind: Kind, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
    }

    var displayTitle: String {
        switch kind {
        case .file(let url):
            return Self.middleTruncate(url.lastPathComponent, maxLength: 26)
        case .link(let url):
            let host = url.host(percentEncoded: false) ?? url.absoluteString
            let path = url.path(percentEncoded: false)
            if path.isEmpty || path == "/" {
                return Self.middleTruncate(host, maxLength: 28)
            }
            return "\(host)\n\(Self.middleTruncate(path, maxLength: 18))"
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            return Self.middleTruncate(trimmed.isEmpty ? "Text" : trimmed, maxLength: 28)
        }
    }

    func sharesIdentity(with other: Self) -> Bool {
        switch (kind, other.kind) {
        case (.file(let lhs), .file(let rhs)):
            lhs.standardizedFileURL == rhs.standardizedFileURL
        case (.link(let lhs), .link(let rhs)):
            lhs.absoluteString == rhs.absoluteString
        case (.text(let lhs), .text(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    static func inserting(
        _ incoming: [Self],
        into existing: [Self],
        limit: Int = maxItems
    ) -> [Self] {
        var combined = existing
        for candidate in incoming.reversed() {
            combined.removeAll { $0.sharesIdentity(with: candidate) }
            combined.insert(candidate, at: 0)
        }
        if combined.count > limit {
            combined = Array(combined.prefix(limit))
        }
        return combined
    }

    static func middleTruncate(_ text: String, maxLength: Int) -> String {
        guard maxLength >= 6, text.count > maxLength else { return text }
        let headCount = (maxLength - 1) / 2
        let tailCount = maxLength - 1 - headCount
        return "\(text.prefix(headCount))…\(text.suffix(tailCount))"
    }
}
