import Foundation
import UniformTypeIdentifiers

/// What a referenced file is, for the Type row and the tile a thumbnail has not filled yet.
enum ClipboardFileKind: Sendable {
    case image
    case movie
    case audio
    case pdf
    case document
    case spreadsheet
    case presentation
    case code
    case archive
    case app
    case font
    case folder
    case other

    private static let appExtensions: Set<String> = [
        "app", "dmg", "pkg", "mpkg", "iso", "appimage"
    ]

    private static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz", "7z", "rar", "zst"
    ]

    private static let codeExtensions: Set<String> = [
        "swift", "c", "h", "cpp", "hpp", "cc", "m", "mm", "rs", "go", "py", "rb", "php",
        "java", "kt", "kts", "scala", "cs", "fs", "js", "jsx", "mjs", "cjs", "ts", "tsx",
        "vue", "svelte", "html", "htm", "css", "scss", "sass", "less", "sql", "graphql",
        "gql", "json", "jsonc", "yaml", "yml", "toml", "xml", "plist", "ini", "cfg",
        "conf", "env", "sh", "bash", "zsh", "fish", "ps1", "lua", "r", "dart", "zig",
        "nim", "ex", "exs", "erl", "clj", "hs", "ml", "proto", "dockerfile", "makefile",
        "cmake", "gradle"
    ]

    private static let spreadsheetExtensions: Set<String> = [
        "xls", "xlsx", "xlsm", "numbers", "ods", "csv", "tsv"
    ]

    private static let presentationExtensions: Set<String> = [
        "ppt", "pptx", "key", "odp"
    ]

    private static let documentExtensions: Set<String> = [
        "doc", "docx", "pages", "odt", "rtf", "rtfd", "txt", "md", "markdown", "rst",
        "tex", "epub", "mobi"
    ]

    private static let fontExtensions: Set<String> = [
        "ttf", "otf", "ttc", "woff", "woff2"
    ]

    /// Resolved from the extension, never from disk, so a vanished file still classifies.
    static func of(path: String, isDirectory: Bool = false) -> ClipboardFileKind {
        let url = URL(filePath: path, directoryHint: .inferFromPath)
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()

        if ext == "app" { return .app }
        if isDirectory {
            if ext == "pages" || ext == "rtfd" { return .document }
            if ext == "numbers" { return .spreadsheet }
            if ext == "key" { return .presentation }
            if ext == "pkg" || ext == "mpkg" { return .app }
            return .folder
        }

        if appExtensions.contains(ext) { return .app }
        if archiveExtensions.contains(ext) { return .archive }
        if fontExtensions.contains(ext) { return .font }
        if spreadsheetExtensions.contains(ext) { return .spreadsheet }
        if presentationExtensions.contains(ext) { return .presentation }
        if codeExtensions.contains(ext) || name == "dockerfile" || name == "makefile" {
            return .code
        }
        if documentExtensions.contains(ext) { return .document }

        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .diskImage) || type.identifier.contains("installer-package") {
            return .app
        }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .font) { return .font }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .movie }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .spreadsheet) { return .spreadsheet }
        if type.conforms(to: .presentation) { return .presentation }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .json)
            || type.conforms(to: .yaml) || type.conforms(to: .xml) || type.conforms(to: .propertyList)
        {
            return .code
        }
        if type.conforms(to: .text) || type.conforms(to: .compositeContent) {
            return .document
        }
        return .other
    }

    var isPlayable: Bool { self == .movie || self == .audio }

    var title: String {
        switch self {
        case .image: return String(localized: "Image")
        case .movie: return String(localized: "Movie")
        case .audio: return String(localized: "Audio")
        case .pdf: return "PDF"
        case .document: return String(localized: "Document")
        case .spreadsheet: return String(localized: "Spreadsheet")
        case .presentation: return String(localized: "Presentation")
        case .code: return String(localized: "Source Code")
        case .archive: return String(localized: "Archive")
        case .app: return String(localized: "Application")
        case .font: return String(localized: "Font")
        case .folder: return String(localized: "Folder")
        case .other: return String(localized: "File")
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .movie: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .spreadsheet: return "tablecells"
        case .presentation: return "rectangle.on.rectangle"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .archive: return "archivebox"
        case .app: return "app.badge"
        case .font: return "textformat.abc"
        case .folder: return "folder"
        case .other: return "doc"
        }
    }
}
