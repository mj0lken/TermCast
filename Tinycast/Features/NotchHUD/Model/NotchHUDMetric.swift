import Foundation

/// Pure state, step math and symbol selection for the Notch HUD.
enum NotchHUDMetric: Sendable, Equatable {
    case volume(level: Double, muted: Bool)
    case screenBrightness(level: Double)
    case keyboardBacklight(level: Double, suppressed: Bool)
    case audioDeviceConnected(name: String, symbol: String, level: Double, muted: Bool)

    struct StepResult: Sendable, Equatable {
        let level: Double
        /// Signed boundary impulse in `[-1, 1]` when a step hits or pushes past `0` or `1`.
        let overshoot: Double
    }

    static let coarseStep: Double = 1.0 / 16.0
    static let fineStep: Double = 1.0 / 64.0
    static let dwellDuration: TimeInterval = 1.6
    static let toastDwellDuration: TimeInterval = 2.4
    static let overshootResetDelay: TimeInterval = 0.14

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    static func step(from current: Double, up: Bool, fine: Bool) -> StepResult {
        let magnitude = fine ? fineStep : coarseStep
        return step(from: current, delta: up ? magnitude : -magnitude)
    }

    static func step(from current: Double, delta: Double) -> StepResult {
        let start = clamp(current)
        guard delta.isFinite, delta != 0 else {
            return StepResult(level: start, overshoot: 0)
        }
        let raw = start + delta
        let clamped = clamp(raw)
        let reference = max(abs(delta), fineStep)
        let overshoot: Double
        if raw < 0 {
            overshoot = -min(abs(raw) / reference, 1)
        } else if raw > 1 {
            overshoot = min((raw - 1) / reference, 1)
        } else {
            overshoot = 0
        }
        return StepResult(level: clamped, overshoot: overshoot)
    }

    static func volumeSymbol(level: Double, muted: Bool) -> String {
        let clamped = clamp(level)
        if muted || clamped <= 0.001 { return "speaker.slash.fill" }
        if clamped < 1.0 / 3.0 { return "speaker.wave.1.fill" }
        if clamped < 2.0 / 3.0 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    static func audioDeviceSymbol(for deviceName: String) -> String {
        let folded = deviceName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if folded.contains("airpods max") { return "airpodsmax" }
        if folded.contains("airpods pro") { return "airpodspro" }
        if folded.contains("airpods") { return "airpods.gen3" }
        if folded.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    var symbol: String {
        switch self {
        case .volume(let level, let muted):
            Self.volumeSymbol(level: level, muted: muted)
        case .screenBrightness:
            "sun.max.fill"
        case .keyboardBacklight(_, let suppressed):
            suppressed ? "light.min" : "light.max"
        case .audioDeviceConnected(_, let symbol, _, _):
            symbol
        }
    }

    var effectiveLevel: Double {
        switch self {
        case .volume(let level, let muted), .audioDeviceConnected(_, _, let level, let muted):
            muted ? 0 : Self.clamp(level)
        case .screenBrightness(let level):
            Self.clamp(level)
        case .keyboardBacklight(let level, let suppressed):
            suppressed ? 0 : Self.clamp(level)
        }
    }

    var isToast: Bool {
        if case .audioDeviceConnected = self { return true }
        return false
    }

    var dwell: TimeInterval {
        isToast ? Self.toastDwellDuration : Self.dwellDuration
    }

    func percentageText(locale: Locale = .current) -> String {
        effectiveLevel.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}
