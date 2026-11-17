import SwiftUI

/// Notes as a launcher screen: the search field filters the list, and the open note is its row.
struct NotesScreen: PaletteScreen {
    let notes: NotesCoordinator
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    var rows: [NoteSummary] { notes.visibleNotes }

    /// With no notes the pill creates one, so an empty collection is never a dead end.
    var actsWithoutRows: Bool { true }

    var landingSelection: Int {
        rows.firstIndex { $0.id == notes.selectedID } ?? 0
    }

    var primaryActionTitle: String {
        rows.isEmpty ? String(localized: "Create Note") : String(localized: "Edit Note")
    }

    private func summary(at selection: Int) -> NoteSummary? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func hasActions(at selection: Int) -> Bool { true }

    /// A focused note or rename field moves its own caret; the arrows drive the list only from it.
    func ownsVerticalKeys(at selection: Int) -> Bool { vm.isEditingField }

    func actions(at selection: Int) -> PopoverMenuContent? {
        var items: [PopoverMenuItem] = []
        let summary = summary(at: selection)
        if let summary {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Edit Note"), systemImage: "square.and.pencil", shortcut: "↵"
                ) {
                    notes.edit(summary.id)
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Create Note"), systemImage: "plus", shortcut: "⌘N"
            ) {
                notes.createNote()
            })
        if let summary {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Switch Between List and Note"),
                    systemImage: "arrow.left.arrow.right", shortcut: "⌘L"
                ) {
                    notes.toggleEditorFocus()
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Rename Note"), systemImage: "pencil", shortcut: "⌘E"
                ) {
                    notes.beginRename(summary)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy Deeplink"), systemImage: "link",
                    startsSection: true, shortcut: "⇧⌘C"
                ) {
                    notes.copyDeepLink(to: summary.id)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Show in Finder"), systemImage: "folder", shortcut: "⌘F"
                ) {
                    notes.showInFinder(summary.id)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Move to Trash"), systemImage: "trash",
                    startsSection: true, shortcut: "⌃X", isDestructive: true
                ) {
                    notes.trash(summary.id)
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Notes Settings"), systemImage: "slider.horizontal.3",
                startsSection: true, shortcut: "⌥⌘,"
            ) {
                notes.showSettings()
            })
        return PopoverMenuContent(header: summary?.displayTitle, items: items)
    }

    func activate(at selection: Int) {
        guard let summary = summary(at: selection) else {
            // An empty list mid-search is not an empty collection, so ↵ waits for the results.
            if !notes.isSearching { notes.createNote() }
            return
        }
        notes.edit(summary.id)
    }

    func secondary(at selection: Int) -> Bool { false }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        // In a note these chords are text commands: ⌘⌫ deletes a line, ⌘E is inline code.
        guard !vm.isEditingField else { return false }
        switch shortcut {
        case .newItem:
            notes.createNote()
            return true
        case .settings:
            notes.showSettings()
            return true
        default: break
        }
        guard let summary = summary(at: selection) else { return false }
        switch shortcut {
        case .edit: notes.beginRename(summary)
        case .copyFile: notes.copyDeepLink(to: summary.id)
        case .showInFinder: notes.showInFinder(summary.id)
        case .delete, .commandDelete: notes.trash(summary.id)
        default: return false
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            NotesScreenView(
                rows: rows, selection: selection, scroll: scroll,
                defaultListWidth: metrics.scaled(Theme.Size.noteListWidth), openActions: openActions))
    }
}

/// The screen's body: the list, the hairline that also resizes it, and the open note's editor.
private struct NotesScreenView: View {
    @Environment(NotesCoordinator.self) private var notes
    @Environment(PaletteState.self) private var vm
    let rows: [NoteSummary]
    let selection: Int
    let scroll: ScrollIntent
    let defaultListWidth: CGFloat
    let openActions: () -> Void
    @State private var dragStartWidth: CGFloat?

    private var listWidth: CGFloat { notes.listWidth ?? defaultListWidth }

    /// The open note's row, so an autosave that re-sorts the list cannot move the highlight off it.
    private var highlightedID: NoteID? {
        if !notes.isSelectionPending, let open = notes.selectedID, rows.contains(where: { $0.id == open }) {
            return open
        }
        return rows.indices.contains(selection) ? rows[selection].id : nil
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyResults(text: emptyMessage, systemImage: "text.book.closed")
            } else {
                HStack(spacing: 0) {
                    NotesList(
                        results: rows, selectedID: highlightedID, scroll: scroll,
                        onSelect: select,
                        onActivate: { summary in
                            select(summary)
                            notes.edit(summary.id)
                        },
                        onActions: { summary in
                            select(summary)
                            openActions()
                        }
                    )
                    .frame(width: listWidth)
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(width: Theme.Size.hairline)
                        .overlay {
                            NoteSplitHandle(
                                onBegin: { dragStartWidth = listWidth },
                                onDrag: { translation in
                                    notes.setListWidth((dragStartWidth ?? listWidth) + translation)
                                }
                            )
                            .frame(width: Theme.Size.noteSplitHandleWidth)
                        }
                    NoteEditorPane()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if notes.showsInfo {
                NoteInfoCard()
                    .padding(.trailing, Theme.Spacing.xl)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: Theme.Duration.tooltip), value: notes.showsInfo)
        .onAppear(perform: notes.screenDidOpen)
        .onDisappear(perform: notes.screenDidClose)
        .onChange(of: vm.query, initial: true) { _, query in notes.setSearchQuery(query) }
        // Only the highlight moving opens a note; the rows moving under it must never do so.
        .onChange(of: vm.selection) { _, _ in openHighlighted() }
        .onChange(of: rows.map(\.id), initial: true) { _, _ in reseat() }
        .onChange(of: notes.selectedID) { _, _ in reseat() }
    }

    private var emptyMessage: String {
        if notes.isSearching { return String(localized: "Searching notes…") }
        return notes.isFilteringList ? String(localized: "No notes found") : String(localized: "No Notes")
    }

    /// Puts the highlight back on the open note, or opens the highlighted row when it left the list.
    private func reseat() {
        guard !notes.isSelectionPending else { return }
        guard let index = rows.firstIndex(where: { $0.id == notes.selectedID }) else {
            openHighlighted()
            return
        }
        if index != vm.selection { vm.selection = index }
    }

    private func openHighlighted() {
        guard rows.indices.contains(vm.selection) else { return }
        notes.preview(rows[vm.selection].id)
    }

    private func select(_ summary: NoteSummary) {
        guard let index = rows.firstIndex(where: { $0.id == summary.id }) else { return }
        if index == vm.selection {
            notes.preview(summary.id)
        } else {
            vm.selection = index
        }
    }
}

/// The hairline's hit strip: AppKit, because the panel hands a SwiftUI drag to its own window drag.
private struct NoteSplitHandle: NSViewRepresentable {
    let onBegin: () -> Void
    let onDrag: (CGFloat) -> Void

    func makeNSView(context: Context) -> NoteSplitHandleView {
        let view = NoteSplitHandleView()
        view.onBegin = onBegin
        view.onDrag = onDrag
        return view
    }

    func updateNSView(_ view: NoteSplitHandleView, context: Context) {
        view.onBegin = onBegin
        view.onDrag = onDrag
    }
}

final class NoteSplitHandleView: NSView, PaletteResizeHandleView {
    var onBegin: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    private var pressX: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        pressX = event.locationInWindow.x
        onBegin?()
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.locationInWindow.x - pressX)
    }
}

/// The open note, with the formatting bar under it while the header's toggle has it out.
private struct NoteEditorPane: View {
    @Environment(NotesCoordinator.self) private var notes

    var body: some View {
        if notes.hasActiveNote {
            VStack(spacing: 0) {
                NoteEditorView(
                    input: notes.editorInput,
                    rendersMarkdown: notes.rendersMarkdown,
                    onSourceChange: notes.updateSource,
                    onCharacterCountChange: notes.updateCounts,
                    onFormattingChange: notes.updateFormatting,
                    onFocusChange: notes.editorFocusChanged,
                    onCommand: notes.perform,
                    onReady: notes.editorReady
                )
                if notes.isFormattingBarShown {
                    NoteFormattingBar()
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, Theme.Spacing.md)
                        .frame(height: Theme.Size.bottomBarHeight)
                        .transition(.opacity)
                }
            }
            .onChange(of: notes.isFormattingBarShown) { _, shown in
                if !shown { notes.closeHeadingMenu() }
            }
            // A pane torn down while focused never reports the loss itself.
            .onDisappear { notes.editorFocusChanged(false) }
        } else {
            Color.clear
        }
    }
}

/// Drawn in the palette, not as a system popover: how long the note is and when it was made.
private struct NoteInfoCard: View {
    @Environment(NotesCoordinator.self) private var notes
    @Environment(\.metrics) private var metrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            row(String(localized: "Words"), Text(verbatim: notes.wordCount.formatted()))
                .accessibilityLabel("\(notes.wordCount) words in this note")
            row(String(localized: "Characters"), Text(verbatim: notes.characterCount.formatted()))
                .accessibilityLabel("\(notes.characterCount) characters in this note")
            if let created = notes.activeCreatedAt {
                row(
                    String(localized: "Created"),
                    Text(created, format: .dateTime.day().month(.abbreviated).year().hour().minute()))
            }
        }
        .font(metrics.typography.keyCap)
        .padding(metrics.spacing.lg)
        .frame(width: Theme.Size.noteInfoCardWidth)
        // The tooltip's own surface: solid, because the card hangs over the note's text.
        .background {
            shape.fill(Color(nsColor: .windowBackgroundColor))
            shape.fill(Theme.Colors.controlSurface)
        }
        .shadow(color: Theme.Colors.tooltipShadow, radius: metrics.spacing.xs, y: metrics.spacing.xxs)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note Info")
    }

    private func row(_ label: String, _ value: Text) -> some View {
        HStack(spacing: metrics.spacing.md) {
            Text(verbatim: label)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: metrics.spacing.md)
            value
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// The Notes screen's own controls beside the search field: a new note, formatting, and its info.
struct NotesHeaderControls: View {
    @Environment(NotesCoordinator.self) private var notes
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            control(
                "plus", String(localized: "Create Note"), String(localized: "Create Note  ⌘N"),
                action: notes.createNote)
            if notes.showsFormattingBar, notes.hasActiveNote {
                control(
                    "paintbrush", String(localized: "Formatting"), String(localized: "Formatting"),
                    isSelected: notes.isFormattingBarShown, action: notes.toggleFormattingBar)
            }
            if notes.hasActiveNote {
                // No tooltip: hovering it is what shows the card, and a tooltip would cover that.
                control(
                    "info.circle", String(localized: "Note Info"), nil,
                    isSelected: notes.isInfoPinnedOpen, action: notes.toggleInfoPinned
                )
                .onHover(perform: notes.setInfoHovered)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func control(
        _ symbol: String, _ label: String, _ help: String?, isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        BarButton(chrome: .rounded, isSelected: isSelected, isCompact: true, action: action) {
            Image(systemName: symbol)
                .font(
                    .system(
                        size: metrics.scaled(Theme.Typography.menuSymbolSize),
                        weight: Theme.Typography.menuSymbolWeight)
                )
                .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: metrics.size.chatAttachmentGlyph, height: metrics.size.chatAttachmentGlyph)
        }
        .focusable(false)
        .tooltip(help, edge: .bottom)
        .accessibilityLabel(label)
    }
}
