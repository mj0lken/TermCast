import AppKit
import SwiftUI

/// Owns the closed notch's persistent wings and decides which ongoing activity they show.
@MainActor
final class NotchLiveActivityController {
    private static let collapseSettleDuration: TimeInterval = 0.28

    var terminalSessions: (() -> [NotchTerminalSession])?
    var meetingEvents: (() -> [MeetingEvent])?
    var meetingLeadMinutes: (() -> Int)?

    private let state = NotchLiveActivityState()
    private let nowPlaying: NowPlayingService
    private let timer: NotchTimer
    private let capture: MediaCaptureMonitor

    private var panel: NotchHUDPanel?
    private var isRunning = false
    private var isDictating = false
    private var meeting: MeetingEvent?
    private var meetingTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var observers: [NotificationToken] = []
    private var trackingGeneration = 0

    init(nowPlaying: NowPlayingService, timer: NotchTimer, capture: MediaCaptureMonitor) {
        self.nowPlaying = nowPlaying
        self.timer = timer
        self.capture = capture
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NotificationCenter.default
        observers = [
            observe(center, NSApplication.didChangeScreenParametersNotification) { $0.refresh() },
            // The events were read for a few days around today, so a new day needs a new read.
            observe(center, .NSCalendarDayChanged) { $0.refreshMeeting() }
        ]
        refreshMeeting()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observers = []
        meetingTask?.cancel()
        meetingTask = nil
        collapseTask?.cancel()
        collapseTask = nil
        meeting = nil
        state.isExpanded = false
        panel?.orderOut(nil)
    }

    func calendarDidUpdate() {
        guard isRunning else { return }
        refreshMeeting()
    }

    func setDictating(_ dictating: Bool) {
        guard dictating != isDictating else { return }
        isDictating = dictating
        if !dictating {
            state.dictationLevels = [Float](repeating: 0, count: NotchLiveActivityState.waveformBarCount)
        }
        if isRunning { refresh() }
    }

    func setDictationLevels(_ levels: [Float]) {
        guard isRunning, isDictating, !levels.isEmpty else { return }
        let barCount = NotchLiveActivityState.waveformBarCount
        state.dictationLevels = (0..<barCount).map { bar in
            let lower = min(bar * levels.count / barCount, levels.count - 1)
            let upper = max((bar + 1) * levels.count / barCount, lower + 1)
            return levels[lower..<min(upper, levels.count)].max() ?? 0
        }
    }

    // MARK: - Resolution

    /// Re-armed on every change, so each observable source is read once per change and never polled.
    private func refresh() {
        guard isRunning else { return }
        trackingGeneration &+= 1
        let generation = trackingGeneration
        let presentation = withObservationTracking {
            inputs().presentation(at: Date())
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                // A direct refresh leaves its predecessor's tracking armed; only the newest may act.
                guard let self, self.trackingGeneration == generation else { return }
                self.refresh()
            }
        }
        show(presentation)
    }

    private func inputs() -> NotchLiveInputs {
        NotchLiveInputs(
            isDictating: isDictating,
            meeting: meeting,
            timerEnd: timer.end,
            runningTerminalCount: NotchTerminalSession.runningCount(in: terminalSessions?() ?? []),
            isPlaying: nowPlaying.snapshot?.isPlaying == true,
            capture: capture.use)
    }

    private func refreshMeeting() {
        meetingTask?.cancel()
        meetingTask = nil
        guard isRunning else { return }
        let now = Date()
        let events = meetingEvents?() ?? []
        let countdown = NotchMeetingCountdown(leadMinutes: meetingLeadMinutes?() ?? 10)
        meeting = countdown.current(from: events, now: now)
        if let next = countdown.nextChange(from: events, now: now) {
            meetingTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0) + 0.5))
                guard !Task.isCancelled else { return }
                self?.refreshMeeting()
            }
        }
        refresh()
    }

    // MARK: - Presentation

    private func show(_ presentation: NotchLivePresentation) {
        guard !presentation.isEmpty, let layout = resolveLayout(for: presentation) else {
            retract()
            return
        }
        collapseTask?.cancel()
        collapseTask = nil

        let panel = ensurePanel()
        if panel.frame != layout.panelFrame {
            panel.setFrame(layout.panelFrame, display: true)
        }
        if state.presentation != presentation { state.presentation = presentation }
        if state.layout != layout { state.layout = layout }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        guard !state.isExpanded else { return }
        withAnimation(Theme.NotchMotion.wing) {
            state.isExpanded = true
        }
    }

    private func retract() {
        guard let panel, panel.isVisible, state.isExpanded else { return }
        withAnimation(Theme.NotchMotion.wing) {
            state.isExpanded = false
        }
        let settle = Motion.duration(Self.collapseSettleDuration)
        guard settle > 0 else {
            panel.orderOut(nil)
            return
        }
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(settle))
            guard !Task.isCancelled, let self, !self.state.isExpanded else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func resolveLayout(for presentation: NotchLivePresentation) -> NotchHUDGeometry.Layout? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else { return nil }
        return NotchHUDGeometry.resolveLive(
            screen: NotchHUDGeometry.ScreenMetrics(
                frame: screen.frame,
                safeAreaTop: screen.safeAreaInsets.top,
                auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                auxiliaryTopRight: screen.auxiliaryTopRightArea),
            leftWing: presentation.leftWingWidth,
            rightWing: presentation.rightWingWidth)
    }

    private func ensurePanel() -> NotchHUDPanel {
        if let panel { return panel }
        let created = NotchHUDPanel(level: .notchLiveActivity)
        let view = NotchLiveActivityView(state: state, nowPlaying: nowPlaying)
        let host = NSHostingView(rootView: view.motionScope())
        host.sizingOptions = []
        created.contentView = host
        panel = created
        return created
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ handler: @escaping @Sendable @MainActor (NotchLiveActivityController) -> Void
    ) -> NotificationToken {
        NotificationToken(
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    handler(self)
                }
            },
            center: center)
    }
}
