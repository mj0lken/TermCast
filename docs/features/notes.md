# Notes

Notes is an unlimited local collection of plain Markdown files, shown as a launcher screen: the
palette's search field filters a list of every note, beside an editor that renders the open note's
Markdown in place. The screen edits one active note at a time, which is also the list's highlighted
row. One command, **Notebook**, opens it from the launcher, a global shortcut, the menu bar or the
notch tray.

## Invariants

- **One regular, non-hidden `.md` file is one note.** Its filename without the extension is its title;
  the source contains no frontmatter, embedded ID, or title field, and there is no database or sidecar.
- **A note the user has not named shows its first line instead.** Only the names `create` claims yield
  it, it is presentation and nothing else, and naming the note replaces it. The editor draws that line
  as the title while Render Markdown is on; a named note's first line is body text.
- **Notes is a palette screen, not a window.** `PaletteMode.notes` lives in the palette panel and takes
  its position, width, glass, header field, back chevron and bottom bar. It leaves with the palette,
  which hides when it loses key, so no note stays on screen behind another app. `NotesPanel` survives
  only as the borderless child window the heading menu is drawn in.
- **The highlighted row is the open note.** There is no second cursor: moving the highlight opens the
  note it lands on, and nothing on the screen shows one note while another is highlighted.
- **The storage is the source.** The string in `NSTextView`, `NotesStore`, search, and the file are
  identical; rendering is attributes and drawing over that string, never a second string or an offset
  map.
- **The caret's line is raw.** Every line under the selection shows its Markdown; an unfocused editor
  reveals nothing.
- **Styling never reaches undo.** Attribute passes bypass `shouldChangeText`; every edit a Markdown
  gesture makes goes through `NoteTextView.performEdit`.
- **Render Markdown off is the literal editor**, with native Return, Tab and shortcuts and no parsing.
- **The formatting bar is another way to press a shortcut.** Each button sends its chord's
  `NoteEditAction` through `NoteTextView.format`, so it has the chord's gate, undo step and autosave,
  and a button is lit exactly when its toggle would remove that formatting.
- **Only the active note can be dirty.** Switching, creating, renaming, and deleting first flush it, so
  collection navigation cannot abandon an in-memory draft.
- **Tinycast is the only writer while editing.** There is no watcher or disk revision check: a save
  replaces the file with what is in the editor. Every show re-lists the folder and reloads the clean
  active note; an unsaved draft is retained, including after a failed save.
- **Search is on demand and unindexed.** An empty query lists metadata plus the first 4 KB of every
  note, which is where a row's preview comes from; a nonempty query reads bodies sequentially off-main
  and retains no collection-sized source cache.
- **Off means no entry point or Notes work.** The feature is off by default; its shortcut no-ops, its
  command is absent, and enabling alone does not enumerate or create the Notes directory.
- **The collection may be empty.** Deleting the last note is allowed and creates no replacement; the
  screen shows its empty state, and ↵ there is Create Note.
- **Notes wears the palette's look, not its own.** Rows are the palette's row grammar filled selection,
  then hover, then clear, the search field is the palette's own, and every control is a `BarButton`.
  The one hairline is the one a palette draws between a list and the pane beside it. A Notes-only
  row or control is a defect.
- **A key meant for a note never navigates the palette.** While the editor, its find bar or a rename
  field has the keyboard, `PaletteState.noteEditingField` is set, and Escape is offered to
  `handlePaletteEscape` before the palette's own back step.
- **The editor is a surface snippets expand into.** `NoteTextView` adopts `InjectableTextView`,
  so a typed keyword is written straight into the text storage rather than posted as events at
  whichever app happens to be frontmost. Quick Actions also read and replace its selected text in
  process. A note is in the palette and never behind it, so the Snippets browser's ↵ does not reach
  one. Only AI Chat's composer adopts it too: see
  [snippets.md](snippets.md#text-delivery-and-pasteboard-safety).

## Storage and identity

The per-channel directory is:

```text
~/Library/Application Support/<bundle-id>/Notes/
```

**Notes Folder** in the Notes pane, or `notes.folder` in the [settings file](settings-file.md), uses
another folder, absolute or under `~/`, as it is: nothing moves out of the old one. `NotesStore.relocate`
saves the open draft where it was before it lists the new folder. The folder is excluded from backups,
since it names a place on this Mac.

`NoteID` is the relative filename. A rename therefore returns a new identity; there are no per-note
launcher items, hotkeys, favorites, or visibility settings that could retain the old one. Immediate
regular `.md` children are sorted by modification date, then localized title. Subdirectories, hidden
files, and symbolic links are ignored.

Create uses `Untitled.md`, then `Untitled 2.md`, and so on, and rename claims a free name by the same
rule. `importNotes` claims one the same way, so a note restored from a backup lands beside the note it
shares a title with rather than over it. Collisions with *another* note are case- and diacritic-insensitive, so `plán` beside `Plan`
becomes `plán 2.md`. A note never collides with itself: only an exact filename match is a no-op, which
is what lets a rename change nothing but the case or the accents. The active filename is local UI state
in UserDefaults and does not ride settings backups.

## Derived titles

A note still carrying a name `create` claimed — `Untitled`, `Untitled 2`, … — shows the first line of
its source that carries visible text. `NoteTitle` owns that rule: blank, rule and fence lines are
skipped, block and inline Markdown markers are dropped whether or not rendering is on, and the line is
capped to 120 characters so no row has to carry a paragraph. `NoteSummary.title` remains the filename; `displayTitle` is what every
surface renders — list rows and their VoiceOver labels, the Actions menu's header, the Trash
confirmation, and the title band of `NoteSearch`, so a fuzzy query reaches a note nobody has named.
An empty unnamed note displays a localized Untitled label, preserving its filename and numeric suffix.

`list()` reads at most 4 KB of every note. From that head it derives an unnamed note's title and every
note's `preview`: `NoteTitle.preview(of:skippingTitle:)` joins the visible lines into one run capped at
240 characters, leaving out the line an unnamed note already shows as its title. The screen shows a
title only in the list row, which reads the last listing, so an unnamed note's row follows its first
line on the next autosave; the editor draws that line as the title as it is typed.
Renaming edits the filename, so the rename field starts from `title`: a derived line stands in for a
name, and is never one.

`NotesRepository` owns list, create, load, save, rename, Trash, and search reads. Every
URL is validated as an immediate child of the injected directory. It lives in `Service/` because it
performs filesystem effects; `NotesStore` drives its blocking work from detached tasks.

## Ownership and enablement

`AppCore` owns `NotesStore` and lazily constructs `NotesCoordinator`. `RootPaletteView` builds
`NotesScreen`, the `PaletteScreen` conformer, for `PaletteMode.notes`; its views read only the
coordinator, which `PaletteEnvironment` puts in `@Environment`, and never mutate the store.

Settings > Notes owns `AppSettings.notesEnabled`, which is false when absent. The pane lists
**Notebook** from `CommandCatalog`, so it can still render it while `AppIndex` omits it. It is that
command's only pane: `SettingsTab.ownedCommands` names it, which takes it out of Settings > Commands
and out of reach of `Enable Commands` — Notes' own switch is the one that decides it exists.

`AppCore` observes enablement and calls `NotesCoordinator.applyEnabled()`. Disabling hides the palette
if it is on the Notes screen, invalidates pending presentation work, cancels search, flushes the
draft, and removes the command. A failed flush retains the draft for retry.

## Command, list, and screen

**Notebook** is the one command. Its identifier is still `CommandID.showNotes`
(`command:show-notes`), which predates the name, because shortcuts and favorites are keyed by it. It
toggles: with the palette already on the Notes screen it hides the palette; otherwise it re-lists the
folder, opens the most recently edited note and puts the caret in it. Run from the launcher it
navigates the palette there, so Escape comes back to the launcher. There is no Create Note or Search
Notes command any more: both are things the screen does.

Everything that opens the screen goes through `NotesCoordinator.request`, which reads the folder
before it shows anything and then calls `PaletteCoordinator.showPalette(mode: .notes)` if the screen
is not already up. A note deep link opens that note, and a `command/show-notes` link carrying text
creates a note from it; both land with the caret in the note. A screen that came up any other way,
such as a re-summoned palette that kept its mode, reports through `screenDidOpen` and gets the same
read with nothing on screen moved.

Settings > Notes > **Show in Menu Bar** is `AppSettings.notesShowsInMenuBar`, off when absent and
carried by settings backups. While it and Notes are both on, `NotesCoordinator` owns a
`NotesMenuBarController`: a click on its status item is Notebook, and a right-, Control- or
Option-click opens a menu holding New Note. Turning either setting off removes the status item rather
than hiding it. The notch tray's Notes button is Notebook too.

### The screen

`NotesScreen` is the `PaletteScreen` conformer. Its `rows` are the visible notes, so the palette's
selection, ↑ and ↓, hover arming and scroll following are the launcher's own. The palette supplies the
back chevron, the search field reading "Search notes…" and the floating bottom bar, whose pill is the
primary action (↵) beside Actions (⌘K). `NotesHeaderControls` adds up to three `BarButton`s at the
header's trailing end:

- **Create Note** (`plus`, ⌘N), always.
- **Formatting** (`paintbrush`, ⌥⌘T), while a note is open and Render Markdown and Show Formatting Bar
  are both on. It is lit while the bar is out.
- **Note Info** (`info.circle`), while a note is open. Hovering it shows the info card and a click
  pins the card open; another click or Escape drops it.

The body is `NotesList`, one vertical hairline of `separator`, and `NoteEditorPane`: the open note's
editor, with the formatting bar under it while that is out. The list opens `noteListWidth` wide, a
quarter narrower than the clipboard's, scaled with Interface Size. The hairline carries a 10-point
strip that drags it between `noteListMinWidth` and `noteListMaxWidth`; the dragged width lasts for the
visit, and every open starts from the default again. With no rows the whole body is the palette's
`EmptyResults` instead, reading `Searching notes…` while a search is in flight, `No notes found` under
a query and `No Notes` otherwise.

The info card is `NoteInfoCard`, drawn in the palette at the body's top-trailing corner, never a
system popover: the word count, the character count, and the file's creation date where the volume
keeps one. It is the only place the counts appear. The card is solid, because it hangs over the
note's text, and takes no clicks.

### The list

A row is the palette's row grammar: the 26-point icon slot, the display title, and one line of preview
under it, in a `Radius.row` background filled selection, then hover, then clear. A note with nothing
to preview is a title alone. Rows are sorted by modification date, so the note being edited rises to
the top on its next autosave, and the list dissolves under the palette's bars with `edgeDissolve()`
like every other palette list.

An empty query lists every note by recency; a nonempty query searches titles and literal bodies after a
120-millisecond debounce. Results are capped at 200, and generation checks prevent superseded search or
selection work from publishing. A new query lands the highlight on the open note's row when the
results still hold it and on the first row otherwise (`landingSelection`). Opening a result keeps the
query, so several results can be read in turn. Leaving the screen ends the search, and a note link
opened while the screen is up clears the palette's query with it, so the field and the list agree.
Renaming and trashing a note end `NotesStore`'s search, so the coordinator applies the field's query
again as soon as they finish; creating a note clears the field with the search. While a search is
showing, rows are read through the current listing by `NoteID`, so a result edited mid-search shows its
new title and preview on the next autosave. While a query's results are still being read the list
keeps the rows it had, so a keystroke never blanks the screen or unmounts the editor, and ↵ on a list
that is empty only because a search is running does not create a note.

Only the highlight moving opens a note (`preview`); the rows moving under it never do. The highlight
is drawn on the open note's row whenever that row is in the list, so the autosave that re-sorts the
list carries the highlight with the note, and `reseat` moves the palette's selection to follow. When
the open note leaves the list, as under a query that no longer matches it, the highlighted row opens
instead. A click highlights a row and leaves the keyboard where it was, a double-click also puts the
caret in its note, and a right-click highlights it and opens Actions. A held arrow key steps from the
row the last press was heading for, not from the note still loading. The editor keeps the caret it had
while a row loads, so a key can land meanwhile: `select` compares `sourceRevision` across the load and
flushes again before it replaces the source, so that key is saved to the note it was typed in.

### Actions

↵ is **Edit Note**, which puts the caret in the highlighted note, or **Create Note** when there are no
rows. ⌘K opens the Actions menu under the note's display title:

| Action | Shortcut |
| --- | --- |
| Edit Note | ↵ |
| Create Note | ⌘N |
| Rename Note | ⌘E |
| Copy Deeplink | ⇧⌘C |
| Show in Finder | ⌘F |
| Move to Trash | ⌃X |
| Notes Settings | ⌥⌘, |

With no rows the menu holds Create Note and Notes Settings only. ⌘⌫ moves the highlighted note to
Trash as ⌃X does. These are the palette's row chords, resolved by `PaletteShortcut` and answered in
`NotesScreen.perform`, so they act while the search field has the keyboard.

Rename Note edits the filename in an inline field in the row. Return commits, and so does the field
losing the focus or the highlight moving to another row; only Escape discards it. Move to Trash asks
through Tinycast's own dialog, then opens the row that took the removed one's place:
`NotesStore.trash(_:successor:)` loads that note directly, and falls back to the newest when it is
gone.

### Focus and Escape

The keyboard is in one of three places: the palette's search field, the editor, or a rename field.
Command-L moves it between the search field and the open note, from either side;
`PaletteWindowController` answers it at the panel so it works wherever the keyboard is, and a click in
the note or on the field does the same. A focused note keeps every text key: `NotesScreen` reports
`ownsVerticalKeys` and answers no row chord while `PaletteState.isEditingField` is set, and the
palette's Tab and Command-K handlers stand down for it, so the arrows move the caret, Tab indents,
Command-K is a link and Command-Delete deletes a line rather than driving the list. `NoteTextView`
carries the chords a note needs from the collection and reports them as a `NoteEditorCommand`:

| Shortcut in a note | Does |
| --- | --- |
| ⌘N | creates a note |
| ⌥⌘↑, ⌥⌘↓ | opens the previous or next row, keeping the caret in the editor |
| ⌥⌘T | shows or hides the formatting bar |
| ⌘F | opens AppKit's find bar in the note |

`NoteEditorView` reports the editor's focus, and `NotesCoordinator` passes it to
`PaletteState.noteEditingField`, which is also set by an active rename and by a showing find bar. It
is what keeps a bare Backspace under the caret, or in the find bar's field, from being the palette's
back step, and what leaves ⇧⇥ to outdent the note instead of cycling the palette. `focusEditor` waits
out the palette's own summon, which refocuses its search field a beat later, then seats the editor
once, so a later click on the search field keeps the focus.

`PalettePanel` offers Escape to `NotesCoordinator.handlePaletteEscape` before the palette's own rule,
and each press undoes one layer: the heading menu, the find bar, a pinned info card, a rename, then
the editor's focus, which goes back to the search field. From the search field Escape is the
palette's: it clears a nonempty query, then steps back or closes. ⌘W closes the palette from
anywhere. Command-Q is bound to nothing app-wide, so no chord over Notes can quit Tinycast.

`screenDidClose` runs when the screen is left or the palette hides. It closes the heading menu, drops
the rename, the search and the pinned card, retires pending presentation work and flushes the draft.

## Editor

`NoteEditorView` is one TextKit 2 `NSTextView` inside an `NSScrollView`. It installs
`NoteEditorInput.source` as `NSTextView.string` and never swaps that string for a display version.
Rendering is attributes and drawing over the source.

### Parsing

With rendering on, the first line of a note whose filename is still one `create` claimed is drawn in
`NoteMarkdownTypography.title` when it is a plain paragraph: `NoteMarkdownRenderer.titlesFirstLine`
passes `isTitle` for line 0, so a line typed above it takes the title over on the next restyle. A
heading or list on the first line keeps its own style, and the literal editor sets no title.

`Model/NoteMarkdownParser` splits the source on the same boundaries as `NSString.lineRange(for:)`, so
one line is one TextKit paragraph. `NoteMarkdown` gives each line its kind, UTF-16 ranges for its
content, block marker and task checkbox, and a list level from an indent stack. A source ending in a
terminator, and an empty source, get a final zero-length line, so a caret on the empty last row sits on
a real line like any other. Inline spans are not stored: `NoteMarkdown.inlines(of:)` scans the one line
asked for, which is all the styler, the editing rules and `NoteTitle` ever need.

It covers headings 1 to 6 (4 to 6 look like 3), bold, italic, bold italic, strikethrough, inline code,
links, bare `http` and `https` URLs, bullet, numbered and task lists with nesting, quotes, fenced code
blocks and horizontal rules. Inline spans never cross a line. Images, underline, HTML, setext headings,
indented code, footnotes, reference links and blocks nested inside quotes stay plain text. A GFM table
(a pipe row, a delimiter row with as many cells, then the pipe rows after it) also stays plain text, but
is recognised so it gets no inline styling: it shows in the code font, with wrapped rows hanging under
their first line, and a delimiter row typed under existing rows restyles all of them.
The whole note is reparsed on each edit. The AI chat's `MarkdownBlock` is a separate read-only parser
and is not shared.

### Rendering

`UI/NoteMarkdownRenderer` holds the parse and the set of revealed lines, and is the text storage's
delegate. Every mutation reports its edited range and length delta there, including the undo, redo and
marked-text ones that post no `textDidChange`, and several are folded into one pending edit.
`textDidChange`, `textViewDidChangeSelection` and any read of the parse consume it and reparse. The
edited lines and one neighbour on each side are restyled, widened to the rest of the note when a fenced
block moved and to any list line whose depth changed.

`NoteMarkdownStyler` turns one line into attributes. `NoteMarkdownTypography` sets the body one
system text style up (title3) and headings at largeTitle, title1 and title2, with or without
rendering; Interface Size does not scale Notes. A hidden marker gets a 0.01-point system font and
a clear colour, so it stays in the string at almost no width. Fence and rule lines are cleared at their
normal font instead, so they keep their row height. Every list item (bullet, numbered or task) gets 8
points of space after it, rendered or revealed, so items read as separate rows and moving the caret
never shifts them; a wrapped item keeps normal line spacing. A restyle writes straight to `NSTextStorage` inside
`beginEditing` and `endEditing`, then invalidates layout for those lines. It never calls
`shouldChangeText`, which is what keeps styling off the undo stack.

A bullet or numbered marker becomes a list only after a space or tab; a lone `-` or `1.` stays literal.

`NoteRevealPolicy` picks the lines that show raw Markdown: every line under the selection, plus both
fences of a code block the selection is in. Nothing is revealed unless the editor is first responder in
the key window. Revealed markers use `textTertiary`. During a drag selection the reveal waits for
mouse-up, because revealing moves text under the pointer. Bullets keep their dot under the caret;
other revealed list markers keep the rendered marker's `textSecondary` colour. Revealed non-bullet list
and quote lines hang their source marker left of the content indent, so text stays where the rendered
line had it. Empty list items keep body-sized invisible markers so their line height does not collapse.
Other caret lines are raw, keeping the caret out of hidden text.

### Block drawing

`NoteLayoutFragmentProvider` is the text layout manager's delegate. A paragraph whose first character
carries a `NoteBlockDecoration` is laid out by `NoteBlockLayoutFragment`, which draws code bands with
their language label, quote bars, rules, bullets, the source's own list numbers, and checkboxes, all
list markers in a neutral gray. Vertical
spacing comes from paragraph styles: overriding the fragment's frame would leave the caret above the
glyphs. A marker sits on the item's first line of text, not its first line fragment: a first word
too wide for the line wraps below the hidden marker, leaving the marker a line of almost no height,
and the checkbox hit test reads the same line. There are no text attachments, overlay controls,
`NSTextList`, `NSTextTable` or private API.

### Editing

`Model/NoteMarkdownEditing` turns a gesture into a `NoteEditPlan`, one replacement plus the selection
after it. Nil means AppKit handles the key natively. `NoteTextView.performEdit` applies a plan through
`shouldChangeText`, `replaceCharacters` and `didChangeText`, so each gesture is one undo step and
reaches autosave.

- Return continues a list or quote and leaves it on an empty item. Tab and Shift-Tab nest list items
  by four spaces. Backspace at an item's content start outdents it, then removes its marker. These
  edits renumber the ordered run they touch in the same undo step.
- Typing `[] ` or `[ ] ` at the start of a paragraph makes `- [ ] `.
- ⌥⌘C wraps the touched lines in a fenced block, or removes the fences of the block the selection is
  in. On an empty line it opens an empty block with the caret inside.
- ⇧⌘B adds `> ` to each touched line, or removes one `>` from each when all of them are quotes. Blank
  lines inside a selection, code, tables and rules are left alone.
- Pasting a single `http` or `https` URL over text selected on one line makes `[text](url)`.
- Clicking a checkbox toggles `[ ]` and `[x]` without moving the caret. The hit test uses
  `NoteCheckboxGeometry`, the rect the fragment draws, grown by 3 points.
- Clicking a rendered link opens it, unless the click lands in the outer 30% of the label's first or
  last glyph, which places the caret. Only `http`, `https` and `mailto` open. A revealed line carries
  no link attribute, so its URL is edited as text.

| Shortcut | Does |
| --- | --- |
| ⌘Z, ⇧⌘Z | undo, redo |
| ⌘B, ⌘I, ⌘E | bold, italic, inline code |
| ⇧⌘X | strikethrough |
| ⌥⌘C | code block |
| ⇧⌘B | quote |
| ⌘K | link |
| ⇧⌘7, ⇧⌘8, ⇧⌘9 | numbered, bullet, task list |
| ⌥⌘1, ⌥⌘2, ⌥⌘3 | heading 1, 2, 3 |
| ⌥⌘0 | plain paragraph |

Digits match by key code. `NoteTextView.performKeyEquivalent` answers these only while it is first
responder, so the same key can mean something else from the search field: ⌘E is inline code in a note
and Rename Note from the list, ⌘K is a link in a note and Actions from the list, and ⌘F is the find
bar in a note and Show in Finder from the list. In a note, ⌘E replaces AppKit's Use Selection for
Find. The chords a note answers for the collection around it are under
[Focus and Escape](#focus-and-escape).

AppKit still owns typing, selection, Cut, Copy, Paste, Select All, Find, marked text, emoji, combining
characters and undo grouping. The editor handles ⌘Z and ⇧⌘Z while focused, including in the
non-activating panel and with rendering off. Its native undo manager holds one linear history in
memory; editing after undo discards redo. The coordinator observes undo and redo completion with
main-actor notifications, so both reach autosave, rendering, formatting and the counts.
Copy yields raw Markdown and VoiceOver reads the source. Changing the note
identity or editor epoch reinstalls and restyles the string and clears the previous document's undo
history. Snippets expand through `insertText` and are styled like typed text. The empty-note placeholder
is drawn in the text view, so opening the find bar moves it with the editor content.

### The formatting bar

While Render Markdown and Show Formatting Bar are both on, the header's `paintbrush` button, or ⌥⌘T
with the caret in the note, shows and hides `NoteFormattingBar` in a `bottomBarHeight` band under the
editor. The bar is one frosted capsule of `BarButton`s at the band's trailing edge: a heading menu,
Bold, Italic, Strikethrough, Inline Code and Link, then Code Block and Quote, then Numbered, Bullet
and Task List. Hovering a button shows its name and shortcut. Each button is a 28-point square. With
the bar hidden there is no band at all, and the editor takes its height.

Shown or hidden is screen state, not a preference: `AppCore` reads and writes it under
`notesFormattingBarExpanded` in `UserDefaults` and hands it to `NotesCoordinator`, the way it hands
the store the active note's filename. It is deliberately not an `AppSettings` key, so no settings
backup carries it. With Show Formatting Bar off there is no header button and no bar.

`NoteEditorView` reports `NoteMarkdownEditing.formatting(source:selection:markdown:)` on every
install, edit and selection change, and `NotesCoordinator` publishes it only when it changed. That
function uses the same span and line rules as the toggles, so a lit button always undoes. A click goes
`NotesCoordinator.format` → `NoteTextView.format`, re-seating the editor as first responder first if
anything else took it. The buttons never take focus, so the caret and its revealed line stay put.

The heading button opens `NoteHeadingMenuView` (Heading 1 to 3 and Text, the current one checked) in a
`NotesPanel`: a borderless child window of the palette, raised to the palette's level, that never
becomes key, so it can hang above its button while the editor keeps its caret and chords. It closes on
a choice, Escape, any mouse down in the palette, an edit, hiding the bar, and the screen closing. It
is a copy of the popover menu's row look, because `PopoverMenu` depends on palette state.

### The setting

Settings > Notes > **Render Markdown** is `AppSettings.notesRendersMarkdown`, on when absent and carried
by settings backups. `NotesCoordinator` exposes it and `NoteEditorPane` hands it to `NoteEditorView`.
Off gives the literal editor: one font and colour, native Return, Tab and shortcuts, and no parsing.
Flipping it restyles the open note without touching its undo history or marking it dirty.

Settings > Notes > **Show Formatting Bar** is `AppSettings.notesShowsFormattingBar`, on when absent and
carried by settings backups. It only takes effect while Render Markdown is on, and its row is disabled
otherwise.

An empty note shows a `Start writing…` placeholder aligned to the 16-point text container inset. The
character count comes straight off `NSTextStorage.length`. The word count is `NoteWordCount`: ICU word
boundaries over the source, so Markdown markers and punctuation are not words and text without spaces
still splits into words. It costs a pass over the whole note, so `NotesCoordinator` runs it off-main
after every report and applies only the result for the current editor input. Both counts are read in
the info card, which the header offers only while a note is active.

## Autosave

Editor changes update the main-actor draft immediately and debounce save for 300 milliseconds. Only the
active source is retained. A successful save refreshes metadata ordering; switching waits for the same
flush before loading another source. The palette hides when it loses key, so leaving the screen and
hiding the palette both flush at once rather than waiting out the debounce. Termination awaits that
flush before the app exits, but never vetoes the quit.

**A save overwrites whatever is on disk.** There is no watcher, no revision comparison and no conflict
state: editing the *active* note in another app while Tinycast has it open loses that edit the next time
the debounce fires. Show in Finder (⌘F) invites exactly that, and this is the accepted trade for a
feature whose whole job is one local editor. Opening the screen re-lists the folder and reloads the
active note if it is clean, waiting for an in-flight save first. An unsaved draft, including one whose
save failed, stays in the editor. Edits or selection changes during the read retire its result.
Unchanged contents retain editor history; a changed source or note identity resets it. If the active
file was removed, loading chooses a remaining note, or the empty state when none remain.

## Verification

`Tests/NotesTests.swift` compiles the shipped Notes model and service sources with the real fuzzy
matcher. It covers repository safety, unique-name claiming, derived titles and row previews, search,
selection, autosave, external reloads, draft preservation, empty collections, list rename and
replacement rules, and cancellation, plus the Markdown parser, every edit plan, the formatting each
selection reports, the reveal policy and the word count.

`Tests/NotesEditorTests.swift` uses real TextKit 2 and AppKit undo objects. It runs the native
Cut/Copy/Paste, the native find bar, Unicode and marked-text cases with rendering off and on, and covers
undo isolation, undo and redo shortcut routing, source publication and character count, linear history,
exact source after styling, hidden and revealed markers, restyling after edits and after undo, block
decorations and layout fragments, list keys, chords, the task rule, checkbox toggles, link schemes,
pasting a URL, the first-line title, and the formatting reports and `format(_:)` the formatting bar
uses.
`Tests/NotesEditorPerformanceTests.swift` times install, typing and caret moves on
a 100,000-character note; its budget is in `docs/testing.md`. The palette screen is not automated: the
Notes manual sweep in `docs/testing.md` covers the command, shortcuts, the list, the Actions menu, focus
between the search field and the editor, Finder, Trash recovery, and accessibility.
