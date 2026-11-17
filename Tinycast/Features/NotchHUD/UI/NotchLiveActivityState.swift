import CoreGraphics
import Observation

/// Observable state driving `NotchLiveActivityView` without recreating its hosting hierarchy.
@MainActor
@Observable
final class NotchLiveActivityState {
    static let waveformBarCount = 5

    var presentation = NotchLivePresentation(activity: nil, terminalCount: 0, capture: NotchCaptureUse())
    var layout: NotchHUDGeometry.Layout = NotchHUDGeometry.resolve(
        screen: NotchHUDGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 38,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil))
    var isExpanded = false
    var dictationLevels = [Float](repeating: 0, count: waveformBarCount)
}
