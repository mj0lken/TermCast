# Notch HUD & Open Notch Shelf

Hardware-blended inline Notch HUD, persistent closed-notch live activities, and interactive Open-Notch tray (`Home` Now Playing + Calendar/Upcoming, `Shelf` AirDrop + File/URL staging and `Terminal` live sessions) replacing both the stock macOS OSD and third-party notch utilities.

## Invariants

- **Zero idle CPU and zero keystroke/pointer overhead.** When disabled, no event tap, tracking window, CoreAudio listener, `MediaRemote` observer or `IOPowerSources` run-loop source is installed. When `notchHUDEnabled` is on, `MediaKeyInterceptorTap` subscribes exclusively to `CGEventMask(1 << 14)` (`NX_SYSDEFINED`). When `notchShelfEnabled` is on, `NotchSensorPanel` parks a passive `NSTrackingArea` + `NSDraggingDestination` strictly over the dead camera housing (`leftAux.maxX .. rightAux.minX`), so desktop mouse movement never wakes the process.
- **Zero per-step CoreAudio device discovery.** `AudioVolumeService` caches the default output device, transport type and volume/mute properties via `AudioObjectAddPropertyListenerBlock`.
- **Event-driven Now Playing and Battery.** `NowPlayingMonitor` reads one line per change from the relay and never polls; a 1 Hz `TimelineView` scrubber runs only while the tray is visibly expanded and playing. `BatteryStatusService` listens to `IOPSNotificationCreateRunLoopSource` without polling.
- **Now Playing is read out of process, through `/usr/bin/osascript`.** macOS answers now-playing queries only for Apple-signed processes, so an in-process `MediaRemote` read returns nothing on every supported release. `NowPlayingMonitor` runs `Resources/NowPlayingRelay.js` under `osascript` instead, and the relay exists only while `notchShelfEnabled` and `notchShowsMedia` are both on. Transport (play/pause, next, previous, seek) is still accepted from Tinycast itself and stays in-process in `NowPlayingService`.
- **The relay never outlives Tinycast.** It holds the read end of a pipe Tinycast never writes to and exits on end-of-file, so a crash or a force-quit takes it down too. The pipe end Tinycast holds is close-on-exec, so a terminal shell cannot inherit it and keep the relay alive. Each launch is drained by its own task in the order the relay wrote, and that task is cancelled on stop, so output from an earlier launch is never applied.
- **A live activity never polls and never animates in-process.** `NotchLiveActivityController` re-arms one `withObservationTracking` pass per change and schedules a single sleep per meeting boundary; a meeting hours away costs nothing until its lead window opens. The now-playing equaliser is four `CABasicAnimation`s run by the render server, so playback adds no per-frame work to Tinycast. Text that counts (`Text(timerInterval:)`, a per-minute `TimelineView`) exists only while its activity is on the wings.
- **Live wings are click-through and sit one window level under the HUD.** `.notchLiveActivity` is below `.notchHUD`, so a volume step, a notice or the open tray always covers them and they reappear on their own. They never take a click from the menu bar, and they exist only on a display with a notch.
- **The live panel is sized once for the widest activity.** `NotchHUDGeometry.resolveLive` reserves `liveMaxLeftWingWidth` and `liveMaxRightWingWidth`, so swapping activities animates `NotchWingShape` inside a fixed window.
- **Microphone and camera use is read from property listeners only.** `MediaCaptureMonitor` listens on CoreAudio's process-object list and each process's `IsRunningInput`, and on each CoreMediaIO device's `DeviceIsRunningSomewhere`. Tinycast's own processes are excluded, so dictation is never reported as somebody else's recording; CoreMediaIO names no process, so the camera is not reported at all while `CameraSession.liveSessionCount` says Tinycast holds it. It runs only while `notchShelfEnabled` and `notchShowsLiveActivities` are both on.
- **Pure optical black (`#000000`) in both Light and Dark appearances.** `NotchHUDPanel` and `NotchTrayPanel` pin their panel `appearance` to `.darkAqua` and fill `NotchWingShape` with `Theme.Colors.notchHardwareBlack` so both inline wings and the expanded tray blend seamlessly into the physical camera housing.
- **No `NSWindow` resizing during spring overshoot.** `NotchHUDGeometry` reserves overshoot headroom inside `panelFrame` once per presentation so rubber-band stretch animates inside SwiftUI's `NotchWingShape` without reallocating WindowServer backing stores.
- **Native macOS `⌥` shortcut preservation.** Bare `⌥` + Volume/Brightness passes through `MediaKeyEvent.decode` untouched so macOS continues opening **System Settings → Sound / Displays**.

## Layering

| File | Role |
| --- | --- |
| `Features/NotchHUD/Model/NotchHUDMetric.swift` | Pure metric state, `1/16` & `1/64` step math, overshoot calculation and SF Symbol selection |
| `Features/NotchHUD/Model/NotchHUDGeometry.swift` | Pure inline-wing layout, sensor rect, `OpenTrayLayout` and non-notched fallbacks |
| `Features/NotchHUD/Model/MediaKeyEvent.swift` | Pure subtype-8 `NX_SYSDEFINED` decoder |
| `Features/NotchHUD/Model/NotchTab.swift` | Pure page identifier (`home`, `shelf`, `terminal`) |
| `Features/NotchHUD/Model/NotchLiveActivity.swift` | Pure live-activity priority (`NotchLiveInputs.presentation`), wing widths and the capture dot |
| `Features/NotchHUD/Model/NotchMeetingCountdown.swift` | Pure rule for which meeting counts down, its next wake-up and its narrow label |
| `Features/NotchHUD/Model/NotchTerminalSession.swift` | Pure row for one live Terminal tab, with running count and ordering |
| `Features/NotchHUD/Model/NotchTimerPreset.swift` | Pure countdown lengths offered from the tray menu |
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
| `Features/NotchHUD/Service/NotchTimer.swift` | One observable countdown; a single sleep ends it and nothing ticks in between |
| `Features/NotchHUD/Service/MediaCaptureMonitor.swift` | Event-driven microphone and camera use by other apps, naming the recording app when macOS reveals it |
| `Features/NotchHUD/Service/InputSourceMonitor.swift` | Reports a keyboard input source only when it differs from the last one |
| `Features/NotchHUD/Service/NotchShelfStore.swift` | Persistent `notch-shelf.json` staging store, drop ingestion and native AirDrop sharing |
| `Features/NotchHUD/Service/NotchSensorPanel.swift` | Passive camera-cutout hover & drag-destination sensor panel |
| `Features/NotchHUD/Service/MediaKeyInterceptorTap.swift` | Dedicated worker-thread `.cghidEventTap` swallowing intercepted subtype-8 media keys |
| `Features/NotchHUD/UI/NotchHUDManager.swift` | Unified lifecycle, sleep/lock pause, Accessibility recovery and routing |
| `Features/NotchHUD/UI/NotchHUDController.swift` | Closed-notch inline HUD presentation, dwell extension and rubber-band snap-back |
| `Features/NotchHUD/UI/NotchTrayController.swift` | Interactive Open-Notch hover/drag/click expansion, haptic alignment and auto-collapse |
| `Features/NotchHUD/UI/NotchLiveActivityController.swift` | Closed-notch live wings: gathers the inputs, resolves one presentation, shows or retracts the panel |
| `Features/NotchHUD/UI/NotchLiveActivityView.swift` | Left wing (the purple terminal glyph with its count, then the activity's glyph: artwork, calendar, mic or timer) and right readout (equaliser, countdown, waveform, capture dot) |
| `Features/NotchHUD/UI/NotchEqualizerView.swift` | Core Animation equaliser bars |
| `Features/NotchHUD/UI/NotchOpenTrayView.swift` | The expanded tray's shape and page switch, and the action bundles its pages are handed |
| `Features/NotchHUD/UI/NotchTrayHeader.swift` | Header band: tabs, the shortcut row (buttons and the Window Management and Timer menus), battery readout and the inline HUD chip |
| `Features/NotchHUD/UI/NotchTrayHomePage.swift` | `Home`: the Now Playing card, source label and scrubber |
| `Features/NotchHUD/UI/NotchTrayCalendarCard.swift` | `Home`: the week strip, the selected day's events and the Join pill |
| `Features/NotchHUD/UI/NotchTrayShelfPage.swift` | `Shelf`: the AirDrop target and the staged items |
| `Features/NotchHUD/UI/NotchTrayTerminalPage.swift` | `Terminal`: the live sessions list |
| `Features/NotchHUD/Model/NotchShortcut.swift` | Pure header shortcut list: the options, the stored row's validity, the limit and what is drawn |
| `Features/NotchHUD/Settings/NotchSettingsView.swift` | **Settings → Features → Notch** controls and live HUD / Tray previews |
| `Features/NotchHUD/Settings/NotchShortcutsSection.swift` | The pane's Shortcuts section: add, reorder and remove header shortcuts |

## Now Playing relay

The relay prints one JSON object per line, and an object with no `title` means nothing is playing:
`title`, `artist`, `album`, `duration`, `elapsed`, `rate`, `timestamp` (Unix seconds at which `elapsed`
was true), `isPlaying`, `bundleID`, `parentBundleID`, `appName`, `artworkID` and `artwork` (base64).

- **Artwork crosses the pipe once per image.** A play/pause repeats the whole response, so the relay
  sends `artwork` only when the image size changes, and
  `NowPlayingRelayMessage.snapshot(carrying:receivedAt:)` keeps the previous image while consecutive
  lines share an `artworkID`. The two rules must stay mirrored: the relay forgets what it sent on any
  line with a different `artworkID` or no title, because that is exactly when Tinycast drops its copy.
- **The source is the parent app.** A browser plays through a helper process, so `parentBundleID` wins
  over `bundleID` when it is present; the tray shows that app's icon and name.
- **The controller's worker queue is the main queue.** JavaScript called from any other thread waits
  for the run loop to yield, which under `osascript` is never — the callbacks would simply not arrive.
- **A relay that dies is relaunched once per tray open**, through `NowPlayingService.resume()`, never
  on a timer.

## Live activities

While `notchShelfEnabled` and `notchShowsLiveActivities` are on, the closed notch keeps one ongoing
activity on its wings: a glyph on the left, a compact readout on the right.

- **One activity at a time, by priority.** `NotchLiveInputs.presentation(at:)` picks dictation, then an
  imminent meeting, then a running timer, then playback. What the user is doing outranks what is
  scheduled, which outranks what is ambient. Microphone or camera use adds a dot (orange for the
  microphone, green for the camera) beside whatever else is showing, or on its own.
- **Running Terminal sessions never compete for the wings.** They are one compact mark on the leading
  wing, the terminal glyph in `Theme.Colors.brandSecondary` with the count beside it, shown alone or
  ahead of whichever activity has the wings.
- **Now Playing** shows the artwork and an equaliser only while something is playing; a pause retracts
  the wings. A change of track peeks the title through the HUD as a `.notice`, never for the track found
  at launch and never while the tray is open.
- **A meeting counts down inside the join window.** `NotchMeetingCountdown` uses `joinWindowMinutes` as
  its lead and keeps a started meeting for five minutes, never past its end. The same rule shows the
  green **Join** pill on that meeting's row in the tray, so the pill and the countdown cannot disagree.
  Events are re-read on a calendar change, at each scheduled boundary and when the day changes.
- **Dictation** mirrors `DictationCoordinator.onListeningChanged` and `onLevels`; the notch owns none of
  the recording.
- **Timers** start from the Timer shortcut in the tray header (`NotchTimerPreset.minutes`). One sleep on
  the continuous clock ends the timer, so a lid-closed timer finishes on wake; it then plays a sound and
  shows a notice.
- **Terminal sessions** come from a closure `AppCore` supplies over `TerminalStore`; the `Terminal` tab
  lists every live tab, running ones first, and a click opens that tab in the palette through
  `TerminalCoordinator.openSession(id:)`. The tab appears only while `terminalEnabled` is on.

## Notices

`NotchHUDMetric.notice(symbol:text:)` is the one-line toast every announcement shares: a track change, a
finished timer, an app starting to use the microphone or camera, and a keyboard input-source switch
(`notchInputSourceNotifications`, which needs `notchHUDEnabled`). The caller localizes the text, so the
model stays pure. With the tray open a notice becomes the header's inline chip.

## Header shortcuts

The open notch's header holds the tabs on the leading side of the cutout and a row of shortcuts on the
trailing side. `AppSettings.notchShortcuts` is that row, in order: any of Clipboard History, Notebook,
Camera Mirror, Window Management, Timer and Notch Settings, edited in the pane's **Shortcuts** section
and mirrored in `settings.json` as `notch.shortcuts`. The default is Clipboard, Notebook, Camera and
Settings.

- **The row is cut to what fits.** `NotchShortcut.limit(showsBattery:)` is five, or four while the
  battery readout shares the side. `NotchShortcut.visible` drops a shortcut whose feature is off and
  hands its slot to the next one, so the stored row is never rewritten by a feature toggle.
- **Window Management and Timer are menus; the rest are buttons.** Window Management lists the halves,
  quarters and sizing placements and runs one through `WindowCommandCoordinator` on the frontmost
  window, which the non-activating tray never displaces. Every other shortcut closes the tray first.
- **The app's own menu stays in the menu bar.** The notch carries no Termcast menu, so
  `showInMenuBar` is independent of `notchShelfEnabled`.

## What the notch depends on

A notch option never switches another feature on silently; it says what is missing.

| Notch option | Needs | When it is missing |
| --- | --- | --- |
| Replace system volume & brightness HUD | Accessibility | the pane's status row offers Grant Access |
| Show calendar, and the meeting countdown | Calendar enabled and granted | turning it on asks to enable Calendar; the pane and the tray both offer Enable Calendar |
| Clipboard History shortcut | `clipboardEnabled` | the shortcut is not drawn; its row reads Off with Turn On |
| Notebook shortcut | `notesEnabled` | the same |
| Window Management shortcut | `windowManagementEnabled` | the same |
| Terminal tab and the terminal mark | `terminalEnabled` | neither appears |
| Dictation activity | Dictation enabled | never appears |
| Camera Mirror shortcut | camera access | macOS asks on first use |

Now Playing, timers, the shelf and the microphone and camera dot need nothing beyond the notch's own
switches.
