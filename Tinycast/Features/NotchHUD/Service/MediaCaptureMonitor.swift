import AppKit
import CoreAudio
import CoreMediaIO
import Observation

/// Reports microphone and camera use by other apps, from property listeners alone.
@MainActor
@Observable
final class MediaCaptureMonitor {
    private(set) var use = NotchCaptureUse()

    /// Carries the name of the app that started recording, when macOS reveals one.
    @ObservationIgnored var onMicrophoneStarted: ((String?) -> Void)?
    @ObservationIgnored var onCameraStarted: (() -> Void)?
    /// CoreMediaIO names no process, so Tinycast's own camera use has to be reported to it.
    @ObservationIgnored var isOwnCameraLive: (() -> Bool)?

    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var processListBlock: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var processBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    @ObservationIgnored private var cameraListBlock: CMIOObjectPropertyListenerBlock?
    @ObservationIgnored private var cameraBlocks: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]

    /// Always-listening system daemons hold the microphone without the user recording anything.
    private static let ignoredBundleIDs: Set<String> = ["com.apple.CoreSpeech"]
    private static let audioSystem = AudioObjectID(kAudioObjectSystemObject)
    private static let cameraSystem = CMIOObjectID(kCMIOObjectSystemObject)

    func start() {
        guard !isStarted else { return }
        isStarted = true
        installProcessListListener()
        installCameraListListener()
        syncProcessListeners()
        syncCameraListeners()
        use = NotchCaptureUse(microphone: !microphoneUsers().isEmpty, camera: isAnyCameraRunning())
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        removeAudioListeners()
        removeCameraListeners()
        if use.isActive { use = NotchCaptureUse() }
    }

    // MARK: - Microphone

    private func installProcessListListener() {
        var address = Self.audioAddress(kAudioHardwarePropertyProcessObjectList)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncProcessListeners()
                self?.refreshMicrophone()
            }
        }
        if AudioObjectAddPropertyListenerBlock(Self.audioSystem, &address, .main, block) == noErr {
            processListBlock = block
        }
    }

    private func syncProcessListeners() {
        guard isStarted else { return }
        let live = Set(Self.audioObjects(Self.audioSystem, kAudioHardwarePropertyProcessObjectList))
        var address = Self.audioAddress(kAudioProcessPropertyIsRunningInput)
        for (process, block) in processBlocks where !live.contains(process) {
            AudioObjectRemovePropertyListenerBlock(process, &address, .main, block)
            processBlocks[process] = nil
        }
        for process in live where processBlocks[process] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshMicrophone()
                }
            }
            if AudioObjectAddPropertyListenerBlock(process, &address, .main, block) == noErr {
                processBlocks[process] = block
            }
        }
    }

    private func refreshMicrophone() {
        guard isStarted else { return }
        let users = microphoneUsers()
        let isInUse = !users.isEmpty
        guard isInUse != use.microphone else { return }
        use.microphone = isInUse
        if isInUse { onMicrophoneStarted?(users.lazy.compactMap(Self.appName(of:)).first) }
    }

    private func microphoneUsers() -> [AudioObjectID] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        return processBlocks.keys.filter { process in
            guard Self.audioFlag(process, kAudioProcessPropertyIsRunningInput),
                Self.processID(of: process) != ownPID
            else { return false }
            let bundleID = Self.bundleID(of: process) ?? ""
            // Tinycast's own dictation is its own activity, not somebody else's recording.
            let isOwn = !ownBundleID.isEmpty && bundleID.hasPrefix(ownBundleID)
            return !isOwn && !Self.ignoredBundleIDs.contains(bundleID)
        }
    }

    private func removeAudioListeners() {
        if let block = processListBlock {
            var address = Self.audioAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(Self.audioSystem, &address, .main, block)
            processListBlock = nil
        }
        var address = Self.audioAddress(kAudioProcessPropertyIsRunningInput)
        for (process, block) in processBlocks {
            AudioObjectRemovePropertyListenerBlock(process, &address, .main, block)
        }
        processBlocks.removeAll()
    }

    /// A browser records through a helper, so the name comes from the nearest app with a Dock icon.
    private static func appName(of process: AudioObjectID) -> String? {
        let recorder = processID(of: process).flatMap(NSRunningApplication.init(processIdentifier:))
        if let recorder, recorder.activationPolicy == .regular { return recorder.localizedName }
        var components = (bundleID(of: process) ?? "").split(separator: ".").map(String.init)
        while components.count >= 2 {
            let owner = NSRunningApplication
                .runningApplications(withBundleIdentifier: components.joined(separator: "."))
                .first { $0.activationPolicy == .regular }
            if let name = owner?.localizedName { return name }
            components.removeLast()
        }
        return recorder?.localizedName
    }

    private static func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioObjects(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) -> [AudioObjectID] {
        var address = audioAddress(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else {
            return []
        }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func audioFlag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = audioAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func processID(of process: AudioObjectID) -> pid_t? {
        var address = audioAddress(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = audioAddress(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    // MARK: - Camera

    private func installCameraListListener() {
        var address = Self.cameraAddress(kCMIOHardwarePropertyDevices)
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncCameraListeners()
                self?.refreshCamera()
            }
        }
        if CMIOObjectAddPropertyListenerBlock(Self.cameraSystem, &address, .main, block) == noErr {
            cameraListBlock = block
        }
    }

    private func syncCameraListeners() {
        guard isStarted else { return }
        let live = Set(Self.cameraDevices())
        var address = Self.cameraAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        for (device, block) in cameraBlocks where !live.contains(device) {
            CMIOObjectRemovePropertyListenerBlock(device, &address, .main, block)
            cameraBlocks[device] = nil
        }
        for device in live where cameraBlocks[device] == nil {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshCamera()
                }
            }
            if CMIOObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr {
                cameraBlocks[device] = block
            }
        }
    }

    private func refreshCamera() {
        guard isStarted else { return }
        let isInUse = isAnyCameraRunning()
        guard isInUse != use.camera else { return }
        use.camera = isInUse
        if isInUse { onCameraStarted?() }
    }

    private func isAnyCameraRunning() -> Bool {
        guard isOwnCameraLive?() != true else { return false }
        return cameraBlocks.keys.contains(where: Self.isCameraRunning)
    }

    private func removeCameraListeners() {
        if let block = cameraListBlock {
            var address = Self.cameraAddress(kCMIOHardwarePropertyDevices)
            CMIOObjectRemovePropertyListenerBlock(Self.cameraSystem, &address, .main, block)
            cameraListBlock = nil
        }
        var address = Self.cameraAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        for (device, block) in cameraBlocks {
            CMIOObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        cameraBlocks.removeAll()
    }

    private static func cameraAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func cameraDevices() -> [CMIOObjectID] {
        var address = cameraAddress(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(cameraSystem, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(cameraSystem, &address, 0, nil, size, &used, &devices) == noErr else {
            return []
        }
        return Array(devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func isCameraRunning(_ device: CMIOObjectID) -> Bool {
        var address = cameraAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &value) == noErr && value != 0
    }
}
