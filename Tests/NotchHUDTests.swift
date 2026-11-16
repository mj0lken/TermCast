import CoreGraphics
import Foundation

@main
@MainActor
struct NotchHUDTests {
    static let locale = Locale(identifier: "en_US")
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ actual: Double, _ expected: Double, _ message: String) {
        expect(abs(actual - expected) < 1e-9, "\(message) — got \(actual), want \(expected)")
    }

    static func expectCG(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        expect(abs(actual - expected) < 1e-6, "\(message) — got \(actual), want \(expected)")
    }

    static func main() {
        testStepMathAndOvershoot()
        testSymbolsAndPercentages()
        testNotchedGeometryAndMenuBarClamping()
        testNonNotchedFloatingPillFallback()
        testMediaKeyDecoding()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func testStepMathAndOvershoot() {
        expect(NotchHUDMetric.coarseStep, 0.0625, "coarse step is 1/16")
        expect(NotchHUDMetric.fineStep, 0.015625, "fine step is 1/64")

        let midUp = NotchHUDMetric.step(from: 0.5, up: true, fine: false)
        expect(midUp.level, 0.5625, "coarse step up from 50% lands on 56.25%")
        expect(midUp.overshoot, 0, "mid-range step has zero overshoot")

        let fineDown = NotchHUDMetric.step(from: 0.5, up: false, fine: true)
        expect(fineDown.level, 0.484375, "fine step down from 50% moves 1/64")
        expect(fineDown.overshoot, 0, "mid-range fine step has zero overshoot")

        let floorPush = NotchHUDMetric.step(from: 0, up: false, fine: false)
        expect(floorPush.level, 0, "pushing below zero clamps level at zero")
        expect(floorPush.overshoot, -1, "pushing below zero triggers full negative overshoot")

        let ceilingPush = NotchHUDMetric.step(from: 1, up: true, fine: true)
        expect(ceilingPush.level, 1, "pushing above one clamps level at one")
        expect(ceilingPush.overshoot, 1, "pushing above one triggers full positive overshoot")

        let partialCeiling = NotchHUDMetric.step(from: 0.96875, up: true, fine: false)
        expect(partialCeiling.level, 1, "near-ceiling coarse step clamps to 100%")
        expect(partialCeiling.overshoot, 0.5, "half-step past ceiling yields 0.5 overshoot")

        expect(NotchHUDMetric.clamp(.nan), 0, "NaN clamps safely to zero")
    }

    static func testSymbolsAndPercentages() {
        expect(
            NotchHUDMetric.volume(level: 0.8, muted: true).symbol == "speaker.slash.fill",
            "muted volume uses slashed speaker")
        expect(
            NotchHUDMetric.volume(level: 0, muted: false).symbol == "speaker.slash.fill",
            "zero volume uses slashed speaker")
        expect(
            NotchHUDMetric.volume(level: 0.15, muted: false).symbol == "speaker.wave.1.fill",
            "low volume uses wave 1")
        expect(
            NotchHUDMetric.volume(level: 0.5, muted: false).symbol == "speaker.wave.2.fill",
            "medium volume uses wave 2")
        expect(
            NotchHUDMetric.volume(level: 0.85, muted: false).symbol == "speaker.wave.3.fill",
            "high volume uses wave 3")

        expect(
            NotchHUDMetric.screenBrightness(level: 0.4).symbol == "sun.max.fill",
            "screen brightness uses sun glyph")
        expect(
            NotchHUDMetric.keyboardBacklight(level: 0.5, suppressed: false).symbol == "light.max",
            "active keyboard backlight uses light.max")
        expect(
            NotchHUDMetric.keyboardBacklight(level: 0.5, suppressed: true).symbol == "light.min",
            "suppressed keyboard backlight uses light.min")

        expect(
            NotchHUDMetric.audioDeviceSymbol(for: "Malcolm’s AirPods Pro") == "airpodspro",
            "AirPods Pro resolves dedicated glyph")
        expect(
            NotchHUDMetric.audioDeviceSymbol(for: "AirPods Max") == "airpodsmax",
            "AirPods Max resolves dedicated glyph")
        expect(
            NotchHUDMetric.audioDeviceSymbol(for: "Sony WH-1000XM5") == "headphones",
            "generic headset resolves headphones glyph")

        expect(
            NotchHUDMetric.volume(level: 0.5, muted: false).percentageText(locale: locale) == "50%",
            "50% formats cleanly")
        expect(
            NotchHUDMetric.volume(level: 0.75, muted: true).percentageText(locale: locale) == "0%",
            "muted effective percentage reads 0%")
    }

    static func testNotchedGeometryAndMenuBarClamping() {
        let macBook16 = NotchHUDGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
            safeAreaTop: 38,
            auxiliaryTopLeft: CGRect(x: 0, y: 1291, width: 918, height: 38),
            auxiliaryTopRight: CGRect(x: 1138, y: 1291, width: 918, height: 38))

        let rest = NotchHUDGeometry.resolve(screen: macBook16, overshoot: 0)
        expect(rest.isNotched, "MacBook screen with safeAreaTop > 0 resolves notched layout")
        expectCG(rest.panelFrame.maxY, 1329, "notched panel sits flush with screen.frame.maxY")
        expectCG(rest.panelFrame.height, 38, "notched panel height equals exact notchHeight")

        if case .notched(
            let notchOriginX, let notchWidth, let notchHeight,
            let leftWing, let rightWing, let earRadius, let innerRadius
        ) = rest.mode {
            expectCG(notchWidth, 220, "notch width matches auxiliary gap (1138 - 918)")
            expectCG(notchHeight, 38, "notch height matches safeAreaTop")
            expectCG(rest.panelFrame.minX + notchOriginX, 918, "notchOriginX locks onto leftAux.maxX")
            expectCG(leftWing, NotchHUDGeometry.idealLeftWingWidth, "spacious menu bar uses ideal left wing")
            expectCG(rightWing, NotchHUDGeometry.idealRightWingWidth, "spacious menu bar uses ideal right wing")
            expectCG(earRadius, 6, "top-shoulder concave ear radius is 6pt")
            expectCG(innerRadius, 14, "inner corner radius is 14pt")
        } else {
            expect(false, "expected notched mode")
        }

        let stretched = NotchHUDGeometry.resolve(screen: macBook16, overshoot: 1.0)
        expect(
            stretched.panelFrame == rest.panelFrame,
            "panelFrame stays fixed during rubber-band overshoot so WindowServer never reallocates")
        expectCG(stretched.wingStretch, 4, "full boundary overshoot stretches wings by +4pt")
        expectCG(stretched.trackCompression, 2, "full boundary overshoot compresses track by 2pt")

        let cramped = NotchHUDGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 640, height: 420),
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 388, width: 66, height: 32),
            auxiliaryTopRight: CGRect(x: 280, y: 388, width: 128, height: 32))
        let clamped = NotchHUDGeometry.resolve(screen: cramped)
        if case .notched(_, _, _, let leftWing, let rightWing, _, _) = clamped.mode {
            expect(leftWing < NotchHUDGeometry.idealLeftWingWidth, "narrow left aux clamps left wing")
            expect(rightWing < NotchHUDGeometry.idealRightWingWidth, "narrow right aux clamps right wing")
            expect(clamped.trackWidth >= NotchHUDGeometry.minimumTrackWidth, "track respects minimum width")
        } else {
            expect(false, "expected clamped notched mode")
        }

        let impossiblyNarrow = NotchHUDGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 500, height: 400),
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 368, width: 40, height: 32),
            auxiliaryTopRight: CGRect(x: 260, y: 368, width: 40, height: 32))
        expect(
            !NotchHUDGeometry.resolve(screen: impossiblyNarrow).isNotched,
            "impossibly narrow auxiliary regions fall back cleanly to floating pill")
    }

    static func testNonNotchedFloatingPillFallback() {
        let external = NotchHUDGeometry.ScreenMetrics(
            frame: CGRect(x: 2056, y: 0, width: 2560, height: 1440),
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil)
        let layout = NotchHUDGeometry.resolve(screen: external)
        expect(!layout.isNotched, "safeAreaTop == 0 uses Dynamic Island floating pill fallback")
        expectCG(
            layout.panelFrame.maxY, 1440 - NotchHUDGeometry.floatingTopOffset,
            "floating pill sits 8pt below screen.frame.maxY")
        expectCG(
            layout.panelFrame.midX, external.frame.midX,
            "floating pill centers horizontally on the cursor display")
    }

    static func testMediaKeyDecoding() {
        let soundUpDown = (Int(0) << 16) | (0x0A << 8)
        let decoded = MediaKeyEvent.decode(subtype: 8, data1: soundUpDown)
        expect(
            decoded == MediaKeyEvent(key: .soundUp, phase: .down, isRepeat: false, isFineStep: false),
            "unmodified soundUp key-down decodes as coarse step")

        let fineRepeat = MediaKeyEvent.decode(
            subtype: 8, data1: (Int(2) << 16) | (0x0A << 8) | 0x1, shift: true, option: true)
        expect(
            fineRepeat == MediaKeyEvent(key: .brightnessUp, phase: .down, isRepeat: true, isFineStep: true),
            "Shift+Option brightness repeat decodes as fine step")

        let illuminationUp = MediaKeyEvent.decode(subtype: 8, data1: (Int(21) << 16) | (0x0B << 8))
        expect(
            illuminationUp == MediaKeyEvent(
                key: .illuminationUp, phase: .up, isRepeat: false, isFineStep: false),
            "illumination key-up decodes so key-up is swallowed cleanly too")

        expect(
            MediaKeyEvent.decode(subtype: 8, data1: soundUpDown, option: true) == nil,
            "bare Option + media key passes through so macOS opens System Settings")
        expect(
            MediaKeyEvent.decode(subtype: 8, data1: (Int(16) << 16) | (0x0A << 8)) == nil,
            "Play/Pause (16) is never intercepted by the HUD tap")
        expect(
            MediaKeyEvent.decode(subtype: 4, data1: soundUpDown) == nil,
            "non-aux subtypes are ignored")
    }
}
