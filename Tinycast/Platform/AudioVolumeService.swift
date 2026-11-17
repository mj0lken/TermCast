import AudioToolbox
import CoreAudio
import Foundation

/// Event-driven CoreAudio output cache with zero per-tick device discovery and zero idle polling.
@MainActor
final class AudioVolumeService {
    struct State: Sendable, Equatable {
        let deviceID: AudioDeviceID
        let deviceName: String
        let isBluetooth: Bool
        let level: Double
        let isMuted: Bool
    }

    struct StepOutcome: Sendable, Equatable {
        let state: State
        let overshoot: Double
    }

    private struct DeviceDescriptor {
        let id: AudioDeviceID
        let name: String
        let isBluetooth: Bool
        let usesVirtualMainVolume: Bool
        let volumeElements: [AudioObjectPropertyElement]
        let hasMuteProperty: Bool
    }

    private struct DeviceListenerRegistration {
        let deviceID: AudioDeviceID
        let addresses: [AudioObjectPropertyAddress]
        let block: AudioObjectPropertyListenerBlock
    }

    private static let selfWriteEchoWindow: TimeInterval = 0.28

    var onExternalVolumeChange: ((State) -> Void)?
    var onBluetoothOutputConnected: ((State) -> Void)?
    var isSuppressingExternalNotifications: () -> Bool = { false }

    private var isStarted = false
    private var defaultDeviceBlock: AudioObjectPropertyListenerBlock?
    private var deviceRegistration: DeviceListenerRegistration?
    private var descriptor: DeviceDescriptor?
    private var cachedLevel: Double = 0
    private var cachedMuted = false
    private var lastSelfWriteUptime: TimeInterval = -.infinity

    func start() {
        guard !isStarted else { return }
        isStarted = true
        installDefaultDeviceListener()
        refreshActiveDevice(announceBluetoothConnect: false)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        removeDeviceListeners()
        removeDefaultDeviceListener()
        descriptor = nil
    }

    func currentState() -> State? {
        guard let device = activeDescriptor() else { return nil }
        if !isStarted {
            cachedLevel = Self.readLevel(from: device)
            cachedMuted = Self.readMuted(from: device)
        }
        return State(
            deviceID: device.id,
            deviceName: device.name,
            isBluetooth: device.isBluetooth,
            level: cachedLevel,
            isMuted: cachedMuted)
    }

    func isBluetoothOutput() -> Bool {
        activeDescriptor()?.isBluetooth ?? false
    }

    func step(up: Bool, fine: Bool) -> StepOutcome? {
        let delta = (fine ? 1.0 / 64.0 : 1.0 / 16.0) * (up ? 1 : -1)
        return step(delta: delta)
    }

    func step(delta: Double) -> StepOutcome? {
        guard let device = activeDescriptor() else { return nil }
        let startingLevel = isStarted ? cachedLevel : Self.readLevel(from: device)
        let startingMuted = isStarted ? cachedMuted : Self.readMuted(from: device)

        if startingMuted, delta < 0, startingLevel <= 0.001 {
            let snapshot = State(
                deviceID: device.id,
                deviceName: device.name,
                isBluetooth: device.isBluetooth,
                level: 0,
                isMuted: true)
            return StepOutcome(state: snapshot, overshoot: -1)
        }

        let effectiveStart = (startingMuted && delta > 0 && startingLevel <= 0.001) ? 0 : startingLevel
        let raw = effectiveStart + delta
        let nextLevel = min(max(raw, 0), 1)
        let reference = max(abs(delta), 1.0 / 64.0)
        let overshoot: Double
        if raw < 0 {
            overshoot = -min(abs(raw) / reference, 1)
        } else if raw > 1 {
            overshoot = min((raw - 1) / reference, 1)
        } else {
            overshoot = 0
        }

        lastSelfWriteUptime = ProcessInfo.processInfo.systemUptime
        let wroteVolume = Self.writeLevel(Float32(nextLevel), to: device)
        let nextMuted: Bool
        if nextLevel <= 0.0001 {
            if device.hasMuteProperty, Self.writeMuted(true, to: device) {
                nextMuted = true
            } else {
                nextMuted = startingMuted
            }
        } else if startingMuted {
            _ = Self.writeMuted(false, to: device)
            nextMuted = false
        } else {
            nextMuted = false
        }

        let appliedLevel = wroteVolume ? nextLevel : startingLevel
        cachedLevel = appliedLevel
        cachedMuted = nextMuted
        let snapshot = State(
            deviceID: device.id,
            deviceName: device.name,
            isBluetooth: device.isBluetooth,
            level: appliedLevel,
            isMuted: nextMuted)
        return StepOutcome(state: snapshot, overshoot: wroteVolume ? overshoot : (delta >= 0 ? 1 : -1))
    }

    func toggleMute() -> State? {
        guard let device = activeDescriptor() else { return nil }
        let currentMuted = isStarted ? cachedMuted : Self.readMuted(from: device)
        let currentLevel = isStarted ? cachedLevel : Self.readLevel(from: device)
        let targetMuted = !currentMuted
        lastSelfWriteUptime = ProcessInfo.processInfo.systemUptime

        if device.hasMuteProperty, Self.writeMuted(targetMuted, to: device) {
            var updatedLevel = currentLevel
            if !targetMuted, currentLevel <= 0.001 {
                updatedLevel = 1.0 / 16.0
                _ = Self.writeLevel(Float32(updatedLevel), to: device)
            }
            cachedLevel = updatedLevel
            cachedMuted = targetMuted
            return State(
                deviceID: device.id,
                deviceName: device.name,
                isBluetooth: device.isBluetooth,
                level: updatedLevel,
                isMuted: targetMuted)
        }
        return nil
    }

    // MARK: - Device Cache & Listeners

    private func activeDescriptor() -> DeviceDescriptor? {
        if isStarted, let descriptor { return descriptor }
        return Self.queryDefaultDescriptor()
    }

    private func installDefaultDeviceListener() {
        guard defaultDeviceBlock == nil else { return }
        var address = Self.defaultOutputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshActiveDevice(announceBluetoothConnect: true)
            }
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, block
        ) == noErr {
            defaultDeviceBlock = block
        }
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceBlock else { return }
        var address = Self.defaultOutputAddress
        _ = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        defaultDeviceBlock = nil
    }

    private func refreshActiveDevice(announceBluetoothConnect: Bool) {
        let previousID = descriptor?.id
        removeDeviceListeners()
        let next = Self.queryDefaultDescriptor()
        descriptor = next
        guard let next else {
            cachedLevel = 0
            cachedMuted = false
            return
        }
        cachedLevel = Self.readLevel(from: next)
        cachedMuted = Self.readMuted(from: next)
        installDeviceListeners(for: next)

        guard announceBluetoothConnect,
            previousID != next.id,
            next.isBluetooth,
            !isSuppressingExternalNotifications()
        else { return }

        let state = State(
            deviceID: next.id,
            deviceName: next.name,
            isBluetooth: true,
            level: cachedLevel,
            isMuted: cachedMuted)
        onBluetoothOutputConnected?(state)
    }

    private func installDeviceListeners(for device: DeviceDescriptor) {
        var addresses: [AudioObjectPropertyAddress] = []
        if device.usesVirtualMainVolume {
            addresses.append(Self.virtualMainVolumeAddress)
        } else {
            for element in device.volumeElements {
                addresses.append(Self.volumeScalarAddress(element: element))
            }
        }
        if device.hasMuteProperty {
            addresses.append(Self.muteAddress)
        }
        guard !addresses.isEmpty else { return }

        let targetID = device.id
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDevicePropertyChanged(deviceID: targetID)
            }
        }
        var registered: [AudioObjectPropertyAddress] = []
        for var address in addresses
        where AudioObjectAddPropertyListenerBlock(targetID, &address, .main, block) == noErr {
            registered.append(address)
        }
        if !registered.isEmpty {
            deviceRegistration = DeviceListenerRegistration(
                deviceID: targetID, addresses: registered, block: block)
        }
    }

    private func removeDeviceListeners() {
        guard let registration = deviceRegistration else { return }
        for var address in registration.addresses {
            _ = AudioObjectRemovePropertyListenerBlock(
                registration.deviceID, &address, .main, registration.block)
        }
        deviceRegistration = nil
    }

    private func handleDevicePropertyChanged(deviceID: AudioDeviceID) {
        guard let descriptor, descriptor.id == deviceID else { return }
        let nextLevel = Self.readLevel(from: descriptor)
        let nextMuted = Self.readMuted(from: descriptor)
        let changed = abs(nextLevel - cachedLevel) >= 0.004 || nextMuted != cachedMuted
        cachedLevel = nextLevel
        cachedMuted = nextMuted

        let elapsed = ProcessInfo.processInfo.systemUptime - lastSelfWriteUptime
        guard changed,
            elapsed > Self.selfWriteEchoWindow,
            !isSuppressingExternalNotifications()
        else { return }

        let state = State(
            deviceID: descriptor.id,
            deviceName: descriptor.name,
            isBluetooth: descriptor.isBluetooth,
            level: nextLevel,
            isMuted: nextMuted)
        onExternalVolumeChange?(state)
    }

    // MARK: - Low-level CoreAudio Queries

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static var virtualMainVolumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func volumeScalarAddress(
        element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
    }

    private static func queryDefaultDescriptor() -> DeviceDescriptor? {
        var address = defaultOutputAddress
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
            ) == noErr,
            device != kAudioObjectUnknown
        else { return nil }

        let name = queryDeviceName(device)
        let bluetooth = queryIsBluetooth(device)
        var virtualAddress = virtualMainVolumeAddress
        let hasVirtual = AudioObjectHasProperty(device, &virtualAddress)
        let elements = hasVirtual ? [] : queryVolumeElements(device)
        var mute = muteAddress
        let hasMute = AudioObjectHasProperty(device, &mute)
        return DeviceDescriptor(
            id: device,
            name: name,
            isBluetooth: bluetooth,
            usesVirtualMainVolume: hasVirtual,
            volumeElements: elements,
            hasMuteProperty: hasMute)
    }

    private static func queryDeviceName(_ device: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let cfName = unmanaged?.takeRetainedValue() else {
            return String(localized: "Audio Output")
        }
        return cfName as String
    }

    private static func queryIsBluetooth(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else {
            return false
        }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func queryVolumeElements(_ device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        var main = volumeScalarAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &main) {
            return [kAudioObjectPropertyElementMain]
        }
        var stereoAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var channels: (UInt32, UInt32) = (1, 2)
        var size = UInt32(MemoryLayout<(UInt32, UInt32)>.size)
        if AudioObjectGetPropertyData(device, &stereoAddress, 0, nil, &size, &channels) != noErr {
            channels = (1, 2)
        }
        return [channels.0, channels.1].filter { channel in
            var address = volumeScalarAddress(element: channel)
            return AudioObjectHasProperty(device, &address)
        }
    }

    private static func readLevel(from device: DeviceDescriptor) -> Double {
        if device.usesVirtualMainVolume {
            var address = virtualMainVolumeAddress
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &value) == noErr {
                return min(max(Double(value), 0), 1)
            }
        }
        guard !device.volumeElements.isEmpty else { return 0 }
        var total: Double = 0
        var count = 0
        for element in device.volumeElements {
            var address = volumeScalarAddress(element: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &value) == noErr {
                total += Double(value)
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return min(max(total / Double(count), 0), 1)
    }

    private static func writeLevel(_ value: Float32, to device: DeviceDescriptor) -> Bool {
        var applied = min(max(value, 0), 1)
        if device.usesVirtualMainVolume {
            var address = virtualMainVolumeAddress
            var settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(device.id, &address, &settable) == noErr,
                settable.boolValue,
                AudioObjectSetPropertyData(
                    device.id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &applied
                ) == noErr
            {
                return true
            }
        }
        guard !device.volumeElements.isEmpty else { return false }
        var wroteAny = false
        for element in device.volumeElements {
            var address = volumeScalarAddress(element: element)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device.id, &address, &settable) == noErr,
                settable.boolValue
            else { continue }
            if AudioObjectSetPropertyData(
                device.id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &applied
            ) == noErr {
                wroteAny = true
            }
        }
        return wroteAny
    }

    private static func readMuted(from device: DeviceDescriptor) -> Bool {
        guard device.hasMuteProperty else { return false }
        var address = muteAddress
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &muted) == noErr else {
            return false
        }
        return muted != 0
    }

    private static func writeMuted(_ muted: Bool, to device: DeviceDescriptor) -> Bool {
        guard device.hasMuteProperty else { return false }
        var address = muteAddress
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device.id, &address, &settable) == noErr,
            settable.boolValue
        else { return false }
        var raw: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(
            device.id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &raw
        ) == noErr
    }
}
