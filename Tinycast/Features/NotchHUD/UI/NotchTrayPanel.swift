import AppKit
import Carbon.HIToolbox

/// Interactive borderless panel hosting the expanded Notch tray above `.statusBar`.
final class NotchTrayPanel: NSPanel {
    var onPointerHoverChanged: ((Bool) -> Void)?
    var onSwipeUp: (() -> Void)?
    var onEscape: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .notchHUD
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func installTracking() {
        guard let view = contentView else { return }
        if let trackingArea { view.removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil)
        view.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerHoverChanged?(false)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, Int(event.keyCode) == kVK_Escape {
            onEscape?()
            return
        }
        if event.type == .scrollWheel {
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
            if dy > 18, abs(event.scrollingDeltaX) < abs(dy) {
                onSwipeUp?()
                return
            }
        }
        super.sendEvent(event)
    }
}
