import Foundation

/// A note's title is its filename; one the user has not named yet borrows its first line to show.
enum NoteTitle {
    static let untitled = "Untitled"

    static func displayName(_ title: String) -> String {
        guard isUnnamed(title) else { return title }
        return String(localized: "Untitled") + title.dropFirst(untitled.count)
    }

    /// Wide enough that the scanned prefix is covered even where every character is four bytes.
    static let headByteCount = 4096

    private static let scanLimit = 1024
    private static let displayLimit = 120
    private static let previewLimit = 240

    /// True only for the names `create` claims — `Untitled`, `Untitled 2`, … — never a typed one.
    static func isUnnamed(_ title: String) -> Bool {
        guard title.hasPrefix(untitled) else { return false }
        let suffix = title.dropFirst(untitled.count)
        guard !suffix.isEmpty else { return true }
        let digits = suffix.dropFirst()
        return suffix.hasPrefix(" ") && !digits.isEmpty
            && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// The first line carrying visible text, without its Markdown markers and capped to one row.
    static func firstLine(of source: String) -> String? {
        visibleLines(of: source).first.map { String($0.prefix(displayLimit)) }
    }

    /// What a list row shows under its title; an unnamed note's first line is already its title.
    static func preview(of source: String, skippingTitle: Bool) -> String? {
        let lines = visibleLines(of: source).dropFirst(skippingTitle ? 1 : 0)
        guard !lines.isEmpty else { return nil }
        return String(lines.joined(separator: " ").prefix(previewLimit))
    }

    /// Bounded by `scanLimit`, so reading every line of the head costs a row nothing worth saving.
    private static func visibleLines(of source: String) -> [String] {
        let head = String(source.prefix(scanLimit))
        let text = head as NSString
        let markdown = NoteMarkdownParser.parse(head)
        return markdown.lines
            .map { visibleText(of: $0, in: markdown, text: text) }
            .filter { !$0.isEmpty }
    }

    /// A line as it reads when rendered, with the setting on or off: syntax never titles a note.
    private static func visibleText(
        of line: NoteMarkdown.Line, in markdown: NoteMarkdown, text: NSString
    ) -> String {
        switch line.kind {
        case .blank, .rule, .fenceOpen, .fenceClose: return ""
        default: break
        }
        var visible = ""
        var cursor = line.contentRange.location
        let markers = markdown.inlines(of: line).flatMap(\.markerRanges)
        for marker in markers.sorted(by: { $0.location < $1.location }) {
            visible += text.substring(with: NSRange(cursor..<marker.location))
            cursor = NSMaxRange(marker)
        }
        visible += text.substring(with: NSRange(cursor..<NSMaxRange(line.contentRange)))
        return visible.trimmingCharacters(in: .whitespaces)
    }
}
