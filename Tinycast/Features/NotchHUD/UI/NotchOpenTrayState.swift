import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// Observable state driving the expanded Notch tray (`Home` media + calendar and `Shelf` dropzone).
@MainActor
@Observable
final class NotchOpenTrayState {
    var tab: NotchTab = .home
    var isExpanded = false
    var layout = NotchHUDGeometry.resolveOpenTray(
        screen: NotchHUDGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 38,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil))
    var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    var weekEvents: [MeetingEvent] = []
    var isCalendarEnabled = false
    var hasCalendarAccess = false
    var inlineHUDMetric: NotchHUDMetric?
    var showsMedia = true
    var showsCalendar = true
    var showsBattery = true
    var showsClipboard = true
    var hidesAllDayEvents = false
    var style = NotchHUDStyle()
}
