import AppKit
import ColorSync

/// The one Cocoa↔AX converter. See docs/features/window-management.md#coordinate-space.
struct AXGeometry {
    let anchorHeight: CGFloat

    /// Snapshot once per command: `NSScreen.screens` can change, and mixing anchors corrupts.
    @MainActor
    init(screens: [NSScreen]) {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        anchorHeight = primary?.frame.height ?? 0
    }

    /// An involution through `maxY`, never scaled. docs/features/window-management.md
    func flip(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x, y: anchorHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    func flip(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: anchorHeight - point.y)
    }
}

/// Displays, converted into the AX space the geometry layer works in.
@MainActor
enum AXScreens {
    /// Current pointer location converted into AX coordinates.
    static func cursorPosition() -> CGPoint {
        AXGeometry(screens: NSScreen.screens).flip(NSEvent.mouseLocation)
    }

    /// Cocoa screens flipped through one snapshotted anchor, never one each.
    static func converted(
        _ screens: [NSScreen], geometry: AXGeometry
    ) -> [WindowPlacementEngine.Screen] {
        screens.enumerated().map { index, screen in
            // A display with no number still needs a stable, collision-free id for this call.
            return WindowPlacementEngine.Screen(
                id: screen.displayID.map(Int.init) ?? -(index + 1),
                frame: geometry.flip(screen.frame),
                visibleFrame: geometry.flip(screen.visibleFrame))
        }
    }

    /// Every connected display a layout can name, left to right, with its persistent identity.
    static func layoutScreens(geometry: AXGeometry) -> [WindowLayoutScreen] {
        let screens = NSScreen.screens
        let converted = converted(screens, geometry: geometry)
        let ordered = WindowPlacementEngine.ordered(converted)
        return ordered.compactMap { screen in
            guard let index = converted.firstIndex(where: { $0.id == screen.id }),
                let uuid = uuid(of: screens[index])
            else { return nil }
            return WindowLayoutScreen(
                display: WindowLayoutDisplay(uuid: uuid, name: screens[index].localizedName),
                screen: screen)
        }
    }

    /// Lowercased, so a stored identity and a live one can never miss each other on case.
    static func uuid(of screen: NSScreen) -> String? {
        guard let id = screen.displayID,
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return string.lowercased()
    }
}
