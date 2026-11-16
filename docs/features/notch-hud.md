# Notch HUD

Hardware-blended inline Notch HUD (and Dynamic-Island pill fallback on non-notched displays) replacing the stock macOS system OSD for audio volume, mute, per-display screen brightness, keyboard backlight and Bluetooth audio output connect notifications.

## Invariants

- **Zero idle CPU and zero keystroke overhead.** When `notchHUDEnabled` is off, neither `MediaKeyInterceptorTap` nor `AudioVolumeService`'s CoreAudio listeners are installed. When on, `MediaKeyInterceptorTap` subscribes exclusively to `CGEventMask(1 << 14)` (`NX_SYSDEFINED`) on its own worker run loop, so normal typing and pointer events never enter the tap.
- **Zero per-step CoreAudio device discovery.** `AudioVolumeService` caches the default output device, its transport type and its volume/mute properties through `AudioObjectAddPropertyListenerBlock`, avoiding synchronous device enumeration on rapid volume steps or trackpad scrolls.
- **Pure optical black (`#000000`) in both Light and Dark appearances.** Physical MacBook camera housings remain pitch black regardless of appearance mode. `NotchHUDPanel` pins its own `appearance` to `.darkAqua` and fills `NotchWingShape` with `Theme.Colors.notchHardwareBlack`, keeping white alpha-ramp ink legible without an adaptive gray seam.
- **No `NSWindow` resizing during spring overshoot.** `NotchHUDGeometry` reserves overshoot headroom inside `panelFrame` once per presentation so rubber-band stretch (`+4 pt` wings, `2 pt` track compression) animates inside SwiftUI's `NotchWingShape` without reallocating WindowServer backing stores.
- **Unconstrained top bezel placement.** `NotchHUDPanel` overrides `constrainFrameRect(_:to:)` and sits at `.notchHUD` (`statusBar + 1`) with `ignoresMouseEvents = true`, allowing inline wings to sit flush with `screen.frame.maxY` across Spaces and fullscreen apps.
- **Native macOS `⌥` shortcut preservation.** Bare `⌥` + Volume/Brightness passes through `MediaKeyEvent.decode` untouched so macOS continues opening **System Settings → Sound / Displays**, while unmodified (`1/16`) and `⇧⌥` (`1/64`) steps route into the Notch HUD.

## Layering

| File | Role |
| --- | --- |
| `Features/NotchHUD/Model/NotchHUDMetric.swift` | Pure metric state, `1/16` & `1/64` step math, overshoot calculation and SF Symbol selection |
| `Features/NotchHUD/Model/NotchHUDGeometry.swift` | Pure inline-wing layout, `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` clamping and non-notched pill fallback |
| `Features/NotchHUD/Model/MediaKeyEvent.swift` | Pure subtype-8 `NX_SYSDEFINED` decoder |
| `Platform/AudioVolumeService.swift` | Event-driven CoreAudio output cache (`VirtualMainVolume` + stereo fallback + Bluetooth route detection) |
| `Platform/KeyboardBacklightService.swift` | `CoreBrightness` `KeyboardBrightnessClient` bridge |
| `Features/HotKeys/Service/DisplayBrightnessService.swift` | Per-display `DisplayServices` + Apple Silicon DDC/CI brightness with optional system-OSD suppression |
| `Features/NotchHUD/Service/MediaKeyInterceptorTap.swift` | Dedicated worker-thread `.cghidEventTap` swallowing intercepted subtype-8 media keys |
| `Features/NotchHUD/UI/NotchHUDManager.swift` | Lifecycle, sleep/lock pause, Accessibility recovery and fast-path routing from `HyperScrollRunner` and `SystemActionCoordinator` |
| `Features/NotchHUD/UI/NotchHUDController.swift` | Presentation, dwell extension, rubber-band snap-back and retraction |
| `Features/NotchHUD/UI/NotchHUDPanel.swift` | Unconstrained click-through `NSPanel` above `.statusBar` |
| `Features/NotchHUD/UI/NotchWingShape.swift` | Animatable bezier silhouette (`6 pt` concave top-shoulder ears, `14 pt` inner corners) |
| `Features/NotchHUD/UI/NotchHUDView.swift` | Inline wings, smooth spring capsule bar, tabular `%` readout and Dynamic-Island pill fallback |
| `Features/NotchHUD/Settings/NotchSettingsView.swift` | **Settings → Notch** toggle, status indicator and live preview |
