import AppKit

/// The Snippets shortcut's menu; only AppKit's attributed titles give a menu labelled text columns.
@MainActor
enum NotchSnippetMenu {
    private static let columnGap: CGFloat = 28

    /// Pops up at `point`, in screen coordinates, and returns once the menu has closed.
    static func present(
        _ choices: [NotchSnippetChoice], at point: NSPoint, isDark: Bool,
        expand: @escaping (NotchSnippetChoice.ID) -> Void
    ) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        // A menu popped up outside a view takes the app's look, so it is handed the tray's instead.
        menu.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        if choices.isEmpty {
            let empty = NSMenuItem(title: String(localized: "No Snippets"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let rows = choices.map(Row.init)
            let columns = Columns(rows: rows + [.header])
            let header = NSMenuItem()
            header.isEnabled = false
            header.attributedTitle = columns.title(for: .header, isHeader: true)
            menu.addItem(header)
            for (choice, row) in zip(choices, rows) {
                let item = NotchSnippetMenuItem { expand(choice.id) }
                item.attributedTitle = columns.title(for: row, isHeader: false)
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    /// One line's three cells: the name, the keyword a reader types, and the hotkey.
    @MainActor
    private struct Row {
        let name: String
        let keyword: String
        let hotkey: String

        static var header: Row {
            Row(
                name: String(localized: "Snippet"), keyword: String(localized: "Keyword"),
                hotkey: String(localized: "Shortcut"))
        }

        init(name: String, keyword: String, hotkey: String) {
            self.name = name
            self.keyword = keyword
            self.hotkey = hotkey
        }

        init(_ choice: NotchSnippetChoice) {
            self.init(
                name: choice.name, keyword: choice.keyword ?? "",
                hotkey: choice.binding.map { $0.keycaps.joined(separator: " ") } ?? "")
        }
    }

    /// Tab stops wide enough for every row, so the keyword and hotkey each keep a column.
    @MainActor
    private struct Columns {
        private static let font = NSFont.menuFont(ofSize: 0)
        private static let keywordFont = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        private static let headerFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)

        private let style: NSParagraphStyle

        init(rows: [Row]) {
            func widest(_ cell: (Row) -> String, _ font: NSFont) -> CGFloat {
                rows.map { ceil((cell($0) as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
            }
            let keywordStart = widest(\.name, Self.font) + columnGap
            let hotkeyEnd = keywordStart + widest(\.keyword, Self.keywordFont) + columnGap
                + widest(\.hotkey, Self.font)
            let style = NSMutableParagraphStyle()
            style.tabStops = [
                NSTextTab(textAlignment: .left, location: keywordStart),
                NSTextTab(textAlignment: .right, location: hotkeyEnd)
            ]
            self.style = style
        }

        func title(for row: Row, isHeader: Bool) -> NSAttributedString {
            func cell(_ text: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: isHeader ? Self.headerFont : font, .paragraphStyle: style,
                    .foregroundColor: isHeader ? NSColor.tertiaryLabelColor : color
                ]
                return NSAttributedString(string: text, attributes: attributes)
            }
            let title = NSMutableAttributedString()
            title.append(cell(row.name, Self.font, .labelColor))
            title.append(cell("\t" + row.keyword, Self.keywordFont, .secondaryLabelColor))
            title.append(cell("\t" + row.hotkey, Self.font, .tertiaryLabelColor))
            return title
        }
    }
}

/// A menu item that runs a closure, so the menu needs no separate target object kept alive.
private final class NotchSnippetMenuItem: NSMenuItem {
    private let run: () -> Void

    init(run: @escaping () -> Void) {
        self.run = run
        super.init(title: "", action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        run()
    }
}
