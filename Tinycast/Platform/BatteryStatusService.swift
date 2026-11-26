import CoreFoundation
import Foundation
import IOKit.ps

private func batteryPowerSourceCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let target = Unmanaged<BatteryStatusService.CallbackBox>.fromOpaque(context).takeUnretainedValue()
    target.notify()
}

/// Event-driven battery and charger monitor backed by `IOPSNotificationCreateRunLoopSource`.
@MainActor
@Observable
final class BatteryStatusService {
    struct Status: Sendable, Equatable {
        let hasBattery: Bool
        let percentage: Int
        let isPluggedIn: Bool
        let isCharging: Bool
    }

    fileprivate final class CallbackBox: Sendable {
        let notify: @Sendable () -> Void
        init(notify: @escaping @Sendable () -> Void) {
            self.notify = notify
        }
    }

    private(set) var status = Status(hasBattery: false, percentage: 100, isPluggedIn: true, isCharging: false)

    /// Whether this Mac has a battery at all, for a caller that needs no updates.
    static var hasInternalBattery: Bool { readStatus().hasBattery }

    @ObservationIgnored var onPowerSourceChanged: ((Status) -> Void)?

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var callbackBox: CallbackBox?
    @ObservationIgnored private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        status = Self.readStatus()

        let box = CallbackBox { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleUpdate()
            }
        }
        callbackBox = box
        if let unmanaged = IOPSNotificationCreateRunLoopSource(
            batteryPowerSourceCallback,
            Unmanaged.passUnretained(box).toOpaque()
        ) {
            let source = unmanaged.takeRetainedValue()
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        callbackBox = nil
    }

    private func handleUpdate() {
        let previous = status
        let next = Self.readStatus()
        guard next != previous else { return }
        status = next
        if next.hasBattery, next.isPluggedIn != previous.isPluggedIn {
            onPowerSourceChanged?(next)
        }
    }

    private static func readStatus() -> Status {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
            !list.isEmpty
        else {
            return Status(hasBattery: false, percentage: 100, isPluggedIn: true, isCharging: false)
        }

        for source in list {
            guard
                let desc = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                let type = desc[kIOPSTypeKey as String] as? String,
                type == (kIOPSInternalBatteryType as String)
            else { continue }

            let current = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maxCap = max(desc[kIOPSMaxCapacityKey as String] as? Int ?? 100, 1)
            let pct = min(max(Int((Double(current) / Double(maxCap) * 100).rounded()), 0), 100)
            let powerState = desc[kIOPSPowerSourceStateKey as String] as? String ?? ""
            let isPlugged = powerState == (kIOPSACPowerValue as String)
            let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
            return Status(
                hasBattery: true,
                percentage: pct,
                isPluggedIn: isPlugged,
                isCharging: isCharging)
        }

        return Status(hasBattery: false, percentage: 100, isPluggedIn: true, isCharging: false)
    }
}
