import Darwin
import Foundation
import ObjectiveC

/// Bridges `CoreBrightness` `KeyboardBrightnessClient` for built-in MacBook keyboard illumination.
@MainActor
final class KeyboardBacklightService {
    struct StepOutcome: Sendable, Equatable {
        let level: Double
        let isSuppressed: Bool
        let overshoot: Double
    }

    private static let fadeMilliseconds: Int32 = 45

    private var cachedKeyboardID: UInt64?
    private var cachedLevel: Double?

    func resetGesture() {
        cachedLevel = nil
    }

    func step(up: Bool, fine: Bool) -> StepOutcome? {
        let delta = (fine ? 1.0 / 64.0 : 1.0 / 16.0) * (up ? 1 : -1)
        return step(delta: delta)
    }

    func step(delta: Double) -> StepOutcome? {
        guard let bridge = CoreBrightnessBridge.shared else { return nil }
        let keyboardID = resolvedKeyboardID(using: bridge)
        guard let keyboardID else { return nil }

        if bridge.isSuppressed(keyboardID: keyboardID) {
            return StepOutcome(
                level: 0,
                isSuppressed: true,
                overshoot: delta >= 0 ? 1 : -1)
        }

        let current = cachedLevel ?? bridge.brightness(keyboardID: keyboardID) ?? 0
        let raw = current + delta
        let next = min(max(raw, 0), 1)
        let reference = max(abs(delta), 1.0 / 64.0)
        let overshoot: Double
        if raw < 0 {
            overshoot = -min(abs(raw) / reference, 1)
        } else if raw > 1 {
            overshoot = min((raw - 1) / reference, 1)
        } else {
            overshoot = 0
        }

        guard bridge.setBrightness(
            Float(next), fadeSpeed: Self.fadeMilliseconds, keyboardID: keyboardID
        ) else {
            cachedKeyboardID = nil
            cachedLevel = nil
            return nil
        }
        cachedLevel = next
        return StepOutcome(level: next, isSuppressed: false, overshoot: overshoot)
    }

    private func resolvedKeyboardID(using bridge: CoreBrightnessBridge) -> UInt64? {
        if let cachedKeyboardID { return cachedKeyboardID }
        let resolved = bridge.builtInKeyboardID()
        cachedKeyboardID = resolved
        return resolved
    }
}

@MainActor
private final class CoreBrightnessBridge {
    private typealias CopyIDsFn = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    private typealias BoolForIDFn = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias FloatForIDFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetBrightnessFn = @convention(c) (
        AnyObject, Selector, Float, Int32, Bool, UInt64
    ) -> Bool

    static let shared = CoreBrightnessBridge()

    private let client: NSObject
    private let copyIDsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
    private let isBuiltInSel = NSSelectorFromString("isKeyboardBuiltIn:")
    private let isSuppressedSel = NSSelectorFromString("isBacklightSuppressedOnKeyboard:")
    private let getBrightnessSel = NSSelectorFromString("brightnessForKeyboard:")
    private let setBrightnessSel = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")

    private let copyIDsFn: CopyIDsFn
    private let isBuiltInFn: BoolForIDFn
    private let isSuppressedFn: BoolForIDFn
    private let getBrightnessFn: FloatForIDFn
    private let setBrightnessFn: SetBrightnessFn

    private init?() {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard dlopen(path, RTLD_LAZY) != nil,
            let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type,
            let copyMethod = class_getInstanceMethod(clientClass, copyIDsSel),
            let builtInMethod = class_getInstanceMethod(clientClass, isBuiltInSel),
            let suppressedMethod = class_getInstanceMethod(clientClass, isSuppressedSel),
            let getMethod = class_getInstanceMethod(clientClass, getBrightnessSel),
            let setMethod = class_getInstanceMethod(clientClass, setBrightnessSel)
        else { return nil }

        client = clientClass.init()
        copyIDsFn = unsafeBitCast(method_getImplementation(copyMethod), to: CopyIDsFn.self)
        isBuiltInFn = unsafeBitCast(method_getImplementation(builtInMethod), to: BoolForIDFn.self)
        isSuppressedFn = unsafeBitCast(
            method_getImplementation(suppressedMethod), to: BoolForIDFn.self)
        getBrightnessFn = unsafeBitCast(method_getImplementation(getMethod), to: FloatForIDFn.self)
        setBrightnessFn = unsafeBitCast(
            method_getImplementation(setMethod), to: SetBrightnessFn.self)
    }

    func builtInKeyboardID() -> UInt64? {
        guard let rawArray = copyIDsFn(client, copyIDsSel)?.takeRetainedValue() as? [NSNumber],
            !rawArray.isEmpty
        else { return nil }
        let ids = rawArray.map(\.uint64Value)
        return ids.first { isBuiltInFn(client, isBuiltInSel, $0) } ?? ids.first
    }

    func isSuppressed(keyboardID: UInt64) -> Bool {
        isSuppressedFn(client, isSuppressedSel, keyboardID)
    }

    func brightness(keyboardID: UInt64) -> Double? {
        let value = getBrightnessFn(client, getBrightnessSel, keyboardID)
        guard value.isFinite, value >= 0 else { return nil }
        return min(max(Double(value), 0), 1)
    }

    func setBrightness(_ level: Float, fadeSpeed: Int32, keyboardID: UInt64) -> Bool {
        setBrightnessFn(client, setBrightnessSel, level, fadeSpeed, true, keyboardID)
    }
}
