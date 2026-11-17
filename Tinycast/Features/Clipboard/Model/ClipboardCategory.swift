import Foundation

/// Sidebar categories and title-first search ranking for the Clipboard History screen.
enum ClipboardCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case pinned
    case text
    case links
    case emails
    case colors
    case images
    case videos
    case audio
    case documents
    case pdfs
    case spreadsheets
    case presentations
    case code
    case apps
    case archives
    case fonts
    case folders
    case otherFiles

    var id: Self { self }

    struct SidebarEntry: Identifiable, Equatable, Sendable {
        let category: ClipboardCategory
        let count: Int
        var id: ClipboardCategory { category }
    }

    init(filter: ClipboardFilter) {
        switch filter {
        case .all: self = .all
        case .text: self = .text
        case .image: self = .images
        case .file: self = .otherFiles
        case .color: self = .colors
        case .link: self = .links
        case .email: self = .emails
        }
    }

    /// Coarsest `ClipboardStore` filter that still returns every candidate this category admits.
    var backingFilter: ClipboardFilter {
        switch self {
        case .all, .pinned, .images:
            .all
        case .text:
            .text
        case .links:
            .link
        case .emails:
            .email
        case .colors:
            .color
        case .videos, .audio, .documents, .pdfs, .spreadsheets, .presentations,
             .code, .apps, .archives, .fonts, .folders, .otherFiles:
            .file
        }
    }

    var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .pinned: return String(localized: "Pinned")
        case .text: return String(localized: "Text")
        case .links: return String(localized: "Links")
        case .emails: return String(localized: "Emails")
        case .colors: return String(localized: "Colors")
        case .images: return String(localized: "Images")
        case .videos: return String(localized: "Videos")
        case .audio: return String(localized: "Audio")
        case .documents: return String(localized: "Documents")
        case .pdfs: return String(localized: "PDFs")
        case .spreadsheets: return String(localized: "Spreadsheets")
        case .presentations: return String(localized: "Presentations")
        case .code: return String(localized: "Code")
        case .apps: return String(localized: "Apps")
        case .archives: return String(localized: "Archives")
        case .fonts: return String(localized: "Fonts")
        case .folders: return String(localized: "Folders")
        case .otherFiles: return String(localized: "Other Files")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .pinned: return "pin"
        case .text: return "textformat"
        case .links: return "link"
        case .emails: return "at"
        case .colors: return "eyedropper"
        case .images: return "photo"
        case .videos: return "film"
        case .audio: return "waveform"
        case .documents: return "doc.text"
        case .pdfs: return "doc.richtext"
        case .spreadsheets: return "tablecells"
        case .presentations: return "rectangle.on.rectangle"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .apps: return "app.badge"
        case .archives: return "archivebox"
        case .fonts: return "textformat.abc"
        case .folders: return "folder"
        case .otherFiles: return "doc"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return String(localized: "Clipboard history is empty")
        case .pinned: return String(localized: "No pinned entries in clipboard history")
        case .text: return String(localized: "No text in clipboard history")
        case .links: return String(localized: "No links in clipboard history")
        case .emails: return String(localized: "No email addresses in clipboard history")
        case .colors: return String(localized: "No colors in clipboard history")
        case .images: return String(localized: "No images in clipboard history")
        case .videos: return String(localized: "No videos in clipboard history")
        case .audio: return String(localized: "No audio files in clipboard history")
        case .documents: return String(localized: "No documents in clipboard history")
        case .pdfs: return String(localized: "No PDFs in clipboard history")
        case .spreadsheets: return String(localized: "No spreadsheets in clipboard history")
        case .presentations: return String(localized: "No presentations in clipboard history")
        case .code: return String(localized: "No code files in clipboard history")
        case .apps: return String(localized: "No apps or disk images in clipboard history")
        case .archives: return String(localized: "No archives in clipboard history")
        case .fonts: return String(localized: "No fonts in clipboard history")
        case .folders: return String(localized: "No folders in clipboard history")
        case .otherFiles: return String(localized: "No files in clipboard history")
        }
    }

    func matches(_ item: ClipboardItem, knownDirectories: Set<String> = []) -> Bool {
        switch self {
        case .all:
            return true
        case .pinned:
            return item.isPinned
        case .text:
            return item.textForm == .plain
        case .links:
            return item.textForm == .link
        case .emails:
            return item.textForm == .email
        case .colors:
            return item.textForm == .color
        case .images:
            if item.kind == .image { return true }
            return fileKind(of: item, knownDirectories: knownDirectories) == .image
        case .videos:
            return fileKind(of: item, knownDirectories: knownDirectories) == .movie
        case .audio:
            return fileKind(of: item, knownDirectories: knownDirectories) == .audio
        case .documents:
            return fileKind(of: item, knownDirectories: knownDirectories) == .document
        case .pdfs:
            return fileKind(of: item, knownDirectories: knownDirectories) == .pdf
        case .spreadsheets:
            return fileKind(of: item, knownDirectories: knownDirectories) == .spreadsheet
        case .presentations:
            return fileKind(of: item, knownDirectories: knownDirectories) == .presentation
        case .code:
            return fileKind(of: item, knownDirectories: knownDirectories) == .code
        case .apps:
            return fileKind(of: item, knownDirectories: knownDirectories) == .app
        case .archives:
            return fileKind(of: item, knownDirectories: knownDirectories) == .archive
        case .fonts:
            return fileKind(of: item, knownDirectories: knownDirectories) == .font
        case .folders:
            return fileKind(of: item, knownDirectories: knownDirectories) == .folder
        case .otherFiles:
            return fileKind(of: item, knownDirectories: knownDirectories) == .other
        }
    }

    /// Shows every core category when `alwaysShowCore` is true, or only non-empty categories otherwise.
    static func visibleCategories(
        in items: [ClipboardItem],
        active: ClipboardCategory,
        knownDirectories: Set<String> = []
    ) -> [SidebarEntry] {
        allCases.compactMap { category in
            let count = category == .all
                ? items.count
                : items.reduce(into: 0) { acc, item in
                    if category.matches(item, knownDirectories: knownDirectories) { acc += 1 }
                }
            guard category == .all || category == active || count > 0 else { return nil }
            return SidebarEntry(category: category, count: count)
        }
    }

    /// Ranks title matches ahead of body/OCR content matches while keeping pinned entries first.
    static func filterAndRank(
        _ candidates: [ClipboardItem],
        category: ClipboardCategory,
        query: String,
        knownDirectories: Set<String> = []
    ) -> [ClipboardItem] {
        let filtered = category == .all
            ? candidates
            : candidates.filter { category.matches($0, knownDirectories: knownDirectories) }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return filtered }

        let pinned = rankSlice(filtered.filter(\.isPinned), query: trimmed)
        let unpinned = rankSlice(filtered.filter { !$0.isPinned }, query: trimmed)
        return pinned + unpinned
    }

    static func displayTitle(for item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            let head = String((item.text ?? "").prefix(240))
            let firstLine = head
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return firstLine ?? String(localized: "Text")
        case .image:
            return String(localized: "Image")
        case .file:
            guard let path = item.filePath, !path.isEmpty else {
                return String(localized: "File")
            }
            return URL(filePath: path, directoryHint: .inferFromPath).lastPathComponent
        }
    }

    private func fileKind(
        of item: ClipboardItem,
        knownDirectories: Set<String>
    ) -> ClipboardFileKind? {
        guard item.kind == .file, let path = item.filePath else { return nil }
        return ClipboardFileKind.of(path: path, isDirectory: knownDirectories.contains(path))
    }

    private static func rankSlice(_ slice: [ClipboardItem], query: String) -> [ClipboardItem] {
        guard slice.count > 1 else { return slice }
        var prefixMatches: [ClipboardItem] = []
        var titleSubstringMatches: [ClipboardItem] = []
        var bodyOnlyMatches: [ClipboardItem] = []

        for item in slice {
            let title = displayTitle(for: item)
            if title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
                prefixMatches.append(item)
            } else if title.localizedStandardContains(query) {
                titleSubstringMatches.append(item)
            } else {
                bodyOnlyMatches.append(item)
            }
        }
        return prefixMatches + titleSubstringMatches + bodyOnlyMatches
    }
}
