import AppKit
import SwiftUI

// MARK: - Narrow Left Category Sidebar

struct ClipboardCategorySidebar: View {
    @Environment(\.metrics) private var metrics
    let entries: [ClipboardCategory.SidebarEntry]
    let selected: ClipboardCategory
    let onSelect: (ClipboardCategory) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entries) { entry in
                    ClipboardCategoryRow(
                        entry: entry,
                        isSelected: entry.category == selected,
                        onSelect: { onSelect(entry.category) })
                }
            }
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, metrics.spacing.sm)
            .hideNativeScrollers()
        }
        .edgeDissolve()
    }
}

private struct ClipboardCategoryRow: View {
    @Environment(\.metrics) private var metrics
    let entry: ClipboardCategory.SidebarEntry
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var hovered = false

    private var fill: Color {
        if isSelected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: metrics.spacing.sm) {
                SymbolImage(
                    name: entry.category.systemImage,
                    size: Theme.Typography.menuSymbolSize,
                    monochrome: true
                )
                .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: 18, height: 18)

                Text(entry.category.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(verbatim: "\(entry.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous)
                    .fill(fill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .armedHover($hovered)
    }
}

// MARK: - Detailed Right-Side List

struct ClipboardList: View {
    @Environment(\.metrics) private var metrics
    let results: [ClipboardItem]
    let selectedID: ClipboardItem.ID?
    let metadataCache: ClipboardMetadataCache
    let scroll: ScrollIntent
    let onSelect: (ClipboardItem) -> Void
    let onActivate: () -> Void
    let onActions: (ClipboardItem) -> Void
    let onDragPayload: (ClipboardItem) -> ClipDragPayload?
    let onDropped: () -> Void
    @Environment(ClipboardStore.self) private var store

    private enum Row: Identifiable {
        case header(String)
        case item(ClipboardItem, slot: Character?)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .item(let item, _): return item.id.uuidString
            }
        }
    }

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var currentTitle: String?
        var pinnedSlot = 0
        for item in results {
            let title = item.isPinned ? String(localized: "Pinned") : DateBucket(for: item.createdAt).title
            if title != currentTitle {
                rows.append(.header(title))
                currentTitle = title
            }
            let slot = item.isPinned ? FavoriteSlots.digit(at: pinnedSlot) : nil
            if item.isPinned { pinnedSlot += 1 }
            rows.append(.item(item, slot: slot))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .item(let item, let slot):
                            ClipboardRow(
                                item: item,
                                selected: item.id == selectedID,
                                imageURL: store.imageURL(for: item),
                                ownsImage: store.ownsImage(of: item),
                                metadataCache: metadataCache,
                                slot: slot
                            )
                            .selectionFrame(item.id == selectedID)
                            .contentShape(Rectangle())
                            .onRightClick { onActions(item) }
                            .onRowClick(
                                select: { onSelect(item) },
                                activate: {
                                    onSelect(item)
                                    onActivate()
                                },
                                drag: RowDrag(
                                    item: { onDragPayload(item)?.dragItem }, dropped: onDropped)
                            )
                        }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID?.uuidString, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

enum DateBucket: Int {
    case today, yesterday, thisWeek, thisMonth, earlier

    var title: String {
        switch self {
        case .today: return String(localized: "Today")
        case .yesterday: return String(localized: "Yesterday")
        case .thisWeek: return String(localized: "This Week")
        case .thisMonth: return String(localized: "This Month")
        case .earlier: return String(localized: "Earlier")
        }
    }

    init(for date: Date, now: Date = Date(), calendar: Calendar = .current) {
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            self = .thisWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            self = .thisMonth
        } else {
            self = .earlier
        }
    }
}

private struct ClipboardRow: View {
    @MainActor private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    @MainActor private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    @Environment(\.metrics) private var metrics
    let item: ClipboardItem
    let selected: Bool
    let imageURL: URL?
    let ownsImage: Bool
    let metadataCache: ClipboardMetadataCache
    let slot: Character?
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var entryMeta: ClipboardMetadataCache.EntryMetadata? {
        metadataCache.metadata(for: item)
    }

    var body: some View {
        IconCache.observeStyle()
        let appInfo = metadataCache.sourceApp(for: item.sourceBundleID)
        return HStack(spacing: metrics.spacing.md) {
            thumbnail(item.colorValue)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(primaryTitle)
                        .font(metrics.typography.menuRow)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                if let secondary = secondarySubtitle {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: metrics.spacing.sm)

            HStack(spacing: metrics.spacing.sm) {
                if let sizeLabel {
                    Text(verbatim: sizeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                if let appInfo {
                    Image(nsImage: appInfo.icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .accessibilityLabel(appInfo.name)
                }

                SlotChordReveal(slot: slot) {
                    Text(verbatim: formattedTimestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(minWidth: 46, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .task(id: item.id) {
            metadataCache.ensureLoaded(for: item, imageURL: imageURL)
        }
    }

    private var primaryTitle: String {
        switch item.kind {
        case .text:
            return ClipboardCategory.displayTitle(for: item)
        case .image:
            if let size = entryMeta?.pixelSize {
                return String(localized: "Image (\(Int(size.width))×\(Int(size.height)))")
            }
            return String(localized: "Image")
        case .file:
            return ClipboardCategory.displayTitle(for: item)
        }
    }

    private var secondarySubtitle: String? {
        switch item.kind {
        case .text:
            guard let text = item.text else { return nil }
            let head = String(text.prefix(320))
            let lines = head
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return lines.count > 1 ? lines[1] : nil
        case .image:
            return nil
        case .file:
            guard let path = item.filePath else { return nil }
            let parent = (path as NSString).deletingLastPathComponent
            return (parent as NSString).abbreviatingWithTildeInPath
        }
    }

    private var sizeLabel: String? {
        switch item.kind {
        case .text:
            if item.colorValue != nil { return String(localized: "Color") }
            guard let chars = entryMeta?.characterCount else { return nil }
            return String(localized: "\(chars) chars")
        case .image, .file:
            if let bytes = entryMeta?.fileBytes {
                return bytes.formatted(.byteCount(style: .file))
            }
            if item.kind == .file {
                return fileKind.title
            }
            return nil
        }
    }

    private var formattedTimestamp: String {
        if Calendar.current.isDateInToday(item.createdAt) {
            return Self.timeFormatter.string(from: item.createdAt)
        }
        if Calendar.current.isDateInYesterday(item.createdAt) {
            return String(localized: "Yesterday")
        }
        return Self.shortDateFormatter.string(from: item.createdAt)
    }

    @ViewBuilder
    private func thumbnail(_ color: ColorValue?) -> some View {
        switch item.kind {
        case .text:
            if let color {
                ColorSwatch(color: color)
                    .frame(width: artworkSize, height: artworkSize)
            } else {
                Image(nsImage: IconCache.symbolIcon(named: textGlyph)).resizable()
            }
        case .image:
            AsyncThumbnail(url: imageURL, maxPixel: 64, source: .image(derived: ownsImage)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(
                        RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
            } placeholder: {
                Image(nsImage: IconCache.symbolIcon(named: "photo")).resizable()
            }
        case .file:
            if fileKind == .app, let path = item.filePath {
                Image(nsImage: IconCache.icon(forFile: path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: artworkSize, height: artworkSize)
            } else {
                AsyncThumbnail(url: fileURL, maxPixel: 64, source: .file) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(
                            RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
                } placeholder: {
                    Image(nsImage: IconCache.symbolIcon(named: fileKind.systemImage)).resizable()
                }
            }
        }
    }

    private var textGlyph: String {
        switch item.textForm {
        case .link: "link"
        case .email: "at"
        case .color: "eyedropper"
        case .plain, .none: "doc.text"
        }
    }

    private var fileURL: URL? {
        item.filePath.map { URL(filePath: $0, directoryHint: .inferFromPath) }
    }

    private var fileKind: ClipboardFileKind {
        item.filePath.map {
            ClipboardFileKind.of(path: $0, isDirectory: entryMeta?.isDirectory == true)
        } ?? .other
    }

    private var artworkSize: CGFloat { metrics.size.resultRowIcon * IconCache.appIconExtent }
}

// MARK: - Bottom-Third Preview Drawer

struct ClipboardBottomPreviewPane: View {
    @MainActor private static let copiedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    @Environment(\.metrics) private var metrics
    let item: ClipboardItem
    let metadataCache: ClipboardMetadataCache
    let onClose: () -> Void
    @Environment(ClipboardStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            headerRow
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, metrics.spacing.lg)
        .padding(.top, metrics.spacing.sm)
        .padding(.bottom, metrics.spacing.sm)
        .task(id: item.id) {
            metadataCache.ensureLoaded(for: item, imageURL: store.imageURL(for: item))
        }
    }

    private var headerRow: some View {
        let appInfo = metadataCache.sourceApp(for: item.sourceBundleID)
        let meta = metadataCache.metadata(for: item)
        return HStack(spacing: metrics.spacing.sm) {
            if let appInfo {
                Image(nsImage: appInfo.icon)
                    .resizable()
                    .frame(width: 15, height: 15)
                Text(verbatim: appInfo.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(verbatim: "·")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Text(verbatim: detailSummary(meta: meta))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: metrics.spacing.sm)

            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.Colors.controlSurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Hide Preview"))
        }
    }

    private func detailSummary(meta: ClipboardMetadataCache.EntryMetadata?) -> String {
        var parts: [String] = []
        switch item.kind {
        case .text:
            if let chars = meta?.characterCount, let words = meta?.wordCount {
                parts.append(String(localized: "\(words) words · \(chars) chars"))
            }
        case .image:
            if let size = meta?.pixelSize {
                parts.append("\(Int(size.width))×\(Int(size.height))")
            }
            if let bytes = meta?.fileBytes {
                parts.append(bytes.formatted(.byteCount(style: .file)))
            }
        case .file:
            if let type = meta?.typeDescription {
                parts.append(type)
            }
            if let bytes = meta?.fileBytes {
                parts.append(bytes.formatted(.byteCount(style: .file)))
            }
        }
        parts.append(Self.copiedFormatter.string(from: item.createdAt))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.kind {
        case .text:
            if let color = item.colorValue {
                ColorPreview(color: color, text: item.text ?? "")
            } else {
                ScrollView {
                    Text(item.text ?? "")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        case .image:
            HStack {
                Spacer(minLength: 0)
                AsyncThumbnail(
                    url: store.imageURL(for: item),
                    maxPixel: metrics.size.clipboardPreviewPixel,
                    source: .image(derived: store.ownsImage(of: item))
                ) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(
                            RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
                } placeholder: {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer(minLength: 0)
            }
        case .file:
            if let path = item.filePath {
                FilePreviewStage(path: path)
            }
        }
    }
}

// MARK: - Async Thumbnail Loader

private enum ThumbnailSource {
    case image(derived: Bool)
    case file

    func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        switch self {
        case .image: return ImageThumbnail.cached(url, maxPixel: maxPixel)
        case .file: return FilePreviewThumbnail.cached(url, maxPixel: maxPixel)
        }
    }

    func loadAsync(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        switch self {
        case .image(let derived):
            return await ImageThumbnail.loadAsync(
                url, maxPixel: maxPixel, copyingWith: derived ? ClipboardTextWorker.executable : nil)
        case .file: return await FilePreviewThumbnail.loadAsync(url, maxPixel: maxPixel)
        }
    }
}

private struct AsyncThumbnail<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixel: CGFloat
    var source: ThumbnailSource = .image(derived: false)
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                content(Image(nsImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let hit = source.cached(url, maxPixel: maxPixel) {
                image = hit
                return
            }
            image = nil
            image = await source.loadAsync(url, maxPixel: maxPixel)
        }
    }
}
