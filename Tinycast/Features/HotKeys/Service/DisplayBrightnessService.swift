import CoreFoundation
import CoreGraphics
import Darwin
import Foundation
import IOKit
import ObjectiveC

/// Adjusts brightness on one specific display via DisplayServices or Apple Silicon DDC/CI.
@MainActor
final class DisplayBrightnessService {
    private enum ActiveBackend {
        case native(displayID: CGDirectDisplayID, level: Double)
        case ddc(displayID: CGDirectDisplayID, target: DisplayDDC.Target)
        case unsupported(displayID: CGDirectDisplayID)

        var displayID: CGDirectDisplayID {
            switch self {
            case .native(let id, _), .ddc(let id, _), .unsupported(let id): id
            }
        }
    }

    private static let ddcWriteSpacing: Duration = .milliseconds(50)
    private static let ddcReadDelay: Duration = .milliseconds(40)

    private var activeBackend: ActiveBackend?
    private var ddcLevels: [CGDirectDisplayID: Double] = [:]
    private var ddcWriteGenerations: [CGDirectDisplayID: UInt64] = [:]
    private var pendingDDCWrites: [CGDirectDisplayID: (target: DisplayDDC.Target, level: Double)] = [:]
    private var ddcReadTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var ddcDrainTask: Task<Void, Never>?

    deinit {
        ddcDrainTask?.cancel()
        for task in ddcReadTasks.values { task.cancel() }
    }

    func resetGesture() {
        activeBackend = nil
    }

    func cancelPendingWork() {
        activeBackend = nil
        pendingDDCWrites.removeAll()
        ddcDrainTask?.cancel()
        ddcDrainTask = nil
        for task in ddcReadTasks.values { task.cancel() }
        ddcReadTasks.removeAll()
    }

    func step(on displayID: CGDirectDisplayID, delta: Double) {
        if activeBackend?.displayID != displayID {
            activeBackend = resolveBackend(for: displayID)
        }
        guard let backend = activeBackend else { return }

        switch backend {
        case .native(_, let current):
            let next = min(max(current + delta, 0), 1)
            activeBackend = .native(displayID: displayID, level: next)
            guard NativeDisplayAPI.setBrightness(displayID: displayID, level: Float(next)) else {
                return
            }
            NativeOSD.showBrightness(level: next, on: displayID)

        case .ddc(_, let target):
            let current = ddcLevels[displayID] ?? 0.5
            let next = min(max(current + delta, 0), 1)
            ddcLevels[displayID] = next
            ddcWriteGenerations[displayID, default: 0] &+= 1
            ddcReadTasks.removeValue(forKey: displayID)?.cancel()
            NativeOSD.showBrightness(level: next, on: displayID)
            enqueueDDCWrite(displayID: displayID, target: target, level: next)

        case .unsupported:
            return
        }
    }

    private func resolveBackend(for displayID: CGDirectDisplayID) -> ActiveBackend {
        if let level = NativeDisplayAPI.brightness(of: displayID) {
            return .native(displayID: displayID, level: Double(level))
        }
        guard CGDisplayIsBuiltin(displayID) == 0,
            let target = makeDDCTarget(for: displayID),
            AVServiceDDC.hasMatchingService(for: target)
        else {
            return .unsupported(displayID: displayID)
        }
        scheduleInitialDDCReadIfNeeded(displayID: displayID, target: target)
        return .ddc(displayID: displayID, target: target)
    }

    private func makeDDCTarget(for displayID: CGDirectDisplayID) -> DisplayDDC.Target? {
        var count: UInt32 = 0
        var active = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &active, &count) == .success else { return nil }
        let externalCount = active.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.count
        let identity = DisplayDDC.Identity(
            vendorID: CGDisplayVendorNumber(displayID),
            modelID: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID))
        return DisplayDDC.Target(
            identity: identity,
            allowsSingleExternalFallback: externalCount == 1)
    }

    private func scheduleInitialDDCReadIfNeeded(
        displayID: CGDirectDisplayID, target: DisplayDDC.Target
    ) {
        guard ddcLevels[displayID] == nil, ddcReadTasks[displayID] == nil else { return }
        let generation = ddcWriteGenerations[displayID, default: 0]
        ddcReadTasks[displayID] = Task { [weak self] in
            let level = await Self.readDDCBrightness(target: target)
            guard !Task.isCancelled, let self else { return }
            self.ddcReadTasks.removeValue(forKey: displayID)
            guard let level,
                self.ddcWriteGenerations[displayID, default: 0] == generation,
                self.ddcLevels[displayID] == nil
            else { return }
            self.ddcLevels[displayID] = level
        }
    }

    private func enqueueDDCWrite(
        displayID: CGDirectDisplayID, target: DisplayDDC.Target, level: Double
    ) {
        pendingDDCWrites[displayID] = (target: target, level: level)
        guard ddcDrainTask == nil else { return }
        ddcDrainTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard let (nextID, entry) = self.pendingDDCWrites.first else { break }
                self.pendingDDCWrites.removeValue(forKey: nextID)
                await Self.writeDDCBrightness(target: entry.target, level: entry.level)
                try? await Task.sleep(for: Self.ddcWriteSpacing)
            }
            self?.ddcDrainTask = nil
        }
    }

    @concurrent
    private static func writeDDCBrightness(target: DisplayDDC.Target, level: Double) async {
        AVServiceDDC.writeBrightness(level: level, to: target)
    }

    @concurrent
    private static func readDDCBrightness(target: DisplayDDC.Target) async -> Double? {
        guard AVServiceDDC.sendReadRequest(to: target) else { return nil }
        try? await Task.sleep(for: ddcReadDelay)
        guard !Task.isCancelled else { return nil }
        return AVServiceDDC.readBrightnessReply(from: target)
    }
}

// MARK: - Private Framework Bridges

private enum NativeDisplayAPI {
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetBrightness =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Functions {
        let canChange: CanChange
        let get: GetBrightness
        let setSmooth: SetBrightness
    }

    private nonisolated static let functions: Functions? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY),
            let canChange = dlsym(handle, "DisplayServicesCanChangeBrightness"),
            let get = dlsym(handle, "DisplayServicesGetBrightness"),
            let setSmooth = dlsym(handle, "DisplayServicesSetBrightnessSmooth")
        else { return nil }
        return Functions(
            canChange: unsafeBitCast(canChange, to: CanChange.self),
            get: unsafeBitCast(get, to: GetBrightness.self),
            setSmooth: unsafeBitCast(setSmooth, to: SetBrightness.self))
    }()

    static func brightness(of displayID: CGDirectDisplayID) -> Float? {
        guard let functions, functions.canChange(displayID) else { return nil }
        var value: Float = 0
        guard functions.get(displayID, &value) == 0 else { return nil }
        return min(max(value, 0), 1)
    }

    static func setBrightness(displayID: CGDirectDisplayID, level: Float) -> Bool {
        guard let functions else { return false }
        return functions.setSmooth(displayID, level) == 0
    }
}

@MainActor
private enum NativeOSD {
    private typealias SharedFn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias ShowFn = @convention(c) (
        AnyObject, Selector, Int64, CGDirectDisplayID, UInt32, UInt32, UInt32, UInt32, Bool
    ) -> Void

    private static let brightnessGraphic: Int64 = 1
    private static let priority: UInt32 = 0x1f4
    private static let fadeMilliseconds: UInt32 = 1000
    private static let totalChiclets: UInt32 = 10_000

    private static let showClosure: ((CGDirectDisplayID, UInt32) -> Void)? = {
        guard dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY) != nil,
            let osdClass = NSClassFromString("OSDManager")
        else { return nil }
        let sharedSel = NSSelectorFromString("sharedManager")
        let showSel = NSSelectorFromString(
            "showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:")
        guard let sharedMethod = class_getClassMethod(osdClass, sharedSel) else { return nil }
        let sharedFn = unsafeBitCast(method_getImplementation(sharedMethod), to: SharedFn.self)
        guard let manager = sharedFn(osdClass, sharedSel)?.takeUnretainedValue(),
            let managerClass = object_getClass(manager),
            let showMethod = class_getInstanceMethod(managerClass, showSel)
        else { return nil }
        let showFn = unsafeBitCast(method_getImplementation(showMethod), to: ShowFn.self)
        return { displayID, filled in
            showFn(
                manager, showSel, brightnessGraphic, displayID,
                priority, fadeMilliseconds, filled, totalChiclets, false)
        }
    }()

    static func showBrightness(level: Double, on displayID: CGDirectDisplayID) {
        let filled = UInt32((min(max(level, 0), 1) * Double(totalChiclets)).rounded())
        showClosure?(displayID, filled)
    }
}

private enum AVServiceDDC {
    private typealias CreateService =
        @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias CopyEDID =
        @convention(c) (CFTypeRef, UnsafeMutablePointer<CFData?>) -> IOReturn
    private typealias WriteI2C =
        @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private typealias ReadI2C =
        @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let chipAddress: UInt32 = 0x37
    private static let writeDataAddress: UInt32 = 0x51

    nonisolated static func hasMatchingService(for target: DisplayDDC.Target) -> Bool {
        withMatchingService(for: target) { _, _ in true } ?? false
    }

    nonisolated static func writeBrightness(level: Double, to target: DisplayDDC.Target) {
        _ = withMatchingService(for: target) { service, symbols in
            var packet = DisplayDDC.makeBrightnessWritePacket(level: level)
            return packet.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return false }
                return symbols.writeI2C(
                    service, chipAddress, writeDataAddress, base, UInt32(buffer.count)
                ) == KERN_SUCCESS
            }
        }
    }

    nonisolated static func sendReadRequest(to target: DisplayDDC.Target) -> Bool {
        withMatchingService(for: target) { service, symbols in
            var request = DisplayDDC.makeBrightnessReadRequest()
            return request.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return false }
                return symbols.writeI2C(
                    service, chipAddress, writeDataAddress, base, UInt32(buffer.count)
                ) == KERN_SUCCESS
            }
        } ?? false
    }

    nonisolated static func readBrightnessReply(from target: DisplayDDC.Target) -> Double? {
        guard let result = withMatchingService(for: target, { service, symbols -> Double? in
            var reply = [UInt8](repeating: 0, count: 11)
            let status = reply.withUnsafeMutableBytes { buffer -> IOReturn in
                guard let base = buffer.baseAddress else { return kIOReturnError }
                return symbols.readI2C(service, chipAddress, 0, base, UInt32(buffer.count))
            }
            guard status == KERN_SUCCESS else { return nil }
            return DisplayDDC.parseBrightnessReply(reply)
        }) else { return nil }
        return result
    }

    private struct Symbols {
        let createService: CreateService
        let copyEDID: CopyEDID
        let writeI2C: WriteI2C
        let readI2C: ReadI2C
    }

    private nonisolated static func resolveSymbols() -> Symbols? {
        _ = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
        guard let handle = dlopen(nil, RTLD_LAZY),
            let create = dlsym(handle, "IOAVServiceCreateWithService"),
            let copyEDID = dlsym(handle, "IOAVServiceCopyEDID"),
            let writeI2C = dlsym(handle, "IOAVServiceWriteI2C"),
            let readI2C = dlsym(handle, "IOAVServiceReadI2C")
        else { return nil }
        return Symbols(
            createService: unsafeBitCast(create, to: CreateService.self),
            copyEDID: unsafeBitCast(copyEDID, to: CopyEDID.self),
            writeI2C: unsafeBitCast(writeI2C, to: WriteI2C.self),
            readI2C: unsafeBitCast(readI2C, to: ReadI2C.self))
    }

    private nonisolated static func withMatchingService<T>(
        for target: DisplayDDC.Target,
        _ body: (CFTypeRef, Symbols) -> T
    ) -> T? {
        guard let symbols = resolveSymbols() else { return nil }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator)
        guard status == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var services: [CFTypeRef] = []
        var identities: [DisplayDDC.Identity?] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(
                entry, "Location" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String
            guard location == "External",
                let service = symbols.createService(kCFAllocatorDefault, entry)?.takeRetainedValue()
            else { continue }
            var edidRef: CFData?
            let identity: DisplayDDC.Identity?
            if symbols.copyEDID(service, &edidRef) == KERN_SUCCESS, let data = edidRef as Data? {
                identity = DisplayDDC.parseEDID(data)
            } else {
                identity = nil
            }
            services.append(service)
            identities.append(identity)
        }
        guard let index = DisplayDDC.matchIndex(for: target, in: identities) else { return nil }
        return body(services[index], symbols)
    }
}
