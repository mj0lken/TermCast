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

    struct OpenTrayLayout: Sendable, Equatable {
        let panelFrame: CGRect
        let trayWidth: CGFloat
        let trayHeight: CGFloat
        let headerHeight: CGFloat
        let notchOriginX: CGFloat
        let notchWidth: CGFloat
        let earRadius: CGFloat
        let cornerRadius: CGFloat
        let isNotched: Bool
    }

    static let earRadius: CGFloat = 6
    static let openEarRadius: CGFloat = 10
    static let innerCornerRadius: CGFloat = 14
    static let openCornerRadius: CGFloat = 22
    static let openTrayIdealWidth: CGFloat = 604
    static let openTrayBodyHeight: CGFloat = 166
    static let nonNotchedSensorWidth: CGFloat = 160
    static let nonNotchedSensorHeight: CGFloat = 8
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
    static let liveMaxLeftWingWidth: CGFloat = 60
    static let liveMaxRightWingWidth: CGFloat = 66

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

    /// Nil without a notch: a persistent pill floating over a plain menu bar would cover content.
    static func resolveLive(
        screen: ScreenMetrics,
        leftWing: CGFloat,
        rightWing: CGFloat
    ) -> Layout? {
        guard screen.safeAreaTop > 0 else { return nil }
        let notchHeight = screen.safeAreaTop
        let (notchMinX, notchMaxX, leftWidth, rightWidth) = notchHorizontalMetrics(for: screen)
        let leftBudget = min(liveMaxLeftWingWidth, max(leftWidth - menuBarSafetyMargin, 0))
        let rightBudget = min(liveMaxRightWingWidth, max(rightWidth - menuBarSafetyMargin, 0))

        // Sized for the widest activity once, so swapping activities never resizes the window.
        let panelMinX = notchMinX - leftBudget - earRadius
        let panelMaxX = notchMaxX + rightBudget + earRadius
        let panelFrame = CGRect(
            x: panelMinX.rounded(.down),
            y: screen.frame.maxY - notchHeight,
            width: (panelMaxX - panelMinX).rounded(.up),
            height: notchHeight)

        return Layout(
            panelFrame: panelFrame,
            mode: .notched(
                notchOriginX: notchMinX - panelFrame.minX,
                notchWidth: max(notchMaxX - notchMinX, 1),
                notchHeight: notchHeight,
                leftWingWidth: min(max(leftWing, 0), leftBudget),
                rightWingWidth: min(max(rightWing, 0), rightBudget),
                earRadius: earRadius,
                innerCornerRadius: innerCornerRadius),
            trackWidth: 0,
            wingStretch: 0,
            trackCompression: 0)
    }

    static func sensorFrame(for screen: ScreenMetrics) -> CGRect {
        if screen.safeAreaTop > 0 {
            let (notchMinX, notchMaxX, _, _) = notchHorizontalMetrics(for: screen)
            let width = max(notchMaxX - notchMinX, 1)
            return CGRect(
                x: notchMinX.rounded(),
                y: screen.frame.maxY - screen.safeAreaTop,
                width: width.rounded(),
                height: screen.safeAreaTop)
        }
        return CGRect(
            x: (screen.frame.midX - nonNotchedSensorWidth / 2).rounded(),
            y: screen.frame.maxY - nonNotchedSensorHeight,
            width: nonNotchedSensorWidth,
            height: nonNotchedSensorHeight)
    }

    static func resolveOpenTray(screen: ScreenMetrics) -> OpenTrayLayout {
        let isNotched = screen.safeAreaTop > 0
        let headerHeight = isNotched ? screen.safeAreaTop : floatingPillHeight
        let trayWidth = min(openTrayIdealWidth, max(screen.frame.width - 48, 360))
        let trayHeight = headerHeight + openTrayBodyHeight
        let ear = isNotched ? openEarRadius : 0

        if isNotched {
            let (notchMinX, notchMaxX, _, _) = notchHorizontalMetrics(for: screen)
            let notchCenterX = (notchMinX + notchMaxX) / 2
            let notchWidth = max(notchMaxX - notchMinX, 1)
            let canvasWidth = trayWidth + ear * 2
            let minX = max(
                screen.frame.minX + 8,
                min(notchCenterX - canvasWidth / 2, screen.frame.maxX - canvasWidth - 8))
            let panelFrame = CGRect(
                x: minX.rounded(),
                y: (screen.frame.maxY - trayHeight).rounded(),
                width: canvasWidth.rounded(),
                height: trayHeight.rounded())
            return OpenTrayLayout(
                panelFrame: panelFrame,
                trayWidth: trayWidth,
                trayHeight: trayHeight,
                headerHeight: headerHeight,
                notchOriginX: notchMinX - panelFrame.minX,
                notchWidth: notchWidth,
                earRadius: ear,
                cornerRadius: openCornerRadius,
                isNotched: true)
        }

        let panelFrame = CGRect(
            x: (screen.frame.midX - trayWidth / 2).rounded(),
            y: (screen.frame.maxY - floatingTopOffset - trayHeight).rounded(),
            width: trayWidth.rounded(),
            height: trayHeight.rounded())
        return OpenTrayLayout(
            panelFrame: panelFrame,
            trayWidth: trayWidth,
            trayHeight: trayHeight,
            headerHeight: headerHeight,
            notchOriginX: trayWidth / 2,
            notchWidth: 0,
            earRadius: 0,
            cornerRadius: openCornerRadius,
            isNotched: false)
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
