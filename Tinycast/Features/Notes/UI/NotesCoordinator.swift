import AppKit
import SwiftUI

@MainActor
@Observable
final class NotesCoordinator {
    private enum Presentation: Equatable {
        /// The Notebook command: the most recently edited note, with the caret in it.
        case latest
        /// The note the store already holds, once a create this request waited on has landed.
        case editor
        /// The screen came up on its own; the folder is re-read and nothing on screen moves.
        case refresh
        case create(source: String)
        case note(NoteID)
    }

    private let store: NotesStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private unowned let core: AppCore
    /// The note editor on the palette's Notes screen, there only while that screen is mounted.
    @ObservationIgnored private weak var editor: NoteTextView?
    @ObservationIgnored private var editorFocusTask: Task<Void, Never>?
    /// Set by a show this coordinator asked for, so the screen does not ask the store again.
    @ObservationIgnored private var openedByRequest = false
    /// One open and one close per visit, though the view and the palette both report each.
    @ObservationIgnored private var isScreenOpen = false
    @ObservationIgnored private lazy var headingMenuController = NoteHeadingMenuWindowController(
        coordinator: self)
    @ObservationIgnored private var menuBarController: NotesMenuBarController?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var issueTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var wordCountTask: Task<Void, Never>?
    @ObservationIgnored private var operationID = 0
    @ObservationIgnored private var pendingIssue: NotesStore.Issue?
    private var pendingPresentation: Presentation?
    private var enablementGeneration = 0
    private(set) var characterCount = 0
    private(set) var wordCount = 0
    private(set) var formatting = NoteFormatting.plain
    private(set) var isFormattingBarExpanded: Bool
    private(set) var isHeadingMenuPresented = false
    /// A press closes the menu before its button fires, so the button must not reopen it.
    @ObservationIgnored private var headingMenuWasOpenAtPress = false
    /// The heading button in the panel's flipped content space, reported by the bar as it lays out.
    @ObservationIgnored var headingButtonFrame: CGRect = .zero
    private var listRename = NoteListRenameState()
    /// The list's dragged width, for this visit only; every open starts from the default again.
    private(set) var listWidth: CGFloat?
    /// The rows on screen when the query last changed, shown until its results arrive.
    @ObservationIgnored private var heldRows: [NoteID] = []
    private var isInfoHovered = false
    /// A click keeps the info card up after the pointer leaves; Escape or another click drops it.
    private var isInfoPinned = false
    /// The row an in-flight selection is heading for, so a held arrow key steps from there.
    @ObservationIgnored private var pendingSelectionID: NoteID?
    private var presentationGeneration = 0

    @ObservationIgnored private let saveFormattingBarExpanded: @Sendable (Bool) -> Void

    init(
        store: NotesStore,
        settings: AppSettings,
        appIndex: AppIndex,
        core: AppCore,
        isFormattingBarExpanded: Bool = false,
        saveFormattingBarExpanded: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.core = core
        self.isFormattingBarExpanded = isFormattingBarExpanded
        self.saveFormattingBarExpanded = saveFormattingBarExpanded
        store.onIssue = { [weak self] issue in self?.present(issue) }
    }

    var editorInput: NoteEditorInput {
        NoteEditorInput(
            id: store.activeID ?? NoteID(rawValue: ""),
            source: store.source,
            epoch: store.editorEpoch)
    }

    var hasActiveNote: Bool { store.activeID != nil }
    var selectedID: NoteID? { store.activeID }
    var showsInfo: Bool { hasActiveNote && (isInfoHovered || isInfoPinned) }
    var isInfoPinnedOpen: Bool { isInfoPinned }
    var activeCreatedAt: Date? {
        store.summaries.first { $0.id == store.activeID }?.createdAt
    }
    /// Lit while the bar's buttons are showing under the note.
    var isFormattingBarShown: Bool { showsFormattingBar && isFormattingBarExpanded }
    /// True while a row is still loading, when the open note is not yet the one the list chose.
    var isSelectionPending: Bool { pendingSelectionID != nil }
    private var isShowing: Bool { core.paletteCoordinator.isShowing(.notes) }
    var rendersMarkdown: Bool { settings.notesRendersMarkdown }
    var showsFormattingBar: Bool { settings.notesRendersMarkdown && settings.notesShowsFormattingBar }
    var isSearching: Bool { store.isSearching }
    var isFilteringList: Bool {
        !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// Results are read through the current listing, so a row edited mid-search is never stale.
    var visibleNotes: [NoteSummary] {
        guard isFilteringList else { return store.summaries }
        let current = Dictionary(store.summaries.map { ($0.id, $0) }) { first, _ in first }
        // A search in flight keeps the rows it replaces, or every keystroke would blank the screen.
        let ids = store.isSearching ? heldRows : store.searchResults.map(\.id)
        return ids.compactMap { current[$0] }
    }
    var editingID: NoteID? { listRename.id }
    var titleDraftBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.listRename.draft ?? "" },
            set: { [weak self] in self?.listRename.updateDraft($0) })
    }

    func applyEnabled() {
        enablementGeneration &+= 1
        let generation = enablementGeneration
        appIndex.setCommandsVisible([.showNotes], settings.notesEnabled)
        applyMenuBarItem()
        guard !settings.notesEnabled else { return }
        presentationGeneration &+= 1
        pendingPresentation = nil
        loadTask?.cancel()
        loadTask = nil
        operationTask?.cancel()
        closeHeadingMenu()
        resetListState()
        if isShowing { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        Task { [weak self] in
            guard let self else { return }
            _ = await store.flush()
            guard generation == enablementGeneration, !settings.notesEnabled else { return }
            store.stop()
        }
    }

    func applyMenuBarItem() {
        let shows = settings.notesEnabled && settings.notesShowsInMenuBar
        guard shows != (menuBarController != nil) else { return }
        menuBarController?.remove()
        menuBarController = shows ? NotesMenuBarController(coordinator: self) : nil
    }

    /// Quit waits on this so the 300 ms autosave debounce cannot swallow the last edit.
    func prepareForTermination() async {
        await store.flush()
    }

    func toggle() {
        if isShowing {
            core.paletteCoordinator.hidePalette()
        } else {
            request(.latest)
        }
    }

    func createNote() {
        createNote(text: "")
    }

    func createNote(text: String) {
        request(.create(source: text))
    }

    func setInfoHovered(_ hovered: Bool) {
        guard hovered != isInfoHovered else { return }
        isInfoHovered = hovered
    }

    func toggleInfoPinned() {
        isInfoPinned.toggle()
    }

    func setListWidth(_ width: CGFloat) {
        listWidth = min(max(width, Theme.Size.noteListMinWidth), Theme.Size.noteListMaxWidth)
    }

    /// The chords a focused note answers itself, since the palette's own never reach it.
    func perform(_ command: NoteEditorCommand) {
        switch command {
        case .newNote: createNote()
        case .toggleFormattingBar: toggleFormattingBar()
        case .previousNote: stepNote(by: -1)
        case .nextNote: stepNote(by: 1)
        }
    }

    /// Steps from the row the last press was heading for, and keeps the caret in the editor.
    private func stepNote(by offset: Int) {
        let notes = visibleNotes
        guard let index = notes.firstIndex(where: { $0.id == pendingSelectionID ?? store.activeID })
        else { return }
        let next = min(max(index + offset, 0), notes.count - 1)
        guard next != index else { return }
        select(notes[next].id, focusEditor: true)
    }

    func open(_ id: NoteID) {
        request(.note(id))
    }

    func copyDeepLink(to id: NoteID) {
        core.deepLinkCoordinator.copyLink(toNote: id)
    }

    // MARK: - The palette screen

    /// Notes is a launcher screen, so showing it is navigating the palette there.
    private func show(focusEditor: Bool) {
        if !isShowing {
            openedByRequest = true
            core.paletteCoordinator.showPalette(mode: .notes)
        }
        if focusEditor { self.focusEditor() }
    }

    /// The screen mounted: a show that did not come through `request` still owes the store a read.
    func screenDidOpen() {
        guard !isScreenOpen else { return }
        isScreenOpen = true
        listWidth = nil
        setSearchQuery(core.palette.query)
        guard !openedByRequest else {
            openedByRequest = false
            return
        }
        request(.refresh)
    }

    /// The screen left, by Escape or with the palette: the draft is saved and the list state dropped.
    func screenDidClose() {
        guard isScreenOpen else { return }
        isScreenOpen = false
        openedByRequest = false
        closeHeadingMenu()
        presentationGeneration &+= 1
        pendingPresentation = nil
        editorFocusTask?.cancel()
        editorFocusTask = nil
        core.palette.noteEditingField(false)
        resetListState()
        Task { await store.flush() }
    }

    func setSearchQuery(_ query: String) {
        guard query != store.searchQuery else { return }
        heldRows = visibleNotes.map(\.id)
        store.updateSearchQuery(query)
    }

    /// Renaming and trashing end the store's search, so the field's query is applied again.
    private func resumeSearch() {
        guard isShowing else { return }
        setSearchQuery(core.palette.query)
    }

    /// The palette's own summon refocuses its search field a beat later, so this waits that out.
    func focusEditor() {
        editorFocusTask?.cancel()
        editorFocusTask = Task { [weak self] in
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled, let self, isShowing else { return }
                guard let editor, let window = editor.window else { continue }
                // Once, then never again: a later click on the search field must keep the focus.
                window.makeFirstResponder(editor)
                return
            }
        }
    }

    /// ⌘L: from the list into the open note, and from the note back to the list's search field.
    func toggleEditorFocus() {
        guard hasActiveNote else { return }
        guard isEditorFocused else { return focusEditor() }
        editorFocusTask?.cancel()
        core.palette.focusToken = UUID()
    }

    /// The palette asks before any text key of its own, so typing in a note never drives the list.
    func editorFocusChanged(_ focused: Bool) {
        // The find bar's field is the note's own text too, so Backspace in it must not go back.
        core.palette.noteEditingField(focused || listRename.isActive || isFindBarVisible)
    }

    private var isEditorFocused: Bool {
        guard let editor, let window = editor.window else { return false }
        return window.firstResponder === editor
    }

    private var isFindBarVisible: Bool {
        editor?.enclosingScrollView?.isFindBarVisible == true
    }

    /// Escape leaves the note for the list before the palette takes it as its own back step.
    func handlePaletteEscape() -> Bool {
        if isHeadingMenuPresented {
            closeHeadingMenu()
            return true
        }
        if isFindBarVisible {
            editor?.find(.hideFindInterface)
            return true
        }
        if isInfoPinned {
            isInfoPinned = false
            return true
        }
        if listRename.isActive {
            cancelRename()
            return true
        }
        guard isEditorFocused else { return false }
        editorFocusTask?.cancel()
        core.palette.focusToken = UUID()
        return true
    }

    /// What leaving the screen undoes: a search, a rename in progress and a pinned info card.
    private func resetListState() {
        listRename.cancel()
        isInfoPinned = false
        isInfoHovered = false
        pendingSelectionID = nil
        store.cancelSearch()
    }

    /// The highlight moved onto a row: its note opens, and the keyboard stays with the list.
    func preview(_ id: NoteID) {
        guard !listRename.isActive else { return commitRename(opening: id) }
        guard id != store.activeID || pendingSelectionID != nil else { return }
        select(id, focusEditor: false)
    }

    /// ↵ on a row: the note opens with the caret in it.
    func edit(_ id: NoteID) {
        select(id, focusEditor: true)
    }

    func showInFinder(_ id: NoteID) {
        AppLauncher.showInFinder(store.fileURL(for: id))
    }

    func showSettings() {
        core.settingsCoordinator.showSettings(tab: .notes)
    }

    /// Moving to another row ends a rename the way losing the focus does: by keeping the name.
    private func commitRename(opening id: NoteID) {
        guard let committed = listRename.commit() else { return }
        core.palette.noteEditingField(isEditorFocused)
        pendingSelectionID = nil
        runOperation { [weak self] generation in
            guard let self else { return }
            let renamedID = await store.rename(committed.id, to: committed.title)
            guard settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            resumeSearch()
            // The row moved to may be the renamed one, whose identity is its new filename.
            let target = committed.id == id ? renamedID ?? id : id
            let selected = await store.select(target) { [weak self] in
                self?.permitsCompletion(generation) ?? false
            }
            guard selected, permitsCompletion(generation) else { return }
            show(focusEditor: false)
        }
    }

    /// Renaming edits the filename, so the field starts from that and never from a derived line.
    func beginRename(_ summary: NoteSummary) {
        listRename.begin(id: summary.id, title: summary.title)
        core.palette.noteEditingField(true)
    }

    func commitRename() {
        guard let committed = listRename.commit() else { return }
        core.palette.noteEditingField(isEditorFocused)
        rename(committed.id, to: committed.title)
        core.palette.focusToken = UUID()
    }

    func cancelRename() {
        guard listRename.isActive else { return }
        listRename.cancel()
        core.palette.noteEditingField(isEditorFocused)
        core.palette.focusToken = UUID()
    }

    func select(_ id: NoteID, focusEditor: Bool = true) {
        pendingSelectionID = id
        runOperation { [weak self] generation in
            guard let self else { return }
            let selected = await store.select(id) { [weak self] in
                self?.permitsCompletion(generation) ?? false
            }
            // A newer selection has already replaced this one's target, and keeps its own.
            if pendingSelectionID == id { pendingSelectionID = nil }
            guard selected, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            guard permitsCompletion(generation) else { return }
            show(focusEditor: focusEditor)
        }
    }

    func rename(_ id: NoteID, to title: String) {
        runOperation { [weak self] generation in
            guard let self else { return }
            let renamedID = await store.rename(id, to: title)
            guard let renamedID, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            resumeSearch()
            if renamedID == store.activeID, permitsCompletion(generation) {
                show(focusEditor: false)
            }
        }
    }

    func trash(_ id: NoteID) {
        guard let title = store.summaries.first(where: { $0.id == id })?.displayTitle else { return }
        runOperation { [weak self] generation in
            guard let self else { return }
            let confirmed = await core.confirm(
                title: String(localized: "Move “\(title)” to Trash?"),
                message: String(localized: "You can recover it from the Trash in Finder."),
                symbol: nil,
                confirmTitle: String(localized: "Move to Trash"))
            guard confirmed, settings.notesEnabled, !Task.isCancelled else { return }
            // The row that takes the removed one's place, which is what the list leads one to expect.
            let neighbour = NoteListSelection.replacement(
                afterRemoving: id, from: store.summaries.map(\.id), fallback: nil)
            let removed = await store.trash(id, successor: neighbour)
            guard removed, settings.notesEnabled, !Task.isCancelled else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            resumeSearch()
            guard permitsCompletion(generation) else { return }
            show(focusEditor: false)
        }
    }

    /// Points Notes at a folder as it is; nothing is moved out of the old one.
    func chooseNotesFolder() {
        guard
            let url = FolderPicker.choose(
                message: String(localized: "Choose the folder your notes are kept in."),
                startingAt: store.notesDirectory)
        else { return }
        settings.notesFolder = AppPaths.contentFolderSetting(for: url, named: "Notes")
    }

    func resetNotesFolder() {
        settings.notesFolder = nil
    }

    func updateSource(_ source: String) {
        closeHeadingMenu()
        store.updateSource(source)
    }

    func updateCounts(_ input: NoteEditorInput, _ characterCount: Int) {
        guard input == editorInput else { return }
        self.characterCount = characterCount
        wordCountTask?.cancel()
        wordCountTask = Task { [weak self] in
            let wordCount = await NoteWordCount.count(in: input.source)
            guard let self, !Task.isCancelled, input == editorInput else { return }
            self.wordCount = wordCount
        }
    }

    /// Id and epoch, not the whole input: comparing a long source on every caret move is not free.
    func updateFormatting(_ input: NoteEditorInput, _ formatting: NoteFormatting) {
        let current = editorInput
        guard input.id == current.id, input.epoch == current.epoch, formatting != self.formatting else {
            return
        }
        self.formatting = formatting
    }

    /// The bar's buttons never take focus, but the editor is re-seated in case anything else did.
    func format(_ action: NoteEditAction) {
        guard isShowing, let editor, let window = editor.window else { return }
        if window.firstResponder !== editor { window.makeFirstResponder(editor) }
        editor.format(action)
    }

    /// Collapsing takes the heading button with it, so its menu cannot outlive it.
    func toggleFormattingBar() {
        guard showsFormattingBar else { return }
        closeHeadingMenu()
        // Explicit, because the chord changes this from outside any view's transaction.
        withAnimation(Self.barMotion) { isFormattingBarExpanded.toggle() }
        saveFormattingBarExpanded(isFormattingBarExpanded)
    }

    private static var barMotion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil : Theme.MenuMotion.chevronAnimation
    }

    func toggleHeadingMenu() {
        guard !headingMenuWasOpenAtPress else {
            headingMenuWasOpenAtPress = false
            return
        }
        guard !isHeadingMenuPresented else { return closeHeadingMenu() }
        isHeadingMenuPresented = true
        guard let window = editor?.window, window.isVisible else {
            isHeadingMenuPresented = false
            return
        }
        headingMenuController.show(above: window)
    }

    func chooseHeading(_ level: Int) {
        closeHeadingMenu()
        format(.setHeading(level: level))
    }

    func closeHeadingMenu() {
        guard isHeadingMenuPresented else { return }
        isHeadingMenuPresented = false
        headingMenuController.hide()
    }

    func noteWindowMouseDown() {
        headingMenuWasOpenAtPress = isHeadingMenuPresented
        closeHeadingMenu()
    }

    func editorReady(_ textView: NoteTextView) {
        editor = textView
    }

    private func request(_ presentation: Presentation) {
        guard settings.notesEnabled else { return }
        closeHeadingMenu()
        pendingPresentation = presentation
        guard loadTask == nil else { return }
        let generation = enablementGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            // Create is its own load: the collection it would wait for is the one it adds to.
            let loaded =
                if case .create(let source) = presentation {
                    await store.create(source: source)
                } else {
                    await store.start()
                }
            guard generation == enablementGeneration else {
                if !settings.notesEnabled { store.stop() }
                return
            }
            loadTask = nil
            guard loaded, settings.notesEnabled, !Task.isCancelled else { return }
            // The note this task just made satisfies a create still pending; never make a second.
            if case .create = presentation,
                pendingPresentation == presentation || pendingPresentation == .create(source: "")
            {
                pendingPresentation = .editor
            }
            guard let next = pendingPresentation else { return }
            pendingPresentation = nil
            await present(next)
        }
    }

    private func present(_ presentation: Presentation) async {
        switch presentation {
        case .latest:
            await showEditor { [store] in
                guard let latest = store.summaries.first?.id else { return true }
                return await store.select(latest)
            }
        case .editor:
            show(focusEditor: true)
        case .refresh:
            break
        case .create(let source):
            await showEditor { await store.create(source: source) }
        case .note(let id):
            await showEditor { await store.select(id) }
        }
    }

    /// Shown only if the change landed and no newer show or hide claimed the window meanwhile.
    private func showEditor(after change: () async -> Bool) async {
        let generation = presentationGeneration
        guard await change(), settings.notesEnabled, !Task.isCancelled,
            generation == presentationGeneration
        else { return }
        store.cancelSearch()
        // The field and the list it filters must agree, so the query goes with the search.
        if isShowing, !core.palette.query.isEmpty { core.palette.query = "" }
        show(focusEditor: true)
    }

    /// A newer show or hide retires an older operation's right to put what it loaded on screen.
    private func permitsCompletion(_ generation: Int) -> Bool {
        isShowing && generation == presentationGeneration
    }

    /// One collection operation at a time: a newer request cancels and supersedes an in-flight one.
    private func runOperation(_ body: @escaping @MainActor (Int) async -> Void) {
        operationTask?.cancel()
        operationID &+= 1
        let id = operationID
        let generation = presentationGeneration
        operationTask = Task { [weak self] in
            guard let self else { return }
            await body(generation)
            if self.operationID == id { self.operationTask = nil }
        }
    }

    private func present(_ issue: NotesStore.Issue) {
        guard issueTask == nil else {
            pendingIssue = issue
            return
        }
        issueTask = Task { [weak self] in
            guard let self else { return }
            switch issue {
            case .load(let failure):
                let retry = await core.reportFailure(
                    title: String(localized: "Couldn't Open Note"),
                    message: failure.localizedDescription,
                    symbol: "text.page",
                    recovery: String(localized: "Retry"))
                if retry { _ = await store.reload() }
            case .save(let failure):
                let retry = await core.reportFailure(
                    title: String(localized: "Couldn't Save Note"),
                    message: failure.localizedDescription,
                    symbol: "text.page",
                    recovery: String(localized: "Retry"))
                if retry { await store.retrySave() }
            case .operation(let failure):
                _ = await core.reportFailure(
                    title: String(localized: "Couldn't Update Note"),
                    message: failure.localizedDescription,
                    symbol: "text.page",
                    recovery: nil)
            }
            issueTask = nil
            if let pendingIssue {
                self.pendingIssue = nil
                present(pendingIssue)
            }
        }
    }
}
