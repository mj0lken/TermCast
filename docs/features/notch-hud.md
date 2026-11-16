# Notch HUD & Open Notch Shelf

Hardware-blended inline Notch HUD and interactive Open-Notch tray (`Home` Now Playing + Calendar/Upcoming and `Shelf` AirDrop + File/URL staging) replacing both the stock macOS OSD and third-party notch utilities.

## Invariants

- **Zero idle CPU and zero keystroke/pointer overhead.** When disabled, no event tap, tracking window, CoreAudio listener, `MediaRemote` observer or `IOPowerSources` run-loop source is installed. When `notchHUDEnabled` is on, `MediaKeyInterceptorTap` subscribes exclusively to `CGEventMask(1 << 14)` (`NX_SYSDEFINED`). When `notchShelfEnabled` is on, `NotchSensorPanel` parks a passive `NSTrackingArea` + `NSDraggingDestination` strictly over the dead camera housing (`leftAux.maxX .. rightAux.minX`), so desktop mouse movement never wakes the process.
- **Zero per-step CoreAudio device discovery.** `AudioVolumeService` caches the default output device, transport type and volume/mute properties via `AudioObjectAddPropertyListenerBlock`.
- **Event-driven Now Playing and Battery.** `NowPlayingMonitor` reads one line per change from the relay and never polls; a 1 Hz `TimelineView` scrubber runs only while the tray is visibly expanded and playing. `BatteryStatusService` listens to `IOPSNotificationCreateRunLoopSource` without polling.
- **Now Playing is read out of process, through `/usr/bin/osascript`.** macOS answers now-playing queries only for Apple-signed processes, so an in-process `MediaRemote` read returns nothing on every supported release. `NowPlayingMonitor` runs `Resources/NowPlayingRelay.js` under `osascript` instead, and the relay exists only while `notchShelfEnabled` and `notchShowsMedia` are both on. Transport (play/pause, next, previous, seek) is still accepted from Tinycast itself and stays in-process in `NowPlayingService`.
- **The relay never outlives Tinycast.** It holds the read end of a pipe Tinycast never writes to and exits on end-of-file, so a crash or a force-quit takes it down too. `NowPlayingMonitor` ignores output from any launch but the current one.
- **Pure optical black (`#000000`) in both Light and Dark appearances.** `NotchHUDPanel` and `NotchTrayPanel` pin their panel `appearance` to `.darkAqua` and fill `NotchWingShape` with `Theme.Colors.notchHardwareBlack` so both inline wings and the expanded tray blend seamlessly into the physical camera housing.
- **No `NSWindow` resizing during spring overshoot.** `NotchHUDGeometry` reserves overshoot headroom inside `panelFrame` once per presentation so rubber-band stretch animates inside SwiftUI's `NotchWingShape` without reallocating WindowServer backing stores.
- **Native macOS `⌥` shortcut preservation.** Bare `⌥` + Volume/Brightness passes through `MediaKeyEvent.decode` untouched so macOS continues opening **System Settings → Sound / Displays**.

## Layering

| File | Role |
| --- | --- |
| `Features/NotchHUD/Model/NotchHUDMetric.swift` | Pure metric state, `1/16` & `1/64` step math, overshoot calculation and SF Symbol selection |
| `Features/NotchHUD/Model/NotchHUDGeometry.swift` | Pure inline-wing layout, sensor rect, `OpenTrayLayout` and non-notched fallbacks |
| `Features/NotchHUD/Model/MediaKeyEvent.swift` | Pure subtype-8 `NX_SYSDEFINED` decoder |
| `Features/NotchHUD/Model/NotchTab.swift` | Pure page identifier (`home`, `shelf`) |
| `Features/NotchHUD/Model/NotchShelfItem.swift` | Pure staged file/link/text model, deduplication and middle truncation |
| `Features/NotchHUD/Model/NowPlayingSnapshot.swift` | Pure playback snapshot, elapsed-time interpolation and seek re-anchoring |
| `Features/NotchHUD/Model/NowPlayingRelayMessage.swift` | Pure decoder for one relay line, folding it into a snapshot and carrying artwork across lines |
| `Features/NotchHUD/Model/NotchWeekStrip.swift` | Pure 6-day week strip and per-day agenda filter |
| `Platform/AudioVolumeService.swift` | Event-driven CoreAudio output cache (`VirtualMainVolume` + stereo fallback + Bluetooth route detection) |
| `Platform/KeyboardBacklightService.swift` | `CoreBrightness` `KeyboardBrightnessClient` bridge |
| `Platform/BatteryStatusService.swift` | Event-driven `IOPowerSources` battery percentage and charger notification monitor |
| `Resources/NowPlayingRelay.js` | JXA script run by `osascript`: an `MRNowPlayingController` delegate printing one JSON line per change |
| `Features/NotchHUD/Service/NowPlayingMonitor.swift` | Owns the relay process and its line framing; reports each `NowPlayingRelayMessage` |
| `Features/NotchHUD/Service/NowPlayingService.swift` | Observable track, artwork and source-app state for the tray, plus in-process `MediaRemote` transport |
| `Features/NotchHUD/Service/NotchShelfStore.swift` | Persistent `notch-shelf.json` staging store, drop ingestion and native AirDrop sharing |
| `Features/NotchHUD/Service/NotchSensorPanel.swift` | Passive camera-cutout hover & drag-destination sensor panel |
| `Features/NotchHUD/Service/MediaKeyInterceptorTap.swift` | Dedicated worker-thread `.cghidEventTap` swallowing intercepted subtype-8 media keys |
| `Features/NotchHUD/UI/NotchHUDManager.swift` | Unified lifecycle, sleep/lock pause, Accessibility recovery and routing |
| `Features/NotchHUD/UI/NotchHUDController.swift` | Closed-notch inline HUD presentation, dwell extension and rubber-band snap-back |
| `Features/NotchHUD/UI/NotchTrayController.swift` | Interactive Open-Notch hover/drag/click expansion, haptic alignment and auto-collapse |
| `Features/NotchHUD/UI/NotchOpenTrayView.swift` | Expanded `Home` (Now Playing + Calendar/Upcoming), `Shelf` (AirDrop + Staging Tray), and header controls (Clipboard shortcut, Camera Mirror, Termcast menu, Battery) |
| `Features/NotchHUD/Settings/NotchSettingsView.swift` | **Settings → Features → Notch** controls and live HUD / Tray previews |

## Now Playing relay

The relay prints one JSON object per line, and an object with no `title` means nothing is playing:
`title`, `artist`, `album`, `duration`, `elapsed`, `rate`, `timestamp` (Unix seconds at which `elapsed`
was true), `isPlaying`, `bundleID`, `parentBundleID`, `appName`, `artworkID` and `artwork` (base64).

- **Artwork crosses the pipe once per image.** A play/pause repeats the whole response, so the relay
  sends `artwork` only when `artworkID` or the image size changes, and
  `NowPlayingRelayMessage.snapshot(carrying:receivedAt:)` keeps the previous image while `artworkID`
  matches. The relay forgets what it sent once nothing is playing, because Tinycast drops it then too.
- **The source is the parent app.** A browser plays through a helper process, so `parentBundleID` wins
  over `bundleID` when it is present; the tray shows that app's icon and name.
- **The controller's worker queue is the main queue.** JavaScript called from any other thread waits
  for the run loop to yield, which under `osascript` is never — the callbacks would simply not arrive.
- **A relay that dies is relaunched once per tray open**, through `NowPlayingService.resume()`, never
  on a timer.
