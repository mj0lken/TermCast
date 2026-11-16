import AppKit
import Foundation

/// Off-main metadata and source-app icon cache for detailed Clipboard History rows.
@MainActor
@Observable
final class ClipboardMetadataCache {
    struct EntryMetadata: Equatable, Sendable {
        var fileBytes: Int64?
        var pixelSize: CGSize?
        var characterCount: Int?
        var wordCount: Int?
        var isDirectory = false
        var typeDescription: String?
    }

    struct SourceAppInfo {
        let name: String
        let icon: NSImage
    }

    private(set) var metadataByID: [UUID: EntryMetadata] = [:]
    private(set) var knownDirectories: Set<String> = []

    @ObservationIgnored private var inFlight: Set<UUID> = []
    @ObservationIgnored private var appCache: [String: SourceAppInfo?] = [:]

    func metadata(for item: ClipboardItem) -> EntryMetadata? {
        metadataByID[item.id]
    }

    func sourceApp(for bundleID: String?) -> SourceAppInfo? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        IconCache.observeStyle()
        if let cached = appCache[bundleID] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            appCache[bundleID] = .some(nil)
            return nil
        }
        let info = SourceAppInfo(
            name: url.deletingPathExtension().lastPathComponent,
            icon: IconCache.icon(forFile: url.path))
        appCache[bundleID] = .some(info)
        return info
    }

    func ensureLoaded(for item: ClipboardItem, imageURL: URL?) {
        guard metadataByID[item.id] == nil, !inFlight.contains(item.id) else { return }
        inFlight.insert(item.id)

        let id = item.id
        let kind = item.kind
        let text = kind == .text ? item.text : nil
        let filePath = item.filePath

        Task { [weak self] in
            let computed = await Self.probe(kind: kind, text: text, imageURL: imageURL, filePath: filePath)
            guard let self else { return }
            self.inFlight.remove(id)
            self.metadataByID[id] = computed
            if computed.isDirectory, let filePath {
                self.knownDirectories.insert(filePath)
            }
        }
    }

    func preloadDirectories(for items: [ClipboardItem]) {
        for item in items.prefix(150) where item.kind == .file {
            ensureLoaded(for: item, imageURL: nil)
        }
    }

    @concurrent
    private static func probe(
        kind: ClipboardItem.Kind,
        text: String?,
        imageURL: URL?,
        filePath: String?
    ) async -> EntryMetadata {
        var result = EntryMetadata()
        switch kind {
        case .text:
            if let text {
                result.characterCount = text.count
                result.wordCount = countWords(in: text)
            }
        case .image:
            if let imageURL {
                result.pixelSize = ImageThumbnail.pixelSize(of: imageURL)
                if let size = try? imageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    result.fileBytes = Int64(size)
                }
            }
        case .file:
            if let filePath {
                let url = URL(fileURLWithPath: filePath)
                let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .isDirectoryKey, .contentTypeKey])
                result.isDirectory = values?.isDirectory == true
                if let size = values?.fileSize, !result.isDirectory {
                    result.fileBytes = Int64(size)
                }
                result.typeDescription = values?.contentType?.localizedDescription
            }
        }
        return result
    }

    nonisolated private static func countWords(in text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let sep = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if !sep, !inWord { count += 1 }
            inWord = !sep
        }
        return count
    }
}
