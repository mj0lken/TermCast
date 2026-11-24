import AppKit

/// The files a pasteboard names; `NSURL` reading picks a representation of its own choosing.
enum PasteboardFiles {
    /// The file itself on the board, so a paste in Finder copies it rather than its path.
    static func write(_ url: URL, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.fileURL, .string], owner: nil)
        pasteboard.setData(url.dataRepresentation, forType: .fileURL)
        // Both types: a file-taking app receives the file, a text field receives the path.
        pasteboard.setString(url.path, forType: .string)
    }

    /// Empty when the board names no file, so a caller falls through to text or bytes.
    static func urls(on pasteboard: NSPasteboard) -> [URL] {
        urls(on: pasteboard, limit: .max) { _ in true }
    }

    /// A picture on the board, unless plain text is there without a browser's image URL.
    static func pastedImageData(on pasteboard: NSPasteboard) -> Data? {
        guard urls(on: pasteboard, limit: 1, matching: { _ in true }).isEmpty,
            let type = pasteboard.availableType(from: [.png, .tiff]),
            let data = pasteboard.data(forType: type)
        else { return nil }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return data }
        guard pasteboard.string(forType: .URL) != nil || isWebURL(text) else { return nil }
        return data
    }

    private static func isWebURL(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace), let url = URL(string: text),
            let scheme = url.scheme?.lowercased()
        else { return false }
        return scheme == "http" || scheme == "https" || scheme == "data" || scheme == "blob"
    }

    /// Filters while decoding, so a ten-thousand-file select-all stops decoding at the limit.
    static func urls(
        on pasteboard: NSPasteboard, limit: Int, matching predicate: (URL) -> Bool
    ) -> [URL] {
        guard limit > 0 else { return [] }
        var matches: [URL] = []
        for item in pasteboard.pasteboardItems ?? [] {
            guard let url = url(from: item), predicate(url) else { continue }
            matches.append(url)
            if matches.count == limit { return matches }
        }
        return matches
    }

    /// `public.file-url` arrives as UTF-8 data on most boards and as a string on some.
    private static func url(from item: NSPasteboardItem) -> URL? {
        if let data = item.data(forType: .fileURL),
            let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL
        {
            return url
        }
        guard let string = item.string(forType: .fileURL), let url = URL(string: string),
            url.isFileURL
        else { return nil }
        return url
    }
}
