import Foundation

/// What a focused note asks of the collection around it, by chord.
enum NoteEditorCommand: Sendable, Equatable {
    case newNote
    case previousNote
    case nextNote
    case toggleFormattingBar
}

@MainActor
protocol NoteTextViewEditing: AnyObject {
    var rendersMarkdown: Bool { get }
    var markdown: NoteMarkdown { get }
    func focusChanged()
    func appearanceChanged()
    func dragSelectionEnded()
    func perform(_ command: NoteEditorCommand)
}
