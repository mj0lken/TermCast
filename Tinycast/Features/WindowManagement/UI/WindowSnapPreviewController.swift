import AppKit
import SwiftUI

@MainActor
@Observable
private final class WindowSnapOverlayModel {
    var target: WindowDragSnap.Target?
    var pills: [WindowDragSnap.Pill] = []
    var showsPills = false
}

/// Click-through per-display overlays for Magnet-style activation pills and target previews.
@MainActor
final class WindowSnapPreviewController {
    private let model = WindowSnapOverlayModel()
    private var panels: [WindowSnapPreviewPanel] = []

    var isShowing: Bool { !panels.isEmpty }

    func update(
        target: WindowDragSnap.Target?, pills: [WindowDragSnap.Pill], showsPills: Bool,
        screens: [WindowPlacementEngine.Screen], geometry: AXGeometry
    ) {
        let shouldShow = target != nil || (showsPills && !pills.isEmpty)
        guard shouldShow else {
            hide()
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduceMotion ? 0 : Motion.duration(Theme.Duration.hover)

        if !isShowing {
            model.pills = pills
            model.showsPills = showsPills
            model.target = target
            open(screens: screens, geometry: geometry)
            return
        }

        model.pills = pills
        model.showsPills = showsPills
        if duration > 0 {
            withAnimation(.easeOut(duration: duration)) {
                model.target = target
            }
        } else {
            model.target = target
        }
    }

    func hide() {
        guard isShowing else { return }
        let closing = panels
        panels = []
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduceMotion ? 0 : Motion.duration(Theme.Duration.exit)
        guard duration > 0 else {
            closing.forEach { $0.orderOut(nil) }
            model.target = nil
            model.pills = []
            return
        }
        for panel in closing {
            panel.fadeOut(duration: duration) { [weak self] in
                guard let self, !self.isShowing else { return }
                self.model.target = nil
                self.model.pills = []
            }
        }
    }

    private func open(screens: [WindowPlacementEngine.Screen], geometry: AXGeometry) {
        panels = screens.compactMap { screen in
            let cocoaFrame = geometry.flip(screen.frame)
            guard !cocoaFrame.isEmpty else { return nil }
            let host = NSHostingView(
                rootView: WindowSnapDisplayOverlayView(
                    model: model, screenID: screen.id, origin: screen.frame.origin,
                    size: screen.frame.size
                ).motionScope())
            host.sizingOptions = []
            let panel = WindowSnapPreviewPanel()
            panel.contentView = host
            panel.setFrame(cocoaFrame, display: false)
            return panel
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduceMotion ? 0 : Motion.duration(Theme.Duration.enter)
        for panel in panels {
            if duration > 0 {
                panel.fadeIn(duration: duration) { panel.orderFrontRegardless() }
            } else {
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
        }
    }
}

private struct WindowSnapDisplayOverlayView: View {
    let model: WindowSnapOverlayModel
    let screenID: Int
    let origin: CGPoint
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target = model.target, target.screenID == screenID {
                let rect = target.placement.frame
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.roomCard, style: .continuous)
                shape
                    .fill(Theme.Colors.snapPreviewFill)
                    .overlay {
                        shape.strokeBorder(
                            Theme.Colors.snapPreviewStroke, lineWidth: Theme.Size.snapPreviewStroke)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX - origin.x, y: rect.minY - origin.y)
            }

            if model.showsPills {
                ForEach(model.pills.filter { $0.screenID == screenID }) { pill in
                    let isArmed =
                        model.target?.screenID == screenID && model.target?.zone == pill.zone
                    let capsule = Capsule(style: .continuous)
                    capsule
                        .fill(isArmed ? Theme.Colors.snapPillArmedFill : Theme.Colors.snapPillFill)
                        .overlay {
                            capsule.strokeBorder(
                                isArmed
                                    ? Theme.Colors.snapPillArmedStroke : Theme.Colors.snapPillStroke,
                                lineWidth: Theme.Size.snapPillStroke)
                        }
                        .frame(width: pill.frame.width, height: pill.frame.height)
                        .offset(x: pill.frame.minX - origin.x, y: pill.frame.minY - origin.y)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private final class WindowSnapPreviewPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .paletteDropGuide
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
