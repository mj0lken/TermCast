import CoreAudio
import Foundation

/// Converts live scroll deltas directly into HID media keys, pacing Bluetooth AVRCP outputs.
@MainActor
final class HyperScrollRunner {
    private static let localStepInterval: TimeInterval = 0.012
    /// Matches Bluetooth AVRCP throughput (~22 pkt/s) so bluetoothaudiod never builds a lag queue.
    private static let bluetoothStepInterval: TimeInterval = 0.045
    private static let gestureExpiry: TimeInterval = 0.25

    private var activeZone: HyperScrollZone?
    private var pendingDelta: Double = 0
    private var isBluetoothOutput = false
    private var lastEventAt: TimeInterval = 0
    private var lastPostedAt: TimeInterval = 0

    func resetGesture() {
        activeZone = nil
        pendingDelta = 0
    }

    func apply(_ adjustment: HyperScrollEngine.Adjustment) {
        let now = ProcessInfo.processInfo.systemUptime
        if activeZone != adjustment.zone || now - lastEventAt > Self.gestureExpiry {
            activeZone = adjustment.zone
            pendingDelta = 0
            if adjustment.zone == .volume {
                isBluetoothOutput = Self.defaultOutputUsesBluetooth()
            }
        }
        lastEventAt = now
        HyperScrollEngine.accumulate(adjustment.delta, into: &pendingDelta)

        let useBluetoothStepping = adjustment.zone == .volume && isBluetoothOutput
        let interval = useBluetoothStepping ? Self.bluetoothStepInterval : Self.localStepInterval
        guard now - lastPostedAt >= interval,
            let step = HyperScrollEngine.popMediaStep(
                from: &pendingDelta, allowFineSteps: !useBluetoothStepping)
        else { return }
        lastPostedAt = now
        post(step, for: adjustment.zone)
    }

    private func post(_ step: HyperScrollEngine.MediaStep, for zone: HyperScrollZone) {
        let key: MediaKeyPoster.Key
        switch (zone, step.up) {
        case (.screenBrightness, true): key = .brightnessUp
        case (.screenBrightness, false): key = .brightnessDown
        case (.keyboardBrightness, true): key = .illuminationUp
        case (.keyboardBrightness, false): key = .illuminationDown
        case (.volume, true): key = .soundUp
        case (.volume, false): key = .soundDown
        }
        MediaKeyPoster.post(key, fineStep: step.fine)
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
