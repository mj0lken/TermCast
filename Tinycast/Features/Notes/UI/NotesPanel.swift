import AppKit

/// The borderless child window the note's heading menu is drawn in; it never takes the keyboard.
final class NotesPanel: NSPanel, AnimatedPanel {
    init(content: NSView, size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        followMotion()
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    /// The note keeps its caret, reveal and chords beneath the menu.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
