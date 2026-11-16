import AppKit
import CoreGraphics

/// Owns the Notch HUD's lifecycle, tap installation, hardware service routing and preview.
@MainActor
@Observable
final class NotchHUDManager: HealthCheckable {
    enum Status: Equatable {
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

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let displayBrightness: DisplayBrightnessService
    @ObservationIgnored private let audioVolume = AudioVolumeService()
    @ObservationIgnored private let keyboardBacklight = KeyboardBacklightService()
    @ObservationIgnored private let tap = MediaKeyInterceptorTap()
    @ObservationIgnored private let controller = NotchHUDController()
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
        displayBrightness.onBrightnessStepped = { [weak self] outcome in
            guard let self, self.isEnabled else { return }
            self.controller.present(
                metric: .screenBrightness(level: outcome.level),
                overshoot: outcome.overshoot,
                preferredDisplayID: outcome.displayID)
        }
        observeSettings()
        observeSystem()
        apply()
    }

    func prepareForTermination() {
        stop(.off)
    }

    func healthCheck() {
        apply()
    }

    // MARK: - Direct Routing (Hyper Scroll & System Actions)

    func isBluetoothOutput() -> Bool {
        audioVolume.isBluetoothOutput()
    }

    func resetBacklightGesture() {
        keyboardBacklight.resetGesture()
    }

    /// Direct fast path for `HyperScrollRunner` so active sliders skip synthetic `MediaKeyPoster` round-trips.
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
        controller.present(
            metric: .volume(level: outcome.state.level, muted: outcome.state.isMuted),
            overshoot: outcome.overshoot)
    }

    func toggleMute() {
        guard let state = audioVolume.toggleMute() else { return }
        controller.present(metric: .volume(level: state.level, muted: state.isMuted))
    }

    func presentVolumeState(level: Double, muted: Bool) {
        controller.present(metric: .volume(level: level, muted: muted))
    }

    func stepKeyboardBacklight(up: Bool, fine: Bool = false) {
        guard let outcome = keyboardBacklight.step(up: up, fine: fine) else { return }
        controller.present(
            metric: .keyboardBacklight(level: outcome.level, suppressed: outcome.isSuppressed),
            overshoot: outcome.overshoot)
    }

    func showPreview() {
        let samples: [NotchHUDMetric] = [
            .volume(level: audioVolume.currentState()?.level ?? 0.65, muted: false),
            .screenBrightness(level: 0.75),
            .keyboardBacklight(level: 0.5, suppressed: false)
        ]
        let metric = samples[previewStepIndex % samples.count]
        previewStepIndex += 1
        controller.present(metric: metric)
    }

    // MARK: - Physical Media Keys & External Audio Events

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
        controller.present(
            metric: .audioDeviceConnected(
                name: state.deviceName,
                symbol: symbol,
                level: state.level,
                muted: state.isMuted))
    }

    private func presentExternalVolumeChange(_ state: AudioVolumeService.State) {
        guard isEnabled else { return }
        controller.present(metric: .volume(level: state.level, muted: state.isMuted))
    }

    // MARK: - Lifecycle Convergence

    private func apply() {
        guard settings.notchHUDEnabled else {
            return stop(.off)
        }
        guard pauseReasons.isEmpty else {
            return stop(.paused)
        }
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

    private func stop(_ nextStatus: Status) {
        tap.tearDown()
        audioVolume.stop()
        keyboardBacklight.resetGesture()
        displayBrightness.showsSystemOSD = true
        controller.dismissImmediately()
        healthTicker?.unsubscribe(self)
        if status != nextStatus { status = nextStatus }
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
