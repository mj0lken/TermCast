import AppKit
import SwiftUI

/// A child window, so the menu can outgrow a short note window; it never takes key from the editor.
@MainActor
final class NoteHeadingMenuWindowController {
    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?
    private var pressMonitor: Any?

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    func show(above host: NSWindow) {
        let panel = ensurePanel()
        anchor(panel, above: host)
        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
        }
        // A child of the palette has to sit at its level, or the palette's own level buries it.
        panel.level = host.level
        panel.orderFront(nil)
        panel.invalidateShadow()
        watchPresses(in: host)
    }

    func hide() {
        if let pressMonitor { NSEvent.removeMonitor(pressMonitor) }
        pressMonitor = nil
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Any press in the host closes the menu, the heading button's own included.
    private func watchPresses(in host: NSWindow) {
        guard pressMonitor == nil else { return }
        pressMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self, weak host] event in
            if event.window === host { self?.coordinator.noteWindowMouseDown() }
            return event
        }
    }

    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let hosting = NSHostingView(
            rootView: NoteHeadingMenuView().environment(coordinator).motionScope())
        hosting.sizingOptions = []
        let panel = NotesPanel(content: hosting, size: Theme.Size.noteHeadingMenu)
        self.panel = panel
        return panel
    }

    /// Hangs off the heading button itself, whose frame arrives flipped from the SwiftUI bar.
    private func anchor(_ panel: NotesPanel, above host: NSWindow) {
        let button = coordinator.headingButtonFrame
        let origin = CGPoint(
            x: host.frame.minX + button.minX,
            y: host.frame.maxY - button.minY + Theme.Spacing.xs)
        panel.setFrame(NSRect(origin: origin, size: Theme.Size.noteHeadingMenu), display: false)
    }
}
