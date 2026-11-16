import CoreGraphics
import Foundation

/// Pure layout and rubber-band geometry for notched inline wings and non-notched pill fallback.
enum NotchHUDGeometry {
    struct ScreenMetrics: Sendable, Equatable {
        let frame: CGRect
        let safeAreaTop: CGFloat
        let auxiliaryTopLeft: CGRect?
        let auxiliaryTopRight: CGRect?
    }

    enum Mode: Sendable, Equatable {
        case notched(
            notchOriginX: CGFloat,
            notchWidth: CGFloat,
            notchHeight: CGFloat,
            leftWingWidth: CGFloat,
            rightWingWidth: CGFloat,
            earRadius: CGFloat,
            innerCornerRadius: CGFloat)
        case floatingPill(baseWidth: CGFloat, cornerRadius: CGFloat)
    }

    struct Layout: Sendable, Equatable {
        let panelFrame: CGRect
        let mode: Mode
        let trackWidth: CGFloat
        let wingStretch: CGFloat
        let trackCompression: CGFloat

        var isNotched: Bool {
            if case .notched = mode { return true }
            return false
        }
    }

    static let earRadius: CGFloat = 6
    static let innerCornerRadius: CGFloat = 14
    static let floatingTopOffset: CGFloat = 8
    static let floatingPillHeight: CGFloat = 36
    static let floatingPillWidth: CGFloat = 224
    static let floatingToastPillWidth: CGFloat = 268
    static let defaultNotchWidth: CGFloat = 212
    static let menuBarSafetyMargin: CGFloat = 24
    static let idealLeftWingWidth: CGFloat = 46
    static let idealRightWingWidth: CGFloat = 142
    static let idealToastRightWingWidth: CGFloat = 178
    static let minimumLeftWingWidth: CGFloat = 34
    static let minimumRightWingWidth: CGFloat = 88
    static let minimumTrackWidth: CGFloat = 28
    static let idealTrackWidth: CGFloat = 72
    static let maxWingOvershootStretch: CGFloat = 4
    static let maxTrackOvershootCompression: CGFloat = 2

    static func resolve(
        screen: ScreenMetrics,
        isToast: Bool = false,
        overshoot: Double = 0
    ) -> Layout {
        let clampedOvershoot = CGFloat(min(max(abs(overshoot), 0), 1))
        let wingStretch = maxWingOvershootStretch * clampedOvershoot
        let trackCompression = maxTrackOvershootCompression * clampedOvershoot

        guard screen.safeAreaTop > 0 else {
            return resolveFloatingPill(
                screenFrame: screen.frame,
                isToast: isToast,
                wingStretch: wingStretch,
                trackCompression: trackCompression)
        }

        let notchHeight = screen.safeAreaTop
        let (notchMinX, notchMaxX, leftWidth, rightWidth) = notchHorizontalMetrics(for: screen)
        let notchWidth = max(notchMaxX - notchMinX, 1)

        let rawAvailableLeft = max(leftWidth - menuBarSafetyMargin, 0)
        let rawAvailableRight = max(rightWidth - menuBarSafetyMargin, 0)

        let targetRight = isToast ? idealToastRightWingWidth : idealRightWingWidth
        guard rawAvailableLeft >= minimumLeftWingWidth,
            rawAvailableRight >= minimumRightWingWidth
        else {
            return resolveFloatingPill(
                screenFrame: screen.frame,
                isToast: isToast,
                wingStretch: wingStretch,
                trackCompression: trackCompression)
        }

        let maxLeftBudget = max(rawAvailableLeft - maxWingOvershootStretch, minimumLeftWingWidth)
        let maxRightBudget = max(rawAvailableRight - maxWingOvershootStretch, minimumRightWingWidth)

        let leftWing = min(idealLeftWingWidth, maxLeftBudget)
        let rightWing = min(targetRight, maxRightBudget)

        let rightShrink = max(idealRightWingWidth - rightWing, 0)
        let baseTrack = max(idealTrackWidth - rightShrink, minimumTrackWidth)
        let trackWidth = max(baseTrack - trackCompression, minimumTrackWidth)

        // Reserve overshoot headroom on both sides so spring expansion never clips at the panel edge.
        let canvasPadding = maxWingOvershootStretch + earRadius
        let panelMinX = notchMinX - leftWing - canvasPadding
        let panelMaxX = notchMaxX + rightWing + canvasPadding
        let panelFrame = CGRect(
            x: panelMinX.rounded(.down),
            y: screen.frame.maxY - notchHeight,
            width: (panelMaxX - panelMinX).rounded(.up),
            height: notchHeight)

        return Layout(
            panelFrame: panelFrame,
            mode: .notched(
                notchOriginX: notchMinX - panelFrame.minX,
                notchWidth: notchWidth,
                notchHeight: notchHeight,
                leftWingWidth: leftWing + wingStretch,
                rightWingWidth: rightWing + wingStretch,
                earRadius: earRadius,
                innerCornerRadius: innerCornerRadius),
            trackWidth: trackWidth,
            wingStretch: wingStretch,
            trackCompression: trackCompression)
    }

    private static func notchHorizontalMetrics(
        for screen: ScreenMetrics
    ) -> (minX: CGFloat, maxX: CGFloat, leftWidth: CGFloat, rightWidth: CGFloat) {
        if let left = screen.auxiliaryTopLeft, let right = screen.auxiliaryTopRight,
            right.minX > left.maxX
        {
            return (left.maxX, right.minX, left.width, right.width)
        }
        let minX = screen.frame.midX - defaultNotchWidth / 2
        let maxX = minX + defaultNotchWidth
        return (minX, maxX, minX - screen.frame.minX, screen.frame.maxX - maxX)
    }

    private static func resolveFloatingPill(
        screenFrame: CGRect,
        isToast: Bool,
        wingStretch: CGFloat,
        trackCompression: CGFloat
    ) -> Layout {
        let baseWidth = isToast ? floatingToastPillWidth : floatingPillWidth
        let canvasWidth = baseWidth + maxWingOvershootStretch * 2
        let panelFrame = CGRect(
            x: (screenFrame.midX - canvasWidth / 2).rounded(),
            y: (screenFrame.maxY - floatingTopOffset - floatingPillHeight).rounded(),
            width: canvasWidth,
            height: floatingPillHeight)
        return Layout(
            panelFrame: panelFrame,
            mode: .floatingPill(
                baseWidth: baseWidth + wingStretch * 2,
                cornerRadius: floatingPillHeight / 2),
            trackWidth: max(idealTrackWidth - trackCompression, minimumTrackWidth),
            wingStretch: wingStretch,
            trackCompression: trackCompression)
    }
}
