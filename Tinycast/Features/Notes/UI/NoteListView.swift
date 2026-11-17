import SwiftUI

/// The Notes screen's list, in the palette's row grammar: a title over one line of preview.
struct NotesList: View {
    @Environment(\.metrics) private var metrics
    let results: [NoteSummary]
    let selectedID: NoteID?
    let scroll: ScrollIntent
    let onSelect: (NoteSummary) -> Void
    let onActivate: (NoteSummary) -> Void
    let onActions: (NoteSummary) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Keyed by the string the scroll follower aims at, which must be this identity.
                    ForEach(results, id: \.id.rawValue) { summary in
                        NoteRow(summary: summary, selected: summary.id == selectedID)
                            .selectionFrame(summary.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(summary) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded { onActivate(summary) }
                            )
                            .onRightClick { onActions(summary) }
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
                scroll, row: selectedID?.rawValue, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct NoteRow: View {
    @Environment(\.metrics) private var metrics
    @Environment(NotesCoordinator.self) private var notes
    let summary: NoteSummary
    let selected: Bool
    @State private var hovered = false
    @FocusState private var titleFocused: Bool

    private var isEditing: Bool { notes.editingID == summary.id }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        IconCache.observeStyle()
        return HStack(spacing: metrics.spacing.lg) {
            Image(nsImage: IconCache.symbolIcon(named: "note.text")).resizable()
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            VStack(alignment: .leading, spacing: 1) {
                title
                if let preview = summary.preview {
                    Text(verbatim: preview)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: metrics.spacing.sm)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.displayTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onChange(of: isEditing) { _, editing in
            guard editing else { return }
            Task { @MainActor in
                await Task.yield()
                titleFocused = true
            }
        }
        // Clicking away keeps the typed name, as Finder does; only Escape discards it.
        .onChange(of: titleFocused) { _, focused in
            if !focused, isEditing { notes.commitRename() }
        }
    }

    @ViewBuilder
    private var title: some View {
        if isEditing {
            TextField("Note title", text: notes.titleDraftBinding)
                .textFieldStyle(.plain)
                .font(metrics.typography.menuRow)
                .focused($titleFocused)
                .onSubmit(notes.commitRename)
        } else {
            Text(verbatim: summary.displayTitle)
                .font(metrics.typography.menuRow)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
