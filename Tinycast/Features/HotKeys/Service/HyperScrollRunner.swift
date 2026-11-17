import AppKit
import CoreAudio
import CoreGraphics
import Foundation

/// Routes live scroll deltas to cursor-display brightness or media keys, pacing Bluetooth AVRCP.
@MainActor
final class HyperScrollRunner {
    private static let localStepInterval: TimeInterval = 0.012
    /// Matches Bluetooth AVRCP throughput (~22 pkt/s) so bluetoothaudiod never builds a lag queue.
    private static let bluetoothStepInterval: TimeInterval = 0.045
    private static let gestureExpiry: TimeInterval = 0.25

    private let now: () -> TimeInterval
    private let cursorDisplayID: () -> CGDirectDisplayID?
    private let stepDisplayBrightness: (CGDirectDisplayID, Double) -> Void
    private let resetDisplayBrightness: () -> Void
    private let stopDisplayBrightness: () -> Void
    private let postMediaKey: (MediaKeyPoster.Key, Bool) -> Void
    private let isBluetoothAudio: () -> Bool

    private var activeZone: HyperScrollZone?
    private var activeDisplayID: CGDirectDisplayID?
    private var pendingDelta: Double = 0
    private var isBluetoothOutput = false
    private var lastEventAt: TimeInterval = 0
    private var lastPostedAt: TimeInterval = 0

    convenience init(
        displayBrightness: DisplayBrightnessService = DisplayBrightnessService(),
        postMediaKey: @escaping (MediaKeyPoster.Key, Bool) -> Void = { key, fine in
            MediaKeyPoster.post(key, fineStep: fine)
        },
        resetKeyboardBrightness: @escaping () -> Void = {},
        isBluetoothAudio: (() -> Bool)? = nil
    ) {
        self.init(
            now: { ProcessInfo.processInfo.systemUptime },
            cursorDisplayID: { NSScreen.underCursor?.displayID },
            stepDisplayBrightness: { displayID, delta in
                displayBrightness.step(on: displayID, delta: delta)
            },
            resetDisplayBrightness: {
                displayBrightness.resetGesture()
                resetKeyboardBrightness()
            },
            stopDisplayBrightness: {
                displayBrightness.cancelPendingWork()
                resetKeyboardBrightness()
            },
            postMediaKey: postMediaKey,
            isBluetoothAudio: isBluetoothAudio ?? { Self.defaultOutputUsesBluetooth() })
    }

    init(
        now: @escaping () -> TimeInterval,
        cursorDisplayID: @escaping () -> CGDirectDisplayID?,
        stepDisplayBrightness: @escaping (CGDirectDisplayID, Double) -> Void,
        resetDisplayBrightness: @escaping () -> Void = {},
        stopDisplayBrightness: @escaping () -> Void = {},
        postMediaKey: @escaping (MediaKeyPoster.Key, Bool) -> Void,
        isBluetoothAudio: @escaping () -> Bool = { false }
    ) {
        self.now = now
        self.cursorDisplayID = cursorDisplayID
        self.stepDisplayBrightness = stepDisplayBrightness
        self.resetDisplayBrightness = resetDisplayBrightness
        self.stopDisplayBrightness = stopDisplayBrightness
        self.postMediaKey = postMediaKey
        self.isBluetoothAudio = isBluetoothAudio
    }

    func resetGesture() {
        activeZone = nil
        activeDisplayID = nil
        pendingDelta = 0
        resetDisplayBrightness()
    }

    func cancelPendingWork() {
        activeZone = nil
        activeDisplayID = nil
        pendingDelta = 0
        stopDisplayBrightness()
    }

    func apply(_ adjustment: HyperScrollEngine.Adjustment) {
        let timestamp = now()
        if activeZone != adjustment.zone || timestamp - lastEventAt > Self.gestureExpiry {
            activeZone = adjustment.zone
            pendingDelta = 0
            resetDisplayBrightness()
            switch adjustment.zone {
            case .screenBrightness:
                activeDisplayID = cursorDisplayID()
            case .keyboardBrightness:
                activeDisplayID = nil
            case .volume:
                activeDisplayID = nil
                isBluetoothOutput = isBluetoothAudio()
            }
        }
        lastEventAt = timestamp
        HyperScrollEngine.accumulate(adjustment.delta, into: &pendingDelta)

        let useBluetoothStepping = adjustment.zone == .volume && isBluetoothOutput
        let interval = useBluetoothStepping ? Self.bluetoothStepInterval : Self.localStepInterval
        guard timestamp - lastPostedAt >= interval,
            let step = HyperScrollEngine.popMediaStep(
                from: &pendingDelta, allowFineSteps: !useBluetoothStepping)
        else { return }
        lastPostedAt = timestamp
        dispatch(step, for: adjustment.zone)
    }

    private func dispatch(_ step: HyperScrollEngine.MediaStep, for zone: HyperScrollZone) {
        switch zone {
        case .screenBrightness:
            guard let displayID = activeDisplayID else { return }
            let magnitude = step.fine ? HyperScrollEngine.fineStep : HyperScrollEngine.coarseStep
            stepDisplayBrightness(displayID, step.up ? magnitude : -magnitude)
        case .keyboardBrightness:
            postMediaKey(step.up ? .illuminationUp : .illuminationDown, step.fine)
        case .volume:
            postMediaKey(step.up ? .soundUp : .soundDown, step.fine)
        }
    }

    private static func defaultOutputUsesBluetooth() -> Bool {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &size, &device
            ) == noErr,
            device != kAudioObjectUnknown
        else { return false }

        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        guard
            AudioObjectGetPropertyData(
                device, &transportAddress, 0, nil, &transportSize, &transport
            ) == noErr
        else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}
