import Foundation

struct HyperScrollEngine: Sendable {
    enum Decision: Equatable, Sendable {
        case pass
        case suppress
    }

    struct Adjustment: Equatable, Sendable {
        var zone: HyperScrollZone
        var delta: Double
    }

    struct MediaStep: Equatable, Sendable {
        var up: Bool
        var fine: Bool
    }

    struct Result: Equatable, Sendable {
        var decision: Decision
        var adjustment: Adjustment?
        var marksHyperUsed = false
        var gestureEnded = false
    }

    private enum Phase {
        static let began: UInt32 = 1
        static let changed: UInt32 = 2
        static let ended: UInt32 = 4
        static let cancelled: UInt32 = 8
        static let mayBegin: UInt32 = 128
        static let momentumEnded: UInt32 = 3
    }

    static let fullSweepPoints: Double = 384
    static let coarseStep: Double = 1.0 / 16.0
    static let fineStep: Double = 1.0 / 64.0
    static let mouseNotchStep: Double = 1.0 / 32.0
    static let maxSingleTickDelta: Double = 0.08
    /// Capped to one coarse step so stopping or lifting fingers never leaves a queued tail.
    static let maxBufferedDelta: Double = coarseStep

    private(set) var touchLockedZone: HyperScrollZone?
    private(set) var activeGestureZone: HyperScrollZone?
    private(set) var isSuppressingMomentum = false

    /// Accumulates signed delta, resetting on direction reversal so reversals have zero deadzone.
    static func accumulate(_ delta: Double, into pending: inout Double) {
        if pending != 0, (pending > 0) != (delta > 0) {
            pending = 0
        }
        pending = min(max(pending + delta, -maxBufferedDelta), maxBufferedDelta)
    }

    /// Pops one step; `allowFineSteps = false` forces 1/16 steps so Bluetooth AVRCP never queues.
    static func popMediaStep(
        from pending: inout Double, allowFineSteps: Bool = true
    ) -> MediaStep? {
        let magnitude = abs(pending)
        let minimum = allowFineSteps ? fineStep : coarseStep
        guard magnitude >= minimum else { return nil }
        let up = pending > 0
        if !allowFineSteps || magnitude >= coarseStep {
            pending = 0
            return MediaStep(up: up, fine: false)
        }
        pending += up ? -fineStep : fineStep
        return MediaStep(up: up, fine: true)
    }

    mutating func reset() {
        touchLockedZone = nil
        activeGestureZone = nil
        isSuppressingMomentum = false
    }

    /// Preserves momentum suppression across Hyper release so coasting never jolts the window.
    mutating func endHyperHold() {
        if activeGestureZone != nil { isSuppressingMomentum = true }
        touchLockedZone = nil
        activeGestureZone = nil
    }

    mutating func updateTouches(normalizedXs: [Double]) {
        if normalizedXs.count >= 2 {
            guard touchLockedZone == nil else { return }
            let mean = normalizedXs.reduce(0, +) / Double(normalizedXs.count)
            touchLockedZone = HyperScrollZone.zone(atNormalizedX: mean)
        } else if normalizedXs.isEmpty, activeGestureZone == nil {
            touchLockedZone = nil
        }
    }

    mutating func handleScroll(
        isHyperActive: Bool,
        isContinuous: Bool,
        scrollPhase: UInt32,
        momentumPhase: UInt32,
        pointDeltaY: Double,
        lineDeltaY: Int64,
        isDirectionInverted: Bool
    ) -> Result {
        if momentumPhase != 0 {
            guard isSuppressingMomentum else { return Result(decision: .pass) }
            if momentumPhase == Phase.momentumEnded { isSuppressingMomentum = false }
            return Result(decision: .suppress)
        }
        isSuppressingMomentum = false

        guard isHyperActive else {
            activeGestureZone = nil
            return Result(decision: .pass)
        }

        if !isContinuous {
            let delta = mouseDelta(
                pointDeltaY: pointDeltaY, lineDeltaY: lineDeltaY,
                isDirectionInverted: isDirectionInverted)
            let adjustment = delta == 0 ? nil : Adjustment(zone: .volume, delta: delta)
            return Result(decision: .suppress, adjustment: adjustment, marksHyperUsed: true)
        }

        if scrollPhase == Phase.mayBegin {
            return Result(decision: .suppress)
        }
        if scrollPhase == Phase.ended || scrollPhase == Phase.cancelled {
            let wasActive = activeGestureZone != nil || touchLockedZone != nil
            activeGestureZone = nil
            touchLockedZone = nil
            if wasActive { isSuppressingMomentum = true }
            return Result(decision: wasActive ? .suppress : .pass, gestureEnded: wasActive)
        }

        if scrollPhase == Phase.began {
            activeGestureZone = touchLockedZone
            if activeGestureZone == nil, pointDeltaY == 0 {
                return Result(decision: .suppress, marksHyperUsed: true)
            }
        }

        let resolvedZone = activeGestureZone ?? touchLockedZone ?? .volume
        activeGestureZone = resolvedZone
        let delta = continuousDelta(
            pointDeltaY: pointDeltaY, isDirectionInverted: isDirectionInverted)
        let adjustment = delta == 0 ? nil : Adjustment(zone: resolvedZone, delta: delta)
        return Result(decision: .suppress, adjustment: adjustment, marksHyperUsed: true)
    }

    private func continuousDelta(pointDeltaY: Double, isDirectionInverted: Bool) -> Double {
        let physicalUp = isDirectionInverted ? -pointDeltaY : pointDeltaY
        return clampDelta(physicalUp / Self.fullSweepPoints)
    }

    private func mouseDelta(
        pointDeltaY: Double, lineDeltaY: Int64, isDirectionInverted: Bool
    ) -> Double {
        let raw: Double
        if lineDeltaY != 0 {
            raw = Double(lineDeltaY) * Self.mouseNotchStep
        } else {
            raw = pointDeltaY / Self.fullSweepPoints
        }
        let physicalUp = isDirectionInverted ? -raw : raw
        return clampDelta(physicalUp)
    }

    private func clampDelta(_ delta: Double) -> Double {
        min(max(delta, -Self.maxSingleTickDelta), Self.maxSingleTickDelta)
    }
}
