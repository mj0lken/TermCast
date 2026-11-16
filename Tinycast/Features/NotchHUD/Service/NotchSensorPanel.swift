import AppKit

/// Zero-CPU passive sensor window parked strictly over the camera cutout to catch hovers and file drags.
final class NotchSensorPanel: NSPanel {
    var onHoverChanged: ((Bool) -> Void)?
    var onClicked: (() -> Void)?
    var onDragEntered: (() -> Void)?
    var onSwipeDown: (() -> Void)?

    private let sensorView = SensorContentView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .notchHUD
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false

        sensorView.onHoverChanged = { [weak self] inside in self?.onHoverChanged?(inside) }
        sensorView.onClicked = { [weak self] in self?.onClicked?() }
        sensorView.onDragEntered = { [weak self] in self?.onDragEntered?() }
        sensorView.onSwipeDown = { [weak self] in self?.onSwipeDown?() }
        contentView = sensorView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class SensorContentView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var onClicked: (() -> Void)?
    var onDragEntered: (() -> Void)?
    var onSwipeDown: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        // Minimal alpha keeps WindowServer hit-testing active over the camera cutout without drawing ink.
        NSColor(white: 0, alpha: 0.005).setFill()
        dirtyRect.fill()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }

    override func scrollWheel(with event: NSEvent) {
        let deltaY = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
        if deltaY < -10 {
            onSwipeDown?()
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .generic
    }
}
