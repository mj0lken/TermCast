import Foundation

/// The group book on disk, and the one copy of it Settings and the picker both read.
@MainActor
@Observable
final class WindowPickerGroupStore {
    @ObservationIgnored private let fileURL: URL
    private(set) var book: WindowPickerGroupBook

    init(
        fileURL: URL = AppPaths.applicationSupport().appendingPathComponent("window-groups.json")
    ) {
        self.fileURL = fileURL
        book =
            (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode(WindowPickerGroupBook.self, from: $0) }
            ?? WindowPickerGroupBook()
    }

    /// False when the file could not be written; the change still holds until the app quits.
    @discardableResult
    func update(_ change: (inout WindowPickerGroupBook) -> Void) -> Bool {
        var next = book
        change(&next)
        guard next != book else { return true }
        book = next
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// A group's own name unless it was given one.
    func title(for group: WindowPickerBoard.Group) -> String {
        let name = book.style(for: group).name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? Self.defaultTitle(for: group) : name
    }

    static func defaultTitle(for group: WindowPickerBoard.Group) -> String {
        switch group {
        case .appType(let name): name.isEmpty ? String(localized: "Other") : name
        case .custom(let number): String(localized: "Group \(number)")
        }
    }
}
