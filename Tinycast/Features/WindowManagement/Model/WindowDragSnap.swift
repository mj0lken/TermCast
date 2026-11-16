import CoreGraphics
import Foundation

/// Magnet-style screen-edge and corner activation areas for mouse drag-to-snap.
enum WindowActivationZone: String, CaseIterable, Identifiable, Sendable {
    case topLeft = "top-left"
    case top
    case topRight = "top-right"
    case leftUpper = "left-upper"
    case left
    case leftLower = "left-lower"
    case rightUpper = "right-upper"
    case right
    case rightLower = "right-lower"
    case bottomLeft = "bottom-left"
    case bottomFirstThird = "bottom-first-third"
    case bottomCenterThird = "bottom-center-third"
    case bottomLastThird = "bottom-last-third"
    case bottomRight = "bottom-right"

    var id: String { rawValue }

    var command: WindowCommand.ID {
        switch self {
        case .topLeft: .topLeftQuarter
        case .top: .maximize
        case .topRight: .topRightQuarter
        case .leftUpper, .rightUpper: .topHalf
        case .left: .leftHalf
        case .right: .rightHalf
        case .leftLower, .rightLower: .bottomHalf
        case .bottomLeft: .bottomLeftQuarter
        case .bottomFirstThird: .firstThird
        case .bottomCenterThird: .centerThird
        case .bottomLastThird: .lastThird
        case .bottomRight: .bottomRightQuarter
        }
    }

    var title: String {
        WindowCommandCatalog.command(id: command)?.name ?? rawValue
    }

    /// Resolves the tiled command on `screen`, adapting side zones to vertical thirds in portrait.
    func command(on screen: WindowPlacementEngine.Screen) -> WindowCommand.ID {
        guard screen.visibleFrame.height > screen.visibleFrame.width else { return command }
        switch self {
        case .leftUpper, .rightUpper: return .topThird
        case .left: return .middleThird
        case .right: return .middleThird
        case .leftLower, .rightLower: return .bottomThird
        default: return command
        }
    }

    /// Zones that share one tiled command, mirroring Magnet's per-command activation area map.
    static func zones(for command: WindowCommand.ID) -> [Self] {
        allCases.filter { $0.command == command }
    }
}

/// Pure drag-to-snap activation area geometry, hit-testing and drag-away unsnap math in AX space.
enum WindowDragSnap {
    static let edgeWidthRange = 1...30
    static let defaultEdgeWidth = 14
    static let areaScaleRange = 15...50
    static let defaultAreaScale = 30

    struct Options: Equatable, Sendable {
        var edgeWidth: Int = WindowDragSnap.defaultEdgeWidth
        var areaScale: Int = WindowDragSnap.defaultAreaScale
        var disabledZones: Set<WindowActivationZone> = []

        init(
            edgeWidth: Int = WindowDragSnap.defaultEdgeWidth,
            areaScale: Int = WindowDragSnap.defaultAreaScale,
            disabledZones: Set<WindowActivationZone> = []
        ) {
            self.edgeWidth = WindowDragSnap.sanitizedEdgeWidth(edgeWidth)
            self.areaScale = WindowDragSnap.sanitizedAreaScale(areaScale)
            self.disabledZones = disabledZones
        }
    }

    struct Pill: Identifiable, Equatable, Sendable {
        var zone: WindowActivationZone
        var screenID: Int
        var frame: CGRect

        var id: String { "\(screenID):\(zone.rawValue)" }
    }

    struct Target: Equatable, Sendable {
        var zone: WindowActivationZone
        var command: WindowCommand.ID
        var screenID: Int
        var placement: WindowPlacementEngine.Placement
    }

    private static let seamSlack: CGFloat = 2
    private static let unsnapDragThreshold: CGFloat = 8
    private static let pillThickness: CGFloat = 10
    private static let pillInset: CGFloat = 4

    static func sanitizedEdgeWidth(_ value: Int) -> Int {
        min(max(value, edgeWidthRange.lowerBound), edgeWidthRange.upperBound)
    }

    static func sanitizedAreaScale(_ value: Int) -> Int {
        min(max(value, areaScaleRange.lowerBound), areaScaleRange.upperBound)
    }

    static func normalizedDisabledZones(_ rawValues: [String]) -> [String]? {
        var seen: Set<WindowActivationZone> = []
        for raw in rawValues {
            guard let zone = WindowActivationZone(rawValue: raw) else { return nil }
            seen.insert(zone)
        }
        return WindowActivationZone.allCases.filter(seen.contains).map(\.rawValue)
    }

    // MARK: - Snap zones

    /// Resolves the active zone, command and target placement when `cursor` enters a snap zone.
    static func target(
        at cursor: CGPoint, in screens: [WindowPlacementEngine.Screen], gap: CGFloat,
        fitTightlyToEdges: Bool, options: Options = Options()
    ) -> Target? {
        guard let host = screen(under: cursor, in: screens),
            host.visibleFrame.width > 0, host.visibleFrame.height > 0,
            let zone = zone(at: cursor, on: host, among: screens, options: options)
        else { return nil }

        let command = zone.command(on: host)
        let probe = CGRect(
            x: host.visibleFrame.midX - 10, y: host.visibleFrame.midY - 10, width: 20, height: 20)
        guard
            let placement = WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: command, windowFrame: probe, screens: [host], gap: gap,
                    fitTightlyToEdges: fitTightlyToEdges))
        else { return nil }

        return Target(zone: zone, command: command, screenID: host.id, placement: placement)
    }

    /// Which activation zone `cursor` hits on `host`, or nil in the interior or when disabled.
    static func zone(
        at cursor: CGPoint, on host: WindowPlacementEngine.Screen,
        among screens: [WindowPlacementEngine.Screen], options: Options = Options()
    ) -> WindowActivationZone? {
        let frame = host.frame
        let visible = host.visibleFrame
        let outerMargin = CGFloat(sanitizedEdgeWidth(options.edgeWidth))
        let seamMargin = min(outerMargin, 4)

        let leftSeam = hasNeighbor(
            beyond: frame.minX, direction: .leading, perpendicular: cursor.y, axis: .horizontal,
            excluding: host.id, in: screens)
        let rightSeam = hasNeighbor(
            beyond: frame.maxX, direction: .trailing, perpendicular: cursor.y, axis: .horizontal,
            excluding: host.id, in: screens)
        let topSeam = hasNeighbor(
            beyond: frame.minY, direction: .leading, perpendicular: cursor.x, axis: .vertical,
            excluding: host.id, in: screens)
        let bottomSeam = hasNeighbor(
            beyond: frame.maxY, direction: .trailing, perpendicular: cursor.x, axis: .vertical,
            excluding: host.id, in: screens)

        let nearLeft =
            leftSeam
            ? cursor.x <= frame.minX + seamMargin
            : cursor.x <= max(frame.minX, visible.minX) + outerMargin
        let nearRight =
            rightSeam
            ? cursor.x >= frame.maxX - seamMargin
            : cursor.x >= min(frame.maxX, visible.maxX) - outerMargin
        let nearTop =
            topSeam
            ? cursor.y <= frame.minY + seamMargin
            : cursor.y <= max(frame.minY, visible.minY) + outerMargin || cursor.y <= visible.minY
        let nearBottom =
            bottomSeam
            ? cursor.y >= frame.maxY - seamMargin
            : cursor.y >= min(frame.maxY, visible.maxY) - outerMargin || cursor.y >= visible.maxY

        guard nearLeft || nearRight || nearTop || nearBottom else { return nil }

        let metrics = edgeMetrics(in: visible, scale: options.areaScale)
        let inLeftCorner = cursor.x <= visible.minX + metrics.cornerWidth
        let inRightCorner = cursor.x >= visible.maxX - metrics.cornerWidth
        let inTopCorner = cursor.y <= visible.minY + metrics.cornerHeight
        let inBottomCorner = cursor.y >= visible.maxY - metrics.cornerHeight

        let resolved: WindowActivationZone?
        if (nearTop && inLeftCorner) || (nearLeft && inTopCorner) {
            resolved = .topLeft
        } else if (nearTop && inRightCorner) || (nearRight && inTopCorner) {
            resolved = .topRight
        } else if (nearBottom && inLeftCorner) || (nearLeft && inBottomCorner) {
            resolved = .bottomLeft
        } else if (nearBottom && inRightCorner) || (nearRight && inBottomCorner) {
            resolved = .bottomRight
        } else if nearTop {
            resolved = .top
        } else if nearLeft {
            resolved = sideZone(y: cursor.y, leading: true, visible: visible, metrics: metrics)
        } else if nearRight {
            resolved = sideZone(y: cursor.y, leading: false, visible: visible, metrics: metrics)
        } else if nearBottom {
            resolved = bottomThirdZone(x: cursor.x, visible: visible, metrics: metrics)
        } else {
            resolved = nil
        }

        guard let resolved, !options.disabledZones.contains(resolved) else { return nil }
        return resolved
    }

    /// Screen-edge indicator pills in AX space for enabled activation zones across `screens`.
    static func activationPills(
        in screens: [WindowPlacementEngine.Screen], options: Options = Options()
    ) -> [Pill] {
        var result: [Pill] = []
        for screen in screens where screen.visibleFrame.width > 0 && screen.visibleFrame.height > 0 {
            let visible = screen.visibleFrame
            let metrics = edgeMetrics(in: visible, scale: options.areaScale)
            for zone in WindowActivationZone.allCases where !options.disabledZones.contains(zone) {
                let rect = pillFrame(for: zone, in: visible, metrics: metrics)
                if rect.width >= 4, rect.height >= 4 {
                    result.append(Pill(zone: zone, screenID: screen.id, frame: rect))
                }
            }
        }
        return result
    }

    /// Display containing `cursor`; includes `maxX`/`maxY` so a bottom-right screen edge resolves.
    static func screen(
        under cursor: CGPoint, in screens: [WindowPlacementEngine.Screen]
    ) -> WindowPlacementEngine.Screen? {
        if let exact = screens.first(where: { $0.frame.contains(cursor) }) { return exact }
        return screens.first {
            cursor.x >= $0.frame.minX - 1 && cursor.x <= $0.frame.maxX + 1
                && cursor.y >= $0.frame.minY - 1 && cursor.y <= $0.frame.maxY + 1
        }
    }

    // MARK: - Unsnap restore

    /// Returns whether `currentFrame` shows a real window move rather than an edge resize.
    static func isMovingWithoutResize(
        from initialFrame: CGRect, to currentFrame: CGRect
    ) -> Bool {
        let tolerance = WindowActionMemory<Int>.tolerance
        let sameSize =
            abs(currentFrame.width - initialFrame.width) <= tolerance
            && abs(currentFrame.height - initialFrame.height) <= tolerance
        let moved =
            hypot(currentFrame.minX - initialFrame.minX, currentFrame.minY - initialFrame.minY)
            >= unsnapDragThreshold
        return sameSize && moved
    }

    /// Restores `restoreSize` proportionally under `currentCursor` when dragging a tiled window.
    static func unsnapFrame(
        initialWindowFrame: CGRect, initialCursor: CGPoint, currentWindowFrame: CGRect,
        currentCursor: CGPoint, restoreSize: CGSize, in screens: [WindowPlacementEngine.Screen]
    ) -> CGRect? {
        guard isMovingWithoutResize(from: initialWindowFrame, to: currentWindowFrame) else {
            return nil
        }
        let tolerance = WindowActionMemory<Int>.tolerance
        let sizeDiffers =
            abs(restoreSize.width - initialWindowFrame.width) > tolerance
            || abs(restoreSize.height - initialWindowFrame.height) > tolerance
        guard sizeDiffers, restoreSize.width > 0, restoreSize.height > 0 else { return nil }

        let host =
            screen(under: currentCursor, in: screens)
            ?? WindowPlacementEngine.screen(containing: currentWindowFrame, in: screens)
        let visible = host?.visibleFrame
        let size = CGSize(
            width: visible.map { min(restoreSize.width, $0.width) } ?? restoreSize.width,
            height: visible.map { min(restoreSize.height, $0.height) } ?? restoreSize.height)

        let rawRatio = (initialCursor.x - initialWindowFrame.minX) / max(1, initialWindowFrame.width)
        let anchorX = min(max(rawRatio, 0.12), 0.88)
        let grabY = min(max(initialCursor.y - initialWindowFrame.minY, 4), min(36, size.height / 2))

        var origin = CGPoint(
            x: currentCursor.x - anchorX * size.width, y: currentCursor.y - grabY)
        if let visible {
            origin.y = max(visible.minY, min(origin.y, visible.maxY - min(36, size.height)))
        }
        return WindowPlacementEngine.rounded(CGRect(origin: origin, size: size))
    }

    // MARK: - Helpers

    private struct EdgeMetrics {
        let cornerWidth: CGFloat
        let cornerHeight: CGFloat
        let sideHalfSpan: CGFloat
        let bottomThirdSpan: CGFloat
    }

    private static func edgeMetrics(in visible: CGRect, scale: Int) -> EdgeMetrics {
        let ratio = CGFloat(sanitizedAreaScale(scale)) / 100
        let cornerWidth = min(max(36, visible.width * ratio * 0.24), visible.width / 5)
        let cornerHeight = min(max(36, visible.height * ratio * 0.30), visible.height / 5)
        let verticalInterior = max(0, visible.height - cornerHeight * 2)
        let sideHalfSpan = min(verticalInterior / 3, verticalInterior * ratio * 0.72)
        let horizontalInterior = max(0, visible.width - cornerWidth * 2)
        let bottomThirdSpan = horizontalInterior / 3
        return EdgeMetrics(
            cornerWidth: cornerWidth, cornerHeight: cornerHeight, sideHalfSpan: sideHalfSpan,
            bottomThirdSpan: bottomThirdSpan)
    }

    private static func sideZone(
        y: CGFloat, leading: Bool, visible: CGRect, metrics: EdgeMetrics
    ) -> WindowActivationZone {
        let upperEnd = visible.minY + metrics.cornerHeight + metrics.sideHalfSpan
        let lowerStart = visible.maxY - metrics.cornerHeight - metrics.sideHalfSpan
        if y < upperEnd { return leading ? .leftUpper : .rightUpper }
        if y > lowerStart { return leading ? .leftLower : .rightLower }
        return leading ? .left : .right
    }

    private static func bottomThirdZone(
        x: CGFloat, visible: CGRect, metrics: EdgeMetrics
    ) -> WindowActivationZone {
        let interiorMinX = visible.minX + metrics.cornerWidth
        let interiorWidth = max(1, visible.width - metrics.cornerWidth * 2)
        let fraction = (x - interiorMinX) / interiorWidth
        if fraction < 1.0 / 3.0 { return .bottomFirstThird }
        if fraction < 2.0 / 3.0 { return .bottomCenterThird }
        return .bottomLastThird
    }

    private static func pillFrame(
        for zone: WindowActivationZone, in visible: CGRect, metrics: EdgeMetrics
    ) -> CGRect {
        let inset = pillInset
        let thick = pillThickness
        let gap: CGFloat = 4
        switch zone {
        case .topLeft:
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: visible.minX + inset, y: visible.minY + inset,
                    width: max(0, metrics.cornerWidth - inset - gap / 2), height: thick))
        case .top:
            let minX = visible.minX + metrics.cornerWidth + gap / 2
            let maxX = visible.maxX - metrics.cornerWidth - gap / 2
            return WindowPlacementEngine.rounded(
                CGRect(x: minX, y: visible.minY + inset, width: max(0, maxX - minX), height: thick))
        case .topRight:
            let minX = visible.maxX - metrics.cornerWidth + gap / 2
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: minX, y: visible.minY + inset,
                    width: max(0, visible.maxX - inset - minX), height: thick))
        case .leftUpper:
            let minY = visible.minY + metrics.cornerHeight + gap / 2
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: visible.minX + inset, y: minY, width: thick,
                    height: max(0, metrics.sideHalfSpan - gap)))
        case .left:
            let minY = visible.minY + metrics.cornerHeight + metrics.sideHalfSpan + gap / 2
            let maxY = visible.maxY - metrics.cornerHeight - metrics.sideHalfSpan - gap / 2
            return WindowPlacementEngine.rounded(
                CGRect(x: visible.minX + inset, y: minY, width: thick, height: max(0, maxY - minY)))
        case .leftLower:
            let maxY = visible.maxY - metrics.cornerHeight - gap / 2
            let height = max(0, metrics.sideHalfSpan - gap)
            return WindowPlacementEngine.rounded(
                CGRect(x: visible.minX + inset, y: maxY - height, width: thick, height: height))
        case .rightUpper:
            let minY = visible.minY + metrics.cornerHeight + gap / 2
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: visible.maxX - inset - thick, y: minY, width: thick,
                    height: max(0, metrics.sideHalfSpan - gap)))
        case .right:
            let minY = visible.minY + metrics.cornerHeight + metrics.sideHalfSpan + gap / 2
            let maxY = visible.maxY - metrics.cornerHeight - metrics.sideHalfSpan - gap / 2
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: visible.maxX - inset - thick, y: minY, width: thick,
                    height: max(0, maxY - minY)))
        case .rightLower:
            let maxY = visible.maxY - metrics.cornerHeight - gap / 2
            let height = max(0, metrics.sideHalfSpan - gap)
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: visible.maxX - inset - thick, y: maxY - height, width: thick, height: height)
            )
        case .bottomLeft:
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: visible.minX + inset, y: visible.maxY - inset - thick,
                    width: max(0, metrics.cornerWidth - inset - gap / 2), height: thick))
        case .bottomFirstThird:
            let start = visible.minX + metrics.cornerWidth + gap / 2
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: start, y: visible.maxY - inset - thick,
                    width: max(0, metrics.bottomThirdSpan - gap), height: thick))
        case .bottomCenterThird:
            let start = visible.minX + metrics.cornerWidth + metrics.bottomThirdSpan + gap / 2
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: start, y: visible.maxY - inset - thick,
                    width: max(0, metrics.bottomThirdSpan - gap), height: thick))
        case .bottomLastThird:
            let start = visible.minX + metrics.cornerWidth + metrics.bottomThirdSpan * 2 + gap / 2
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: start, y: visible.maxY - inset - thick,
                    width: max(0, metrics.bottomThirdSpan - gap), height: thick))
        case .bottomRight:
            let minX = visible.maxX - metrics.cornerWidth + gap / 2
            return WindowPlacementEngine.rounded(
                CGRect(
                    x: minX, y: visible.maxY - inset - thick,
                    width: max(0, visible.maxX - inset - minX), height: thick))
        }
    }

    private enum Axis { case horizontal, vertical }
    private enum Direction { case leading, trailing }

    private static func hasNeighbor(
        beyond boundary: CGFloat, direction: Direction, perpendicular: CGFloat, axis: Axis,
        excluding screenID: Int, in screens: [WindowPlacementEngine.Screen]
    ) -> Bool {
        screens.contains { other in
            guard other.id != screenID else { return false }
            switch (axis, direction) {
            case (.horizontal, .leading):
                return abs(other.frame.maxX - boundary) <= seamSlack
                    && perpendicular >= other.frame.minY && perpendicular <= other.frame.maxY
            case (.horizontal, .trailing):
                return abs(other.frame.minX - boundary) <= seamSlack
                    && perpendicular >= other.frame.minY && perpendicular <= other.frame.maxY
            case (.vertical, .leading):
                return abs(other.frame.maxY - boundary) <= seamSlack
                    && perpendicular >= other.frame.minX && perpendicular <= other.frame.maxX
            case (.vertical, .trailing):
                return abs(other.frame.minY - boundary) <= seamSlack
                    && perpendicular >= other.frame.minX && perpendicular <= other.frame.maxX
            }
        }
    }
}
