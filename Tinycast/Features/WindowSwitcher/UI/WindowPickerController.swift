import AppKit
import SwiftUI

/// Owns the picker's panel: never key, because its keys arrive through `WindowPickerTap`.
@MainActor
final class WindowPickerController {
    private var panel: HUDPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(_ view: some View, size: CGSize, on screen: NSScreen) {
        let panel = panel ?? HUDPanel(acceptsMouseEvents: true)
        self.panel = panel
        let host = NSHostingView(rootView: view)
        // The controller owns the frame, as the palette's does; SwiftUI must not resize it.
        host.sizingOptions = []
        panel.contentView = host
        place(panel, size: size, on: screen)
        panel.orderFrontRegardless()
    }

    func resize(to size: CGSize) {
        guard let panel, panel.isVisible, let screen = panel.screen else { return }
        place(panel, size: size, on: screen)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func place(_ panel: NSPanel, size: CGSize, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded())
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}
