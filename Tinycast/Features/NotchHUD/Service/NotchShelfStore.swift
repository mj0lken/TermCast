import AppKit
import Foundation
import UniformTypeIdentifiers

/// Persists files, URLs and text dropped onto the Notch Shelf and triggers native AirDrop.
@MainActor
@Observable
final class NotchShelfStore {
    private(set) var items: [NotchShelfItem] = []

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = AppPaths.applicationSupport().appending(path: "notch-shelf.json")) {
        self.fileURL = fileURL
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([NotchShelfItem].self, from: data)
        else { return }
        items = decoded.filter { item in
            if case .file(let url) = item.kind {
                return FileManager.default.fileExists(atPath: url.path)
            }
            return true
        }
    }

    func add(_ incoming: [NotchShelfItem]) {
        guard !incoming.isEmpty else { return }
        items = NotchShelfItem.inserting(incoming, into: items)
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        save()
    }

    func open(_ item: NotchShelfItem) {
        switch item.kind {
        case .file(let url), .link(let url):
            NSWorkspace.shared.open(url)
        case .text(let value):
            _ = Paster.copyPlainText(value)
        }
    }

    func itemProvider(for item: NotchShelfItem) -> NSItemProvider {
        switch item.kind {
        case .file(let url), .link(let url):
            return NSItemProvider(object: url as NSURL)
        case .text(let value):
            return NSItemProvider(object: value as NSString)
        }
    }

    func ingestDrop(providers: [NSItemProvider]) {
        Task { @MainActor in
            let extracted = await Self.extractItems(from: providers)
            add(extracted)
        }
    }

    func airDrop(providers: [NSItemProvider]) {
        Task { @MainActor in
            let extracted = await Self.extractItems(from: providers)
            performAirDrop(items: extracted)
        }
    }

    func airDropAllStaged() {
        performAirDrop(items: items)
    }

    private func performAirDrop(items: [NotchShelfItem]) {
        let shareItems: [Any] = items.map { item in
            switch item.kind {
            case .file(let url), .link(let url):
                url as NSURL
            case .text(let text):
                text as NSString
            }
        }
        guard !shareItems.isEmpty,
            let service = NSSharingService(named: .sendViaAirDrop)
        else { return }
        service.perform(withItems: shareItems)
    }

    private func save() {
        let snapshot = items
        let targetURL = fileURL
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: targetURL, options: .atomic)
            }
        }
    }

    private static func extractItems(from providers: [NSItemProvider]) async -> [NotchShelfItem] {
        var collected: [NotchShelfItem] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                let url = await loadURL(from: provider, typeIdentifier: UTType.fileURL.identifier)
            {
                collected.append(NotchShelfItem(kind: .file(url)))
                continue
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                let url = await loadURL(from: provider, typeIdentifier: UTType.url.identifier)
            {
                let kind: NotchShelfItem.Kind = url.isFileURL ? .file(url) : .link(url)
                collected.append(NotchShelfItem(kind: kind))
                continue
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                let text = await loadText(from: provider)
            {
                if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                    scheme == "http" || scheme == "https"
                {
                    collected.append(NotchShelfItem(kind: .link(url)))
                } else {
                    collected.append(NotchShelfItem(kind: .text(text)))
                }
            }
        }
        return collected
    }

    private static func loadURL(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let text = item as? String, let url = URL(string: text) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data, let string = String(bytes: data, encoding: .utf8) {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
