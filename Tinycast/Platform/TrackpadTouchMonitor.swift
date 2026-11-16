import CoreFoundation
import Darwin
import Synchronization

private typealias MTContactCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeRawPointer?,
    Int32,
    Double,
    Int32,
    UnsafeMutableRawPointer?
) -> Int32

private func trackpadContactCallback(
    device: UnsafeMutableRawPointer?,
    touches: UnsafeRawPointer?,
    count: Int32,
    timestamp: Double,
    frame: Int32,
    refcon: UnsafeMutableRawPointer?
) -> Int32 {
    guard let device, let refcon else { return 0 }
    let monitor = Unmanaged<TrackpadTouchMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.receiveFrame(device: device, touches: touches, count: Int(count))
    return 0
}

/// Streams normalized finger X positions from MultitouchSupport only while started.
final class TrackpadTouchMonitor: Sendable {
    /// Verified against arm64 MultitouchSupport: 96-byte stride, normalized X Float at 0x20.
    private enum Layout {
        static let stride = 96
        static let normalizedXOffset = 32
    }

    /// Immutable C function pointers resolved once via dlsym at initialization.
    private struct Functions: @unchecked Sendable {
        let createList: @convention(c) () -> Unmanaged<CFArray>?
        let registerCallback:
            @convention(c) (
                UnsafeMutableRawPointer, MTContactCallback, UnsafeMutableRawPointer?
            ) -> Void
        let unregisterCallback:
            @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
        let startDevice: @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
        let stopDevice: @convention(c) (UnsafeMutableRawPointer) -> Void

        init?() {
            let path =
                "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
            guard let handle = dlopen(path, RTLD_LAZY),
                let createList = dlsym(handle, "MTDeviceCreateList"),
                let register = dlsym(handle, "MTRegisterContactFrameCallbackWithRefcon"),
                let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
                let startDevice = dlsym(handle, "MTDeviceStart"),
                let stopDevice = dlsym(handle, "MTDeviceStop")
            else { return nil }
            self.createList = unsafeBitCast(createList, to: Self.CreateList.self)
            self.registerCallback = unsafeBitCast(register, to: Self.Register.self)
            self.unregisterCallback = unsafeBitCast(unregister, to: Self.Unregister.self)
            self.startDevice = unsafeBitCast(startDevice, to: Self.Start.self)
            self.stopDevice = unsafeBitCast(stopDevice, to: Self.Stop.self)
        }

        private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
        private typealias Register =
            @convention(c) (
                UnsafeMutableRawPointer, MTContactCallback, UnsafeMutableRawPointer?
            ) -> Void
        private typealias Unregister =
            @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
        private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
        private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void
    }

    /// Guarded exclusively by `state` Mutex; `deviceList` retains the opaque MTDevice handles.
    private struct State: @unchecked Sendable {
        var deviceList: CFArray?
        var devices: [UnsafeMutableRawPointer] = []
        var isRunning = false
        var activeXsByDevice: [UInt: [Double]] = [:]
    }

    private let functions: Functions
    private let onTouches: @Sendable ([Double]) -> Void
    private let state = Mutex(State())

    init?(onTouches: @escaping @Sendable ([Double]) -> Void) {
        guard let functions = Functions() else { return nil }
        self.functions = functions
        self.onTouches = onTouches
    }

    deinit {
        stop()
    }

    func start() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        state.withLock { state in
            guard !state.isRunning else { return }
            if state.devices.isEmpty, let list = functions.createList()?.takeRetainedValue() {
                state.deviceList = list
                state.devices = (0..<CFArrayGetCount(list)).compactMap { index in
                    CFArrayGetValueAtIndex(list, index).map { UnsafeMutableRawPointer(mutating: $0) }
                }
            }
            guard !state.devices.isEmpty else { return }
            state.activeXsByDevice.removeAll(keepingCapacity: true)
            state.isRunning = true
            for device in state.devices {
                functions.registerCallback(device, trackpadContactCallback, refcon)
                functions.startDevice(device, 0)
            }
        }
    }

    func stop() {
        let devicesToStop: [UnsafeMutableRawPointer] = state.withLock { state in
            guard state.isRunning else { return [] }
            state.isRunning = false
            state.activeXsByDevice.removeAll(keepingCapacity: true)
            return state.devices
        }
        for device in devicesToStop {
            functions.unregisterCallback(device, trackpadContactCallback)
            functions.stopDevice(device)
        }
    }

    fileprivate func receiveFrame(
        device: UnsafeMutableRawPointer, touches: UnsafeRawPointer?, count: Int
    ) {
        var xs: [Double] = []
        if let touches, count > 0 {
            xs.reserveCapacity(count)
            for index in 0..<count {
                let offset = index * Layout.stride + Layout.normalizedXOffset
                let rawX = touches.loadUnaligned(fromByteOffset: offset, as: Float.self)
                if rawX.isFinite {
                    xs.append(Double(min(max(rawX, 0), 1)))
                }
            }
        }
        let combined: [Double]? = state.withLock { state in
            guard state.isRunning else { return nil }
            let key = UInt(bitPattern: device)
            if xs.isEmpty {
                state.activeXsByDevice.removeValue(forKey: key)
            } else {
                state.activeXsByDevice[key] = xs
            }
            return state.activeXsByDevice.values.flatMap { $0 }
        }
        if let combined { onTouches(combined) }
    }
}
