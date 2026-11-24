import AppKit
import CoreGraphics

/// Owns the Notch HUD, interactive Open-Notch tray, Now Playing, Shelf and Battery lifecycles.
@MainActor
@Observable
final class NotchHUDManager: HealthCheckable {
    enum Status: String, Codable, Sendable {
        case off
        case active
        case needsAccessibility
        case paused
    }

    private enum PauseReason {
        case asleep
        case screenLocked
        case sessionInactive
    }

    private(set) var status: Status = .off

    @ObservationIgnored weak var healthTicker: HealthTicker?
    @ObservationIgnored var refreshCalendarState: (() -> (enabled: Bool, hasAccess: Bool, events: [MeetingEvent]))?
    @ObservationIgnored var onOpenClipboard: (() -> Void)?
    @ObservationIgnored var onOpenNotes: (() -> Void)?
    @ObservationIgnored var onOpenCamera: (() -> Void)?
    @ObservationIgnored var onRunWindowCommand: ((WindowCommand.ID) -> Void)?
    @ObservationIgnored var terminalSessions: (() -> [NotchTerminalSession])?
    @ObservationIgnored var onOpenTerminalSession: ((NotchTerminalSession.ID) -> Void)?
    @ObservationIgnored var onOpenTerminal: (() -> Void)?
    @ObservationIgnored var meetingLeadMinutes: (() -> Int)?
    @ObservationIgnored var isOwnCameraLive: (() -> Bool)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    @ObservationIgnored var onEnableCalendar: (() -> Void)?
    @ObservationIgnored var onJoinMeeting: ((MeetingEvent) -> Void)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let displayBrightness: DisplayBrightnessService
    @ObservationIgnored private let audioVolume = AudioVolumeService()
    @ObservationIgnored private let keyboardBacklight = KeyboardBacklightService()
    @ObservationIgnored private let nowPlaying = NowPlayingService()
    @ObservationIgnored private let shelfStore = NotchShelfStore()
    @ObservationIgnored private let battery = BatteryStatusService()
    @ObservationIgnored private let timer = NotchTimer()
    @ObservationIgnored private let capture = MediaCaptureMonitor()
    @ObservationIgnored private let inputSource = InputSourceMonitor()
    @ObservationIgnored private lazy var liveActivity = makeLiveActivityController()
    @ObservationIgnored private var hasLiveActivity = false
    @ObservationIgnored private var isDictating = false
    @ObservationIgnored private let tap = MediaKeyInterceptorTap()
    @ObservationIgnored private let controller = NotchHUDController()
    @ObservationIgnored private lazy var trayController = makeTrayController()
    @ObservationIgnored private var hasTrayController = false
    @ObservationIgnored private var shelfLoaded = false
    @ObservationIgnored private var observers: [NotificationToken] = []
    @ObservationIgnored private var darwinObservers: [DarwinNotificationToken] = []
    @ObservationIgnored private var permissionRetry: Task<Void, Never>?
    @ObservationIgnored private var pauseReasons: Set<PauseReason> = []
    @ObservationIgnored private var previewStepIndex = 0

    init(
        settings: AppSettings,
        displayBrightness: DisplayBrightnessService,
        isSuppressingExternalAudioHUD: @escaping () -> Bool = { false }
    ) {
        self.settings = settings
        self.displayBrightness = displayBrightness
        audioVolume.isSuppressingExternalNotifications = isSuppressingExternalAudioHUD
    }

    var isEnabled: Bool {
        settings.notchHUDEnabled && pauseReasons.isEmpty
    }

    func start() {
        tap.onMediaKeyDown = { [weak self] event in
            self?.handlePhysicalMediaKey(event)
        }
        audioVolume.onBluetoothOutputConnected = { [weak self] state in
            self?.presentBluetoothConnected(state)
        }
        audioVolume.onExternalVolumeChange = { [weak self] state in
            self?.presentExternalVolumeChange(state)
        }
        battery.onPowerSourceChanged = { [weak self] status in
            self?.presentBatteryChange(status)
        }
        displayBrightness.onBrightnessStepped = { [weak self] outcome in
            guard let self, self.isEnabled else { return }
            self.presentHUD(
                metric: .screenBrightness(level: outcome.level),
                overshoot: outcome.overshoot,
                preferredDisplayID: outcome.displayID)
        }
        nowPlaying.onTrackChanged = { [weak self] in self?.announceTrack($0) }
        timer.onFinished = { [weak self] in self?.announceTimerFinished() }
        capture.onMicrophoneStarted = { [weak self] in self?.announceMicrophone(appName: $0) }
        capture.isOwnCameraLive = { [weak self] in self?.isOwnCameraLive?() ?? false }
        capture.onCameraStarted = { [weak self] in
            self?.announce(symbol: "video.fill", text: String(localized: "Camera in use"))
        }
        inputSource.onChange = { [weak self] in self?.announce(symbol: "keyboard", text: $0) }
        observeSettings()
        observeSystem()
        apply()
    }

    func prepareForTermination() {
        stopAll()
    }

    func healthCheck() {
        apply()
    }

    func calendarDidUpdate() {
        if hasLiveActivity { liveActivity.calendarDidUpdate() }
        guard hasTrayController, trayController.isOpen else { return }
        trayController.syncCalendarData()
    }

    /// Kept here too: a recording can start before the live wings exist, or outlast a pause.
    func dictationDidChange(isListening: Bool) {
        isDictating = isListening
        guard hasLiveActivity else { return }
        liveActivity.setDictating(isListening)
    }

    func dictationLevelsDidChange(_ levels: [Float]) {
        guard hasLiveActivity else { return }
        liveActivity.setDictationLevels(levels)
    }

    // MARK: - Direct Routing (Hyper Scroll, System Actions & Tray Preview)

    func isBluetoothOutput() -> Bool {
        audioVolume.isBluetoothOutput()
    }

    func resetBacklightGesture() {
        keyboardBacklight.resetGesture()
    }

    func handleMediaKeyFromScroll(_ key: MediaKeyPoster.Key, fine: Bool) -> Bool {
        guard isEnabled else { return false }
        switch key {
        case .soundUp:
            stepVolume(up: true, fine: fine)
            return true
        case .soundDown:
            stepVolume(up: false, fine: fine)
            return true
        case .mute:
            toggleMute()
            return true
        case .illuminationUp:
            stepKeyboardBacklight(up: true, fine: fine)
            return true
        case .illuminationDown:
            stepKeyboardBacklight(up: false, fine: fine)
            return true
        case .playPause, .nextTrack, .previousTrack:
            return false
        }
    }

    func stepVolume(up: Bool, fine: Bool = false) {
        guard let outcome = audioVolume.step(up: up, fine: fine) else { return }
        presentHUD(
            metric: .volume(level: outcome.state.level, muted: outcome.state.isMuted),
            overshoot: outcome.overshoot)
    }

    func toggleMute() {
        guard let state = audioVolume.toggleMute() else { return }
        presentHUD(metric: .volume(level: state.level, muted: state.isMuted))
    }

    func presentVolumeState(level: Double, muted: Bool) {
        presentHUD(metric: .volume(level: level, muted: muted))
    }

    func stepKeyboardBacklight(up: Bool, fine: Bool = false) {
        guard let outcome = keyboardBacklight.step(up: up, fine: fine) else { return }
        presentHUD(
            metric: .keyboardBacklight(level: outcome.level),
            overshoot: outcome.overshoot)
    }

    func showPreview() {
        let samples: [NotchHUDMetric] = [
            .volume(level: audioVolume.currentState()?.level ?? 0.65, muted: false),
            .screenBrightness(level: 0.75),
            .keyboardBacklight(level: 0.5)
        ]
        let metric = samples[previewStepIndex % samples.count]
        previewStepIndex += 1
        presentHUD(metric: metric)
    }

    func openTrayPreview(tab: NotchTab? = nil) {
        ensureShelfServicesRunning()
        trayController.open(preferredTab: tab)
    }

    // MARK: - Physical Media Keys & Notifications

    private func presentHUD(
        metric: NotchHUDMetric,
        overshoot: Double = 0,
        preferredDisplayID: CGDirectDisplayID? = nil
    ) {
        if hasTrayController, trayController.isOpen {
            trayController.showInlineHUD(metric: metric)
            return
        }
        controller.present(
            metric: metric,
            overshoot: overshoot,
            preferredDisplayID: preferredDisplayID)
    }

    private func handlePhysicalMediaKey(_ event: MediaKeyEvent) {
        guard isEnabled else { return }
        switch event.key {
        case .soundUp:
            stepVolume(up: true, fine: event.isFineStep)
        case .soundDown:
            stepVolume(up: false, fine: event.isFineStep)
        case .mute:
            toggleMute()
        case .brightnessUp:
            let step = event.isFineStep ? NotchHUDMetric.fineStep : NotchHUDMetric.coarseStep
            displayBrightness.stepPreferredDisplay(
                preferred: NSScreen.underCursor?.displayID,
                delta: step)
        case .brightnessDown:
            let step = event.isFineStep ? NotchHUDMetric.fineStep : NotchHUDMetric.coarseStep
            displayBrightness.stepPreferredDisplay(
                preferred: NSScreen.underCursor?.displayID,
                delta: -step)
        case .illuminationUp:
            stepKeyboardBacklight(up: true, fine: event.isFineStep)
        case .illuminationDown:
            stepKeyboardBacklight(up: false, fine: event.isFineStep)
        }
    }

    private func presentBluetoothConnected(_ state: AudioVolumeService.State) {
        guard isEnabled else { return }
        let symbol = NotchHUDMetric.audioDeviceSymbol(for: state.deviceName)
        presentHUD(
            metric: .audioDeviceConnected(
                name: state.deviceName,
                symbol: symbol,
                level: state.level,
                muted: state.isMuted))
    }

    private func presentExternalVolumeChange(_ state: AudioVolumeService.State) {
        guard isEnabled else { return }
        presentHUD(metric: .volume(level: state.level, muted: state.isMuted))
    }

    private func presentBatteryChange(_ status: BatteryStatusService.Status) {
        guard pauseReasons.isEmpty,
            settings.notchBatteryNotifications,
            settings.notchHUDEnabled || settings.notchShelfEnabled
        else { return }
        presentHUD(
            metric: .battery(
                percentage: status.percentage,
                isPluggedIn: status.isPluggedIn))
    }

    // MARK: - Announcements

    private func announce(symbol: String, text: String) {
        guard pauseReasons.isEmpty else { return }
        presentHUD(metric: .notice(symbol: symbol, text: text))
    }

    /// The open tray already names the track, so only the closed notch peeks.
    private func announceTrack(_ snapshot: NowPlayingSnapshot) {
        guard settings.notchShowsLiveActivities, !(hasTrayController && trayController.isOpen) else { return }
        let text = snapshot.artist.isEmpty ? snapshot.title : "\(snapshot.title) — \(snapshot.artist)"
        announce(symbol: "music.note", text: text)
    }

    private func announceTimerFinished() {
        NSSound(named: "Glass")?.play()
        announce(symbol: "timer", text: String(localized: "Timer finished"))
    }

    private func announceMicrophone(appName: String?) {
        let text =
            appName.map { String(localized: "\($0) is using the microphone") }
            ?? String(localized: "Microphone in use")
        announce(symbol: "mic.fill", text: text)
    }

    // MARK: - Lifecycle Convergence

    private func apply() {
        let hudRequested = settings.notchHUDEnabled
        let shelfRequested = settings.notchShelfEnabled

        guard hudRequested || shelfRequested else {
            stopAll()
            return
        }

        guard pauseReasons.isEmpty else {
            pauseActiveSubsystems()
            return
        }

        if shelfRequested {
            ensureShelfServicesRunning()
            trayController.startSensor()
        } else {
            if hasTrayController { trayController.stopAll() }
            nowPlaying.stop()
            timer.cancel()
        }

        if shelfRequested, settings.notchShowsLiveActivities {
            capture.start()
            liveActivity.start()
        } else {
            stopLiveActivity()
        }

        if hudRequested, settings.notchInputSourceNotifications {
            inputSource.start()
        } else {
            inputSource.stop()
        }

        if shelfRequested || (hudRequested && settings.notchBatteryNotifications) {
            battery.start()
        } else {
            battery.stop()
        }

        guard hudRequested else {
            tap.tearDown()
            audioVolume.stop()
            keyboardBacklight.resetGesture()
            displayBrightness.showsSystemOSD = true
            controller.dismissImmediately()
            healthTicker?.unsubscribe(self)
            if status != .off { status = .off }
            return
        }

        controller.style = NotchHUDStyle(
            showsPercentage: settings.notchShowsPercentage,
            tintsAccent: settings.notchTintsAccent)
        displayBrightness.showsSystemOSD = false
        audioVolume.start()

        guard Permissions.isAccessibilityTrusted(), tap.install() else {
            tap.tearDown()
            healthTicker?.subscribe(self)
            if status != .needsAccessibility { status = .needsAccessibility }
            return
        }

        healthTicker?.unsubscribe(self)
        if status != .active { status = .active }
    }

    private func ensureShelfServicesRunning() {
        if !shelfLoaded {
            shelfLoaded = true
            shelfStore.load()
        }
        if settings.notchShowsMedia {
            nowPlaying.start()
        } else {
            nowPlaying.stop()
        }
        battery.start()
    }

    private func stopLiveActivity() {
        capture.stop()
        if hasLiveActivity { liveActivity.stop() }
    }

    private func pauseActiveSubsystems() {
        tap.tearDown()
        audioVolume.stop()
        nowPlaying.stop()
        battery.stop()
        stopLiveActivity()
        inputSource.stop()
        keyboardBacklight.resetGesture()
        displayBrightness.showsSystemOSD = true
        controller.dismissImmediately()
        if hasTrayController { trayController.stopAll() }
        healthTicker?.unsubscribe(self)
        if settings.notchHUDEnabled, status != .paused {
            status = .paused
        }
    }

    private func stopAll() {
        tap.tearDown()
        audioVolume.stop()
        nowPlaying.stop()
        battery.stop()
        stopLiveActivity()
        inputSource.stop()
        timer.cancel()
        keyboardBacklight.resetGesture()
        displayBrightness.showsSystemOSD = true
        controller.dismissImmediately()
        if hasTrayController { trayController.stopAll() }
        healthTicker?.unsubscribe(self)
        if status != .off { status = .off }
    }

    private func makeTrayController() -> NotchTrayController {
        hasTrayController = true
        let created = NotchTrayController(
            settings: settings,
            nowPlaying: nowPlaying,
            shelfStore: shelfStore,
            battery: battery,
            timer: timer)
        created.refreshCalendarState = { [weak self] in
            self?.refreshCalendarState?() ?? (false, false, [])
        }
        created.terminalSessions = { [weak self] in self?.terminalSessions?() ?? [] }
        created.onOpenTerminalSession = { [weak self] id in self?.onOpenTerminalSession?(id) }
        created.onOpenTerminal = { [weak self] in self?.onOpenTerminal?() }
        created.meetingLeadMinutes = { [weak self] in self?.meetingLeadMinutes?() ?? 10 }
        created.onShortcut = { [weak self] in self?.run($0) }
        created.onRunWindowCommand = { [weak self] id in self?.onRunWindowCommand?(id) }
        created.onEnableCalendar = { [weak self] in self?.onEnableCalendar?() }
        created.onJoinMeeting = { [weak self] meeting in self?.onJoinMeeting?(meeting) }
        return created
    }

    private func makeLiveActivityController() -> NotchLiveActivityController {
        hasLiveActivity = true
        let created = NotchLiveActivityController(nowPlaying: nowPlaying, timer: timer, capture: capture)
        created.terminalSessions = { [weak self] in self?.terminalSessions?() ?? [] }
        created.meetingEvents = { [weak self] in self?.refreshCalendarState?().events ?? [] }
        created.meetingLeadMinutes = { [weak self] in self?.meetingLeadMinutes?() ?? 10 }
        created.setDictating(isDictating)
        return created
    }

    private func run(_ shortcut: NotchShortcut) {
        switch shortcut {
        case .clipboard: onOpenClipboard?()
        case .notebook: onOpenNotes?()
        case .camera: onOpenCamera?()
        case .settings: onOpenSettings?()
        // Both are menus in the header, so neither arrives as a plain press.
        case .windowManagement, .timer: break
        }
    }

    private func recoverTap() {
        guard status == .active, !tap.isEnabled else { return }
        tap.tearDown()
        apply()
    }

    private func permissionsChanged() {
        permissionRetry?.cancel()
        permissionRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.apply()
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.notchHUDEnabled
            _ = settings.notchShelfEnabled
            _ = settings.notchOpenOnHover
            _ = settings.notchHoverDelayMs
            _ = settings.notchHapticsEnabled
            _ = settings.notchRemembersLastTab
            _ = settings.notchBatteryNotifications
            _ = settings.notchShowsPercentage
            _ = settings.notchTintsAccent
            _ = settings.notchShowsBattery
            _ = settings.notchShowsMedia
            _ = settings.notchShortcuts
            _ = settings.notchShowsLiveActivities
            _ = settings.notchInputSourceNotifications
            _ = settings.clipboardEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeSettings()
                self.apply()
            }
        }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observers = [
            observe(workspace, NSWorkspace.willSleepNotification) { $0.pause(.asleep) },
            observe(workspace, NSWorkspace.didWakeNotification) { $0.resume(.asleep) },
            observe(workspace, NSWorkspace.sessionDidResignActiveNotification) {
                $0.pause(.sessionInactive)
            },
            observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) {
                $0.resume(.sessionInactive)
            },
            observe(distributed, Notification.Name("com.apple.screenIsLocked")) {
                $0.pause(.screenLocked)
            },
            observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) {
                $0.resume(.screenLocked)
            }
        ]
        darwinObservers = [
            DarwinNotificationToken("com.apple.coregraphics.eventTapRemoved") { [weak self] in
                self?.recoverTap()
            },
            DarwinNotificationToken("com.apple.tcc.access.changed") { [weak self] in
                self?.permissionsChanged()
            }
        ]
    }

    private func pause(_ reason: PauseReason) {
        pauseReasons.insert(reason)
        apply()
    }

    private func resume(_ reason: PauseReason) {
        pauseReasons.remove(reason)
        apply()
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ handler: @escaping @Sendable @MainActor (NotchHUDManager) -> Void
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
