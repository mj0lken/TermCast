import Carbon.HIToolbox
import CoreGraphics
import Foundation

@main
@MainActor
struct HyperScrollTests {
    static var failures = 0

    static func check(_ name: String, _ condition: Bool) {
        if !condition {
            failures += 1
            print("FAIL \(name)")
        }
    }

    static func main() {
        zonesAndStepping()
        touchDownLockIn()
        directionNormalization()
        mouseWheelFallback()
        deferredTouchBeforeFirstDelta()
        momentumIsolation()
        cancelsQuickPressOnScroll()
        cursorDisplayBrightnessIsolation()
        edidAndDDCPackets()

        print("Hyper scroll: \(failures) failures")
        if failures != 0 { exit(1) }
    }

    static func zonesAndStepping() {
        check(
            "left third maps to screen brightness",
            HyperScrollZone.zone(atNormalizedX: 0.0) == .screenBrightness)
        check(
            "just below 1/3 stays screen brightness",
            HyperScrollZone.zone(atNormalizedX: 0.33) == .screenBrightness)
        check(
            "middle third maps to keyboard brightness",
            HyperScrollZone.zone(atNormalizedX: 0.5) == .keyboardBrightness)
        check(
            "right third maps to volume",
            HyperScrollZone.zone(atNormalizedX: 0.67) == .volume)
        check(
            "right edge maps to volume",
            HyperScrollZone.zone(atNormalizedX: 1.0) == .volume)

        var pending = 0.0
        HyperScrollEngine.accumulate(0.02, into: &pending)
        let fineUp = HyperScrollEngine.popMediaStep(from: &pending)
        check("gentle glide pops a 1/64 fine step", fineUp == .init(up: true, fine: true))
        check("sub-1/64 remainder waits for next delta", HyperScrollEngine.popMediaStep(from: &pending) == nil)

        HyperScrollEngine.accumulate(0.08, into: &pending)
        let coarseUp = HyperScrollEngine.popMediaStep(from: &pending)
        check("fast swipe pops a 1/16 coarse step", coarseUp == .init(up: true, fine: false))
        check(
            "coarse step trims leftover carry so release never runs on",
            HyperScrollEngine.popMediaStep(from: &pending) == nil)

        // Reversing direction clears positive remainder so downward pull responds immediately.
        HyperScrollEngine.accumulate(-0.02, into: &pending)
        let reverseDown = HyperScrollEngine.popMediaStep(from: &pending)
        check("direction reversal responds with zero deadzone", reverseDown == .init(up: false, fine: true))

        // Bluetooth mode skips 1/64 fine steps so bluetoothaudiod never builds a packet backlog.
        var btPending = 0.0
        HyperScrollEngine.accumulate(0.03, into: &btPending)
        check(
            "Bluetooth mode waits until a full 1/16 step is reached",
            HyperScrollEngine.popMediaStep(from: &btPending, allowFineSteps: false) == nil)
        HyperScrollEngine.accumulate(0.04, into: &btPending)
        check(
            "Bluetooth mode emits one 1/16 step and clears carry",
            HyperScrollEngine.popMediaStep(from: &btPending, allowFineSteps: false)
                == .init(up: true, fine: false) && btPending == 0)
    }

    static func touchDownLockIn() {
        var engine = HyperScrollEngine()
        engine.updateTouches(normalizedXs: [0.10, 0.20])
        check("two-finger touch locks left zone", engine.touchLockedZone == .screenBrightness)

        let began = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 1, momentumPhase: 0,
            pointDeltaY: 24, lineDeltaY: 2, isDirectionInverted: false)
        check("began adjusts screen brightness", began.adjustment?.zone == .screenBrightness)
        check("began suppresses scroll", began.decision == .suppress)

        // Drift sideways across middle and right thirds mid-gesture.
        engine.updateTouches(normalizedXs: [0.50, 0.60])
        let midDrift = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 2, momentumPhase: 0,
            pointDeltaY: 24, lineDeltaY: 2, isDirectionInverted: false)
        check(
            "sideways drift keeps initial screen brightness lock",
            midDrift.adjustment?.zone == .screenBrightness)

        engine.updateTouches(normalizedXs: [0.80, 0.90])
        let rightDrift = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 2, momentumPhase: 0,
            pointDeltaY: 24, lineDeltaY: 2, isDirectionInverted: false)
        check("further drift still keeps initial lock", rightDrift.adjustment?.zone == .screenBrightness)

        let ended = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 4, momentumPhase: 0,
            pointDeltaY: 0, lineDeltaY: 0, isDirectionInverted: false)
        check(
            "ended suppresses, flags gestureEnded, and unlocks for next gesture",
            ended.decision == .suppress && ended.gestureEnded)

        engine.updateTouches(normalizedXs: [0.45, 0.55])
        let middle = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 1, momentumPhase: 0,
            pointDeltaY: 24, lineDeltaY: 2, isDirectionInverted: false)
        check(
            "new touch-down in middle locks keyboard backlight",
            middle.adjustment?.zone == .keyboardBrightness)
    }

    static func directionNormalization() {
        var engine = HyperScrollEngine()
        engine.updateTouches(normalizedXs: [0.75, 0.85])

        let traditionalUp = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 1, momentumPhase: 0,
            pointDeltaY: 24, lineDeltaY: 2, isDirectionInverted: false)
        check("traditional upward scroll increases level", (traditionalUp.adjustment?.delta ?? 0) > 0)

        let naturalUp = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 2, momentumPhase: 0,
            pointDeltaY: -24, lineDeltaY: -2, isDirectionInverted: true)
        check("natural upward finger push also increases level", (naturalUp.adjustment?.delta ?? 0) > 0)

        let naturalDown = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 2, momentumPhase: 0,
            pointDeltaY: 24, lineDeltaY: 2, isDirectionInverted: true)
        check("natural downward finger pull decreases level", (naturalDown.adjustment?.delta ?? 0) < 0)
    }

    static func mouseWheelFallback() {
        var engine = HyperScrollEngine()
        let wheelUp = engine.handleScroll(
            isHyperActive: true, isContinuous: false, scrollPhase: 0, momentumPhase: 0,
            pointDeltaY: 10, lineDeltaY: 1, isDirectionInverted: false)
        check("notched mouse wheel targets volume without touches", wheelUp.adjustment?.zone == .volume)
        check("notched mouse wheel suppresses page scroll", wheelUp.decision == .suppress)
        check("notched mouse wheel marks Hyper hold used", wheelUp.marksHyperUsed)
        check(
            "notched mouse wheel steps by mouseNotchStep",
            abs((wheelUp.adjustment?.delta ?? 0) - HyperScrollEngine.mouseNotchStep) < 1e-9)

        let passthrough = engine.handleScroll(
            isHyperActive: false, isContinuous: false, scrollPhase: 0, momentumPhase: 0,
            pointDeltaY: 10, lineDeltaY: 1, isDirectionInverted: false)
        check(
            "mouse wheel without Hyper passes through",
            passthrough.decision == .pass && passthrough.adjustment == nil)
    }

    static func deferredTouchBeforeFirstDelta() {
        var engine = HyperScrollEngine()
        let zeroBegan = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 1, momentumPhase: 0,
            pointDeltaY: 0, lineDeltaY: 0, isDirectionInverted: true)
        check(
            "zero-delta began before touch frame suppresses without premature fallback",
            zeroBegan.decision == .suppress && zeroBegan.adjustment == nil)

        engine.updateTouches(normalizedXs: [0.40, 0.50])
        let changed = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 2, momentumPhase: 0,
            pointDeltaY: -24, lineDeltaY: -2, isDirectionInverted: true)
        check(
            "arriving touch frame locks middle zone on first delta",
            changed.adjustment?.zone == .keyboardBrightness)

        // Magic Mouse continuous scroll has no trackpad contacts, so it falls back to volume.
        var magicMouse = HyperScrollEngine()
        let magicScroll = magicMouse.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 2, momentumPhase: 0,
            pointDeltaY: -24, lineDeltaY: -2, isDirectionInverted: true)
        check(
            "continuous scroll without trackpad contacts falls back to volume",
            magicScroll.adjustment?.zone == .volume)
    }

    static func momentumIsolation() {
        var engine = HyperScrollEngine()

        // Pre-existing page momentum before Hyper was pressed must pass through untouched.
        let priorCoast = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 0, momentumPhase: 2,
            pointDeltaY: -30, lineDeltaY: -3, isDirectionInverted: true)
        check(
            "coasting momentum from prior scroll passes through",
            priorCoast.decision == .pass && priorCoast.adjustment == nil)

        // Trailing momentum from an intercepted swipe stays suppressed after Hyper release.
        engine.updateTouches(normalizedXs: [0.1, 0.2])
        _ = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 1, momentumPhase: 0,
            pointDeltaY: -24, lineDeltaY: -2, isDirectionInverted: true)
        _ = engine.handleScroll(
            isHyperActive: true, isContinuous: true, scrollPhase: 4, momentumPhase: 0,
            pointDeltaY: 0, lineDeltaY: 0, isDirectionInverted: true)
        engine.endHyperHold()

        let coast = engine.handleScroll(
            isHyperActive: false, isContinuous: true, scrollPhase: 0, momentumPhase: 2,
            pointDeltaY: -20, lineDeltaY: -2, isDirectionInverted: true)
        check(
            "trailing momentum after Hyper release is suppressed without extra adjustment",
            coast.decision == .suppress && coast.adjustment == nil)

        let coastEnd = engine.handleScroll(
            isHyperActive: false, isContinuous: true, scrollPhase: 0, momentumPhase: 3,
            pointDeltaY: 0, lineDeltaY: 0, isDirectionInverted: true)
        check(
            "momentum end is suppressed and clears suppression",
            coastEnd.decision == .suppress && !engine.isSuppressingMomentum)
    }

    static func cancelsQuickPressOnScroll() {
        let route = HyperKeyPhysicalKey.capsLock.route(secureInputCompatible: false)!
        var hyper = HyperKeyEngine(route: route)
        _ = hyper.handle(type: .keyDown, keyCode: route.tapKeyCode, flags: 0, at: 0)
        hyper.markUsed()
        let release = hyper.handle(type: .keyUp, keyCode: route.tapKeyCode, flags: 0, at: 0.12)
        check("scrolling during Hyper hold suppresses Quick Press on release", release.effect == nil)
    }

    static func cursorDisplayBrightnessIsolation() {
        var clock: TimeInterval = 1.0
        var hoveredDisplay: CGDirectDisplayID? = 10
        var displaySteps: [(CGDirectDisplayID, Double)] = []
        var postedKeys: [MediaKeyPoster.Key] = []

        let runner = HyperScrollRunner(
            now: { clock },
            cursorDisplayID: { hoveredDisplay },
            stepDisplayBrightness: { id, delta in displaySteps.append((id, delta)) },
            postMediaKey: { key, _ in postedKeys.append(key) })

        runner.apply(HyperScrollEngine.Adjustment(zone: .screenBrightness, delta: 0.02))
        check(
            "brightness scroll targets display under cursor without posting media keys",
            displaySteps.count == 1 && displaySteps[0].0 == 10 && postedKeys.isEmpty)

        // Mid-gesture cursor drift must keep targeting the display locked at gesture start.
        hoveredDisplay = 20
        clock += 0.02
        runner.apply(HyperScrollEngine.Adjustment(zone: .screenBrightness, delta: 0.02))
        check(
            "brightness scroll stays locked to initial cursor display mid-gesture",
            displaySteps.count == 2 && displaySteps[1].0 == 10)

        // Lifting fingers resets the lock so the next scroll targets the new cursor display.
        runner.resetGesture()
        clock += 0.02
        runner.apply(HyperScrollEngine.Adjustment(zone: .screenBrightness, delta: -0.02))
        check(
            "new gesture targets the updated display under cursor",
            displaySteps.count == 3 && displaySteps[2].0 == 20 && displaySteps[2].1 < 0)
    }

    static func edidAndDDCPackets() {
        var edid = [UInt8](repeating: 0, count: 128)
        edid[0...7] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        edid[8] = 0x10
        edid[9] = 0xAC
        edid[10] = 0xD0
        edid[11] = 0xA0
        edid[12] = 0x78
        edid[13] = 0x56
        edid[14] = 0x34
        edid[15] = 0x12

        let parsed = DisplayDDC.parseEDID(Data(edid))
        check(
            "EDID parses big-endian vendor and little-endian model/serial",
            parsed == DisplayDDC.Identity(
                vendorID: 0x10AC, modelID: 0xA0D0, serialNumber: 0x1234_5678))

        let monitorA = DisplayDDC.Identity(vendorID: 0x10AC, modelID: 0xA0D0, serialNumber: 100)
        let monitorB = DisplayDDC.Identity(vendorID: 0x10AC, modelID: 0xA0D0, serialNumber: 200)
        let targetB = DisplayDDC.Target(identity: monitorB, allowsSingleExternalFallback: false)
        check(
            "DDC matches exact serial among identical external monitor models",
            DisplayDDC.matchIndex(for: targetB, in: [monitorA, monitorB]) == 1)

        let zeroSerialMonitor = DisplayDDC.Identity(vendorID: 0x1E6D, modelID: 0x5B11, serialNumber: 0)
        let cgTarget = DisplayDDC.Target(
            identity: DisplayDDC.Identity(vendorID: 0x1E6D, modelID: 0x5B11, serialNumber: 99),
            allowsSingleExternalFallback: false)
        check(
            "DDC matches vendor+model when EDID numeric serial is zero",
            DisplayDDC.matchIndex(for: cgTarget, in: [monitorA, zeroSerialMonitor]) == 1)

        let write50 = DisplayDDC.makeBrightnessWritePacket(level: 0.5)
        check(
            "DDC write packet sets VCP 0x10 to 50% with valid XOR checksum",
            write50 == [0x84, 0x03, 0x10, 0x00, 50, 0x84 ^ 0x03 ^ 0x10 ^ 50 ^ 0x6E ^ 0x51])

        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x00]
        check(
            "DDC VCP reply parses 75/100 brightness",
            DisplayDDC.parseBrightnessReply(reply) == 0.75)
    }
}
