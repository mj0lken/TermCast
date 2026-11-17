import CoreGraphics
import Observation
import SwiftUI

/// Observable display state driving `NotchHUDView` without recreating its hosting hierarchy.
@MainActor
@Observable
final class NotchHUDState {
    var metric: NotchHUDMetric = .volume(level: 0.5, muted: false)
    var layout: NotchHUDGeometry.Layout = NotchHUDGeometry.resolve(
        screen: NotchHUDGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 38,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil))
    var isExpanded = false
    var style = NotchHUDStyle()
}
