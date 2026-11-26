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
        testOpenTrayAndSensorGeometry()
        testShelfItems()
        testNowPlayingSnapshot()
        testNowPlayingSeek()
        testNowPlayingRelayMessage()
        testNowPlayingRelayArtworkCarryOver()
        testWeekStrip()
        testNoticeMetric()
        testLiveActivityPriority()
        testLiveWingWidths()
        testLiveGeometry()
        testMeetingCountdown()
        testTerminalSessions()
        testTimerPreset()
        testNotchShortcuts()

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
            NotchHUDMetric.keyboardBacklight(level: 0.5).symbol == "light.max",
            "lit keyboard backlight uses light.max")
        expect(
            NotchHUDMetric.keyboardBacklight(level: 0).symbol == "light.min",
            "unlit keyboard backlight uses light.min")

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

    static func testOpenTrayAndSensorGeometry() {
        let macBook = NotchHUDGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
            safeAreaTop: 38,
            auxiliaryTopLeft: CGRect(x: 0, y: 1291, width: 918, height: 38),
            auxiliaryTopRight: CGRect(x: 1138, y: 1291, width: 918, height: 38))

        let sensor = NotchHUDGeometry.sensorFrame(for: macBook)
        expectCG(sensor.minX, 918, "notched sensor starts at leftAux.maxX")
        expectCG(sensor.width, 220, "notched sensor spans only the dead camera housing")
        expectCG(sensor.maxY, 1329, "notched sensor sits flush at screen.frame.maxY")

        let tray = NotchHUDGeometry.resolveOpenTray(screen: macBook)
        expect(tray.isNotched, "notched screen resolves notched open tray")
        expectCG(tray.panelFrame.maxY, 1329, "open tray stays anchored to screen.frame.maxY")
        expectCG(tray.headerHeight, 38, "open tray header height matches physical notch height")
        expectCG(tray.panelFrame.minX + tray.notchOriginX, 918, "open tray notchOriginX locks to cutout")
    }

    static func testShelfItems() {
        let link = NotchShelfItem(kind: .link(URL(string: "https://www.blazoer.com/products/ring-cobalt")!))
        expect(link.displayTitle.contains("www.blazoer.com"), "link displays host on first line")

        let duplicate = NotchShelfItem(kind: .link(URL(string: "https://www.blazoer.com/products/ring-cobalt")!))
        let file = NotchShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/proposal-final-2026-deck.pdf")))
        let list = NotchShelfItem.inserting([duplicate], into: [file, link])
        expect(list.count == 2, "reinserting an existing link deduplicates instead of duplicating")
        expect(list.first?.id == duplicate.id, "reinserted item moves to the front of the shelf")
    }

    static func testNowPlayingSnapshot() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        let playing = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: "Album",
            duration: 200,
            elapsedAtAnchor: 10,
            anchorDate: anchor,
            playbackRate: 1.0,
            isPlaying: true,
            clientBundleID: "com.apple.Music",
            clientName: "Music",
            artworkID: nil,
            artworkData: nil)
        expect(playing.liveElapsed(at: anchor.addingTimeInterval(15)), 25, "playing advances elapsed time")
        expect(playing.progress(at: anchor.addingTimeInterval(90)), 0.5, "100s / 200s = 50% progress")
        expect(NowPlayingSnapshot.formatTimestamp(6) == "0:06", "6s formats as 0:06")
        expect(NowPlayingSnapshot.formatTimestamp(3725) == "1:02:05", "hour+ formats with hours")
    }

    static func testNowPlayingSeek() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        let playing = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: "Album",
            duration: 200,
            elapsedAtAnchor: 10,
            anchorDate: anchor,
            playbackRate: 1.0,
            isPlaying: true,
            clientBundleID: "com.apple.Music",
            clientName: "Music",
            artworkID: "art",
            artworkData: Data([1]))
        let later = anchor.addingTimeInterval(30)

        let sought = playing.seeking(to: 120, at: later)
        expect(sought.liveElapsed(at: later), 120, "seeking re-anchors elapsed time at the seek")
        expect(sought.liveElapsed(at: later.addingTimeInterval(5)), 125, "playback continues from the seek")
        expect(sought.title == "Track" && sought.artworkData == Data([1]), "seeking keeps the track")
        expect(playing.seeking(to: 900, at: later).liveElapsed(at: later), 200, "a seek clamps to duration")
        expect(playing.seeking(to: -4, at: later).liveElapsed(at: later), 0, "a seek clamps to zero")
    }

    static func relayMessage(_ json: String) -> NowPlayingRelayMessage? {
        NowPlayingRelayMessage.decode(line: Data(json.utf8))
    }

    static func testNowPlayingRelayMessage() {
        let received = Date(timeIntervalSince1970: 5_000)
        let line = """
            {"isPlaying":true,"bundleID":"com.apple.WebKit.GPU","parentBundleID":"com.apple.Safari",\
            "appName":"Safari","artworkID":"a1","title":"Song","artist":"Band","album":"LP",\
            "duration":240,"elapsed":12.5,"rate":1,"timestamp":4990}
            """
        let snapshot = relayMessage(line)?.snapshot(carrying: nil, receivedAt: received)
        expect(snapshot?.title == "Song", "relay title decodes")
        expect(snapshot?.artist == "Band" && snapshot?.album == "LP", "relay artist and album decode")
        expect(snapshot?.isPlaying == true, "relay playing state decodes")
        expect(snapshot?.clientBundleID == "com.apple.Safari", "a helper process reports its parent app")
        expect(snapshot?.clientName == "Safari", "relay source name decodes")
        expect(snapshot?.liveElapsed(at: received) ?? 0, 22.5, "elapsed is anchored at the relay timestamp")

        let direct = relayMessage(#"{"isPlaying":false,"bundleID":"com.spotify.client","title":"Song"}"#)?
            .snapshot(carrying: nil, receivedAt: received)
        expect(direct?.clientBundleID == "com.spotify.client", "an app without a parent reports itself")
        expect(direct?.isPlaying == false, "a paused relay line is paused")
        expect(direct?.anchorDate == received, "a line without a timestamp anchors at its arrival")
        expect(direct?.liveElapsed(at: received.addingTimeInterval(60)) ?? -1, 0, "paused time stands still")

        let blankParent = relayMessage(
            #"{"bundleID":"com.spotify.client","parentBundleID":"","title":"Song"}"#)?
            .snapshot(carrying: nil, receivedAt: received)
        expect(blankParent?.clientBundleID == "com.spotify.client", "an empty parent falls back to the app")

        expect(relayMessage("{}")?.snapshot(carrying: nil, receivedAt: received) == nil, "an empty line is silence")
        expect(
            relayMessage(#"{"isPlaying":true,"title":"  "}"#)?.snapshot(carrying: nil, receivedAt: received) == nil,
            "a blank title is silence")
        expect(relayMessage("not json") == nil, "a malformed line is rejected")
    }

    static func testNowPlayingRelayArtworkCarryOver() {
        let received = Date(timeIntervalSince1970: 5_000)
        let artwork = Data([0xFF, 0xD8, 0xFF])
        let withArt = relayMessage(
            #"{"title":"Song","artworkID":"a1","artwork":"\#(artwork.base64EncodedString())"}"#)?
            .snapshot(carrying: nil, receivedAt: received)
        expect(withArt?.artworkData == artwork, "relay artwork decodes from base64")

        let sameArt = relayMessage(#"{"title":"Song","artworkID":"a1","isPlaying":true}"#)?
            .snapshot(carrying: withArt, receivedAt: received)
        expect(sameArt?.artworkData == artwork, "a line for the same artwork keeps the image already sent")

        let nextTrack = relayMessage(#"{"title":"Other","artworkID":"b2"}"#)?
            .snapshot(carrying: sameArt, receivedAt: received)
        expect(nextTrack?.artworkData == nil, "a new track never shows the previous artwork")

        let unidentified = relayMessage(#"{"title":"Other"}"#)?
            .snapshot(carrying: withArt, receivedAt: received)
        expect(unidentified?.artworkData == nil, "a line without an artwork identity carries nothing over")
    }

    static func testWeekStrip() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let ref = Date(timeIntervalSince1970: 1_794_830_400)
        let built = NotchWeekStrip.build(around: ref, calendar: calendar, locale: locale)
        expect(built.days.count == 6, "week strip builds 6 day slots (-2..+3)")
        expect(built.days[2].isToday, "slot index 2 (offset 0) is marked as today")
    }

    static func testNoticeMetric() {
        let notice = NotchHUDMetric.notice(symbol: "globe", text: "Swedish")
        expect(notice.isToast, "a notice dwells as long as the other toasts")
        expect(notice.symbol == "globe", "a notice shows the symbol it was given")
        expect(notice.effectiveLevel, 0, "a notice has no level to draw")
    }

    static func meeting(
        _ id: String, startingIn minutes: Double, lasting duration: Double = 30,
        isAllDay: Bool = false, isDeclined: Bool = false, from now: Date
    ) -> MeetingEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return MeetingEvent(
            id: id, title: id, start: start, end: start.addingTimeInterval(duration * 60),
            isAllDay: isAllDay, isDeclined: isDeclined, calendarID: "cal", calendarName: "Work",
            calendarColor: nil, calendarItemID: id, link: nil)
    }

    static func testLiveActivityPriority() {
        let now = Date(timeIntervalSince1970: 10_000)
        let standup = meeting("standup", startingIn: 4, from: now)
        var inputs = NotchLiveInputs()
        expect(inputs.presentation(at: now).isEmpty, "nothing ongoing leaves the notch bare")

        inputs.isPlaying = true
        expect(inputs.presentation(at: now).activity == .nowPlaying, "playback alone shows now playing")

        inputs.runningTerminalCount = 2
        let withTerminal = inputs.presentation(at: now)
        expect(withTerminal.activity == .nowPlaying, "running sessions never take the wings from an activity")
        expect(withTerminal.terminalCount == 2, "running sessions are counted beside the activity")

        inputs.timerEnd = now.addingTimeInterval(60)
        expect(
            inputs.presentation(at: now).activity == .timer(end: now.addingTimeInterval(60)),
            "a running timer outranks playback")

        inputs.meeting = standup
        expect(inputs.presentation(at: now).activity == .meeting(standup), "an imminent meeting outranks a timer")

        inputs.isDictating = true
        expect(inputs.presentation(at: now).activity == .dictation, "dictation outranks everything")

        var expired = NotchLiveInputs()
        expired.timerEnd = now.addingTimeInterval(-1)
        expect(expired.presentation(at: now).isEmpty, "a timer that has ended is no longer shown")

        var terminalOnly = NotchLiveInputs()
        terminalOnly.runningTerminalCount = 1
        let sessions = terminalOnly.presentation(at: now)
        expect(sessions.activity == nil && !sessions.isEmpty, "running sessions alone still show")

        var captureOnly = NotchLiveInputs()
        captureOnly.capture.microphone = true
        let dot = captureOnly.presentation(at: now)
        expect(dot.activity == nil && !dot.isEmpty, "microphone use alone still shows its dot")
    }

    static func testLiveWingWidths() {
        let now = Date(timeIntervalSince1970: 10_000)
        var inputs = NotchLiveInputs()
        inputs.capture.camera = true
        let dotOnly = inputs.presentation(at: now)
        expectCG(dotOnly.leftWingWidth, 0, "a lone capture dot needs no left wing")
        expectCG(dotOnly.rightWingWidth, NotchLivePresentation.captureDotWidth, "a lone dot is one dot wide")

        var terminal = NotchLiveInputs()
        terminal.runningTerminalCount = 3
        let sessions = terminal.presentation(at: now)
        expectCG(
            sessions.leftWingWidth, NotchLivePresentation.terminalWidth,
            "running sessions alone are one compact glyph and count")
        expectCG(sessions.rightWingWidth, 0, "running sessions alone need no right wing")

        inputs.isPlaying = true
        let playing = inputs.presentation(at: now)
        expectCG(playing.leftWingWidth, NotchLivePresentation.glyphWidth, "an activity has one glyph on the left")
        expectCG(
            playing.rightWingWidth,
            NotchLiveActivity.nowPlaying.readoutWidth + NotchLivePresentation.captureDotWidth,
            "the capture dot widens the readout wing")

        inputs.runningTerminalCount = 1
        let both = inputs.presentation(at: now)
        expectCG(
            both.leftWingWidth,
            NotchLivePresentation.glyphWidth + NotchLivePresentation.terminalWidth,
            "running sessions widen the glyph wing")
        expect(
            both.leftWingWidth <= NotchHUDGeometry.liveMaxLeftWingWidth,
            "the widest left wing fits the window sized for it")
    }

    static func testLiveGeometry() {
        let notched = NotchHUDGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 38,
            auxiliaryTopLeft: CGRect(x: 0, y: 944, width: 650, height: 38),
            auxiliaryTopRight: CGRect(x: 862, y: 944, width: 650, height: 38))
        let narrow = NotchHUDGeometry.resolveLive(screen: notched, leftWing: 30, rightWing: 30)
        let wide = NotchHUDGeometry.resolveLive(screen: notched, leftWing: 72, rightWing: 66)
        expect(narrow != nil, "a notched display hosts live activities")
        expect(narrow?.panelFrame == wide?.panelFrame, "swapping activities never resizes the window")
        expect(
            (narrow?.panelFrame.maxY ?? 0) == notched.frame.maxY,
            "the live wings sit flush with the top of the display")
        if case .notched(_, let notchWidth, _, let left, let right, _, _)? = narrow?.mode {
            expectCG(notchWidth, 212, "the live layout spans the real notch")
            expectCG(left, 30, "the left wing is as wide as asked")
            expectCG(right, 30, "the right wing is as wide as asked")
        } else {
            expect(false, "the live layout is notched")
        }
        let oversized = NotchHUDGeometry.resolveLive(screen: notched, leftWing: 400, rightWing: 400)
        if case .notched(_, _, _, let left, let right, _, _)? = oversized?.mode {
            expectCG(left, NotchHUDGeometry.liveMaxLeftWingWidth, "the left wing is capped")
            expectCG(right, NotchHUDGeometry.liveMaxRightWingWidth, "the right wing is capped")
        } else {
            expect(false, "an oversized request still resolves")
        }

        let plain = NotchHUDGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
        expect(
            NotchHUDGeometry.resolveLive(screen: plain, leftWing: 30, rightWing: 30) == nil,
            "a display without a notch shows no live activity")
    }

    static func testMeetingCountdown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let countdown = NotchMeetingCountdown(leadMinutes: 10)
        let soon = meeting("soon", startingIn: 4, from: now)
        let later = meeting("later", startingIn: 90, from: now)
        let allDay = meeting("allDay", startingIn: -60, lasting: 1440, isAllDay: true, from: now)
        let declined = meeting("declined", startingIn: 2, isDeclined: true, from: now)
        let underway = meeting("underway", startingIn: -3, from: now)
        let stale = meeting("stale", startingIn: -12, from: now)
        let brief = meeting("brief", startingIn: -2, lasting: 3, from: now)

        expect(countdown.current(from: [later, soon], now: now) == soon, "a meeting inside the lead is shown")
        expect(countdown.current(from: [later], now: now) == nil, "a meeting beyond the lead is not shown yet")
        expect(countdown.current(from: [allDay, declined], now: now) == nil, "all-day and declined events never count down")
        expect(countdown.current(from: [underway], now: now) == underway, "a meeting just started stays for its grace")
        expect(countdown.current(from: [stale], now: now) == nil, "a meeting past its grace leaves the wings")

        expect(
            countdown.nextChange(from: [later], now: now) == later.start.addingTimeInterval(-600),
            "the next wake-up is when the lead window opens")
        expect(
            countdown.nextChange(from: [underway], now: now) == underway.start.addingTimeInterval(300),
            "an underway meeting wakes the notch when its grace ends")
        expect(
            countdown.nextChange(from: [brief], now: now) == brief.end,
            "the grace never outlives a short meeting")
        expect(countdown.nextChange(from: [], now: now) == nil, "no events schedule no wake-up")

        expect(NotchMeetingCountdown.label(for: soon, now: now, locale: locale) == "4m", "minutes are narrow")
        expect(
            NotchMeetingCountdown.label(
                for: soon, now: now.addingTimeInterval(30), locale: locale) == "4m",
            "a partial minute rounds up")
        expect(NotchMeetingCountdown.label(for: underway, now: now, locale: locale) == "Now", "a started meeting reads Now")
    }

    static func testTerminalSessions() {
        let idle = NotchTerminalSession(id: UUID(), title: "~", directory: "~", isRunning: false)
        let build = NotchTerminalSession(id: UUID(), title: "make", directory: "~/app", isRunning: true)
        expect(NotchTerminalSession.runningCount(in: [idle, build]) == 1, "only running sessions are counted")
        expect(NotchTerminalSession.ordered([idle, build]) == [build, idle], "running sessions list first")
    }

    static func testTimerPreset() {
        let now = Date(timeIntervalSince1970: 500)
        expect(
            NotchTimerPreset.end(afterMinutes: 25, from: now) == now.addingTimeInterval(1_500),
            "a preset ends that many minutes from now")
        expect(
            NotchTimerPreset.end(afterMinutes: 0, from: now) == now.addingTimeInterval(60),
            "a timer is never shorter than a minute")
        expect(NotchTimerPreset.minutes(from: " 90 ") == 90, "a typed length is whole minutes")
        expect(
            NotchTimerPreset.minutes(from: "1") == 1 && NotchTimerPreset.minutes(from: "1440\n") == 1440,
            "a minute and a day are both allowed, and a trailing newline is ignored")
        expect(
            NotchTimerPreset.minutes(from: "0") == nil && NotchTimerPreset.minutes(from: "1441") == nil
                && NotchTimerPreset.minutes(from: "ten") == nil && NotchTimerPreset.minutes(from: "") == nil,
            "anything but a minute to a day is refused")
    }

    static func testNotchShortcuts() {
        expect(NotchShortcut.isValid(NotchShortcut.defaults), "the default row is a valid one")
        expect(
            NotchShortcut.shortcuts(from: ["clipboard", "settings"]) == [.clipboard, .settings],
            "a stored row decodes in order")
        expect(NotchShortcut.shortcuts(from: ["clipboard", "nope"]) == nil, "an unknown name rejects the row")
        expect(
            NotchShortcut.shortcuts(from: ["camera", "camera"]) == nil, "a repeated shortcut rejects the row")
        expect(
            NotchShortcut.shortcuts(from: NotchShortcut.allCases.map(\.rawValue)) == nil,
            "a row longer than the header holds is rejected")
        expect(NotchShortcut.shortcuts(from: []) == [], "an empty row is allowed")
        typealias Slot = NotchShortcutLayout.Slot
        func place(
            _ layout: NotchShortcutLayout?, _ shortcut: NotchShortcut, _ zone: NotchShortcutLayout.Zone,
            _ index: Int, battery: Bool = false
        ) -> NotchShortcutLayout? {
            layout?.placing(shortcut, in: Slot(zone: zone, index: index), showsBattery: battery)
        }
        let short = NotchShortcutLayout(row: [.clipboard, .notebook, .settings])
        expect(
            short[.row] == [nil, nil, .clipboard, .notebook, .settings],
            "a stored row without gaps sits against the header's edge")
        expect(
            NotchShortcutLayout(beforeNotch: [.timer], afterNotch: [.emoji], row: [])[.beforeNotch] == [nil, .timer]
                && NotchShortcutLayout(afterNotch: [.emoji], row: [])[.afterNotch] == [.emoji, nil],
            "and each side of the cutout sits against the cutout")
        let apart = place(short, .timer, .row, 0)
        expect(
            apart?[.row] == [.timer, nil, .clipboard, .notebook, .settings],
            "a shortcut stays in the place it is dropped on, gap and all")
        expect(apart?.stored(.row) == [.timer, .gap, .clipboard, .notebook, .settings], "the gap is stored")
        expect(
            apart.map { NotchShortcutLayout(row: $0.stored(.row)) } == apart, "and read back where it was")
        expect(short.stored(.row) == [.clipboard, .notebook, .settings], "a packed row stores no gaps")
        expect(
            NotchShortcut.shortcuts(from: ["gap", "gap", "timer"]) == [.gap, .gap, .timer],
            "gaps may repeat in a stored list")
        expect(
            place(short, .clipboard, .row, 4)?[.row] == [nil, nil, .settings, .notebook, .clipboard],
            "dropping on a placed shortcut trades places with it")
        expect(
            place(short, .timer, .row, 4)?.unused.contains(.settings) == true,
            "one from outside the header sends the shortcut it lands on out")
        expect(place(short, .settings, .row, 4) == nil, "a shortcut does not land on itself")
        expect(place(short, .timer, .row, 5) == nil, "nor outside the zone")
        let beside = place(short, .notebook, .beforeNotch, 0)
        expect(
            beside?[.beforeNotch] == [.notebook, nil] && beside?[.row] == [nil, nil, .clipboard, nil, .settings],
            "a shortcut moved beside the cutout leaves its place empty")
        expect(beside?.slot(of: .notebook) == Slot(zone: .beforeNotch, index: 0), "and knows where it is")
        expect(beside?.trimmed(.beforeNotch) == [.notebook, nil], "the gap beside the cutout is drawn")
        let five: [NotchShortcut] = [.clipboard, .notebook, .camera, .windowManagement, .timer]
        let full = NotchShortcutLayout(row: five)
        expect(full.unused == [.snippets, .emoji, .settings], "what is not placed is unused, and a gap never is")
        expect(place(full, .emoji, .afterNotch, 0) != nil, "five in the row leave one place right of the cutout")
        expect(place(full, .emoji, .afterNotch, 1) == nil, "but not the second, which would make seven")
        expect(
            full.drawable(.afterNotch, showsBattery: false) == 0..<1
                && short.drawable(.afterNotch, showsBattery: false) == 0..<2,
            "the board offers only the places that have room")
        let crowded = NotchShortcutLayout(afterNotch: [.emoji, .snippets], row: five)
        expect(
            crowded.drawable(.row, showsBattery: false) == 1..<5
                && crowded.fitting(showsBattery: false)[.row] == [nil] + five.dropFirst().map(Optional.some),
            "the cutout's right side takes its room first and the row loses its far place")
        expect(
            full.fitting(showsBattery: true)[.row].first == .some(nil)
                && place(short, .timer, .row, 0, battery: true) == nil
                && place(short, .timer, .row, 1, battery: true) != nil,
            "the battery readout takes the row's far place")
        expect(short.fitting(showsBattery: true) == short, "a layout that fits is left alone")
        expect(
            short.keeping { $0 != .notebook }[.row] == [nil, nil, .clipboard, nil, .settings],
            "a shortcut whose feature is off leaves a gap, and the others keep their places")
        let repaired = NotchShortcutLayout(
            beforeNotch: [.camera, .timer, .emoji, .snippets], afterNotch: [.timer], row: [.camera])
        expect(
            repaired.trimmed(.row) == [.camera] && repaired[.beforeNotch] == [.timer, .emoji]
                && repaired.trimmed(.afterNotch).isEmpty,
            "stored repeats keep their first place and a side is cut to two")
        let sides = NotchShortcutLayout(beforeNotch: [.timer, .gap], afterNotch: [.gap, .emoji], row: [])
        expect(
            sides[.beforeNotch] == [.timer, nil] && sides.stored(.beforeNotch) == [.timer, .gap]
                && sides[.afterNotch] == [nil, .emoji] && sides.stored(.afterNotch) == [.gap, .emoji],
            "a gap next to the cutout is kept on either side and stored")
        expect(
            short.removing(.notebook)[.row] == [nil, nil, .clipboard, nil, .settings]
                && short.removing(.timer) == short,
            "removing leaves the place empty, and a shortcut that is not placed changes nothing")
        let traded = place(beside, .settings, .beforeNotch, 0)
        expect(
            traded?[.beforeNotch] == [.settings, nil] && traded?[.row] == [nil, nil, .clipboard, nil, .notebook],
            "a trade across zones puts each shortcut in the other's place")
        expect(place(short, .gap, .row, 0) == nil, "a gap is never placed")
        expect(
            short.adding(.timer, showsBattery: false)?[.row] == [nil, .timer, .clipboard, .notebook, .settings],
            "an added shortcut takes the row's nearest free place")
        expect(
            full.adding(.emoji, showsBattery: false)?[.afterNotch] == [.emoji, nil],
            "then the place right of the cutout")
        let packed = NotchShortcutLayout(afterNotch: [.emoji], row: five)
        expect(
            packed.adding(.snippets, showsBattery: false)?[.beforeNotch] == [nil, .snippets]
                && NotchShortcutLayout(beforeNotch: [.settings, .snippets], row: Array(five.dropLast()))
                    .adding(.timer, showsBattery: true) == nil,
            "then left of it, and nowhere once the header is full")
        let shown = short.keeping { $0 != .notebook }
        expect(
            shown.removing(.clipboard).restoring(from: short) { $0 == .notebook }[.row]
                == [nil, nil, nil, .notebook, .settings],
            "a shortcut the board left out goes back to its place, and a removed one stays out")
        expect(
            place(shown, .timer, .row, 3)?.restoring(from: short) { $0 == .notebook }[.row]
                == [nil, nil, .clipboard, .timer, .settings],
            "unless its place was taken meanwhile")
    }
}
