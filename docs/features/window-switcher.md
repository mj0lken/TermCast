# Window Switcher

A ⌘⇥ replacement that walks **windows, not apps**: hold the modifier, press the key, and a panel of
window previews opens; letting go of the modifier switches. Modelled on
[Switch](https://github.com/Sanyam-G/switch), written from scratch on top of the sweep
[Switch Windows](navigation.md) already had. It lives in `Features/WindowSwitcher/` beside that
palette screen, under the `WindowPicker` prefix, and shares its `WindowSwitchEntry`, sweep and AX
layer.

Ships **off**. Settings › Window Switcher is the switch, and it is independent of
`navigationEnabled`.

## Keys

| Key | Does |
| --- | --- |
| modifier + ⇥ | open on every window; again steps forward, with ⇧ backward |
| modifier + ` | open on the front app's windows only |
| 1 – 9 | switch to that tile's window; on a closed group, open it |
| ← → ↑ ↓ | move in the grid |
| left ⇧ tap | toggle grouping by app; inside an open group, step back out |
| right ⇧ tap | open the selected group, or close the open one |
| W / Q / H | close the window, quit its app, hide its app |
| ↵, or release the modifier | switch |
| esc | cancel |

Each chord's modifier is ⌘, ⌥, ⌃ or Off (`windowPickerChord`, default ⌘; `windowPickerAppChord`,
default ⌥). The key is fixed per scope — ⇥ and the key above it — so the two can never collide.
Settings shows the second key as the current layout types it, since the backtick's position holds
§ or < on other keyboards.

**Numbers.** The first nine tiles carry a badge, 1–9, matched by key position rather than
character so they hold on a layout that needs Shift for digits. A number on a window switches at
once; on a closed group it opens the group, whose windows are then numbered in turn.

**Grouping.** Grouped, every app with more than one window is one stacked tile carrying a count; an
app with a single window stays a plain window tile. Releasing on a group switches to its frontmost
window. A selected group opens by itself after `windowPickerGroupDelay` (400–1500 ms, or never),
or at once on a right ⇧ tap; opened, the panel shows only that app's windows and stepping stays
inside it. `windowPickerGroupsByApp` is only how a show *starts* — the left ⇧ toggle lasts for that
show and is never written back. A group's stack is drawn from its next two windows' previews.

**Layout.** Five settings shape the panel, gathered in `WindowPickerGeometry.Limits`: the window
size (`windowPickerTileSize`), the most windows per row and the most rows (`windowPickerMaxColumns`,
`windowPickerMaxRows`, each automatic or 1–8), and the most of the screen's width and height the
panel may take (`windowPickerMaxWidth`, `windowPickerMaxHeight`, 40–100 %). Tiles shrink to honour
the row limit and the screen share; once they can shrink no further, rows are added rather than
windows dropped.

## Invariants

- **The enabling flag grants a capability, so it travels nowhere.** `windowPickerEnabled` installs a
  keyboard event tap; like `snippetsEnabled` it has no `SettingsFileKey` and is in
  `SettingsBackupCoverage.deliberatelyExcluded`. The ten behaviour settings ride both.
- **No tap while off.** `WindowPickerCoordinator.applyEnabled()` tears the tap down and leaves the
  `HealthTicker`; nothing of the feature runs until the switch is on.
- **The tap callback only feeds the engine.** `WindowPickerTap` runs a `.cgSessionEventTap` on its
  own thread, holds a `WindowPickerKeyEngine` under a `Mutex`, and decides swallow-or-pass from
  that pure value alone — no AX, no main-actor hop — so a slow sweep can never stall typing. Commands
  queue and drain on the main actor in the order they were typed.
- **A modifier change is never swallowed.** Only key-downs are, and only while the engine is open,
  plus the opening chord itself. Swallowing a `flagsChanged` would strand that modifier down in
  every other app.
- **A Shift is a tap only if nothing happened in between.** It must go down while the picker is
  open and come up with no key-down since; ⌘⇧⇥ therefore still steps backward. The two Shifts are
  told apart by the device bits in the event flags, which the shared `.maskShift` cannot do.
- **The panel is never key.** It is a `HUDPanel` taking clicks; every key reaches it through the
  tap. Nothing is activated or restored on close, so the raise cannot race a focus restore.
- **Previews exist only while the panel is up.** `WindowPickerSession.reset()` drops them; they are
  captured at tile size, in selection order, and a `generation` counter refuses a late one.
- **Previews are optional and degrade silently.** Without Screen Recording, or for a minimized
  window, a tile shows the app icon. ScreenCaptureKit only — `CGWindowListCreateImage` is deprecated.
- **A missed release still closes.** Secure Input hides key events from the tap; the 1 s health
  tick closes a panel whose modifier is no longer held.

## How it is put together

| Piece | Holds |
| --- | --- |
| `Model/WindowPickerKeyEngine.swift` | raw key events → commands, and what to swallow; pure |
| `Model/WindowPickerBoard.swift` | tiles, selection, grouping and the open group; pure |
| `Model/WindowPickerOrder.swift` | per-window front-to-back order over the per-app fallback |
| `Model/WindowPickerGeometry.swift` | the grid: columns, tile size, panel size |
| `Model/WindowPickerChord.swift`, `…GroupDelay`, `…GridLimit`, `…TileSize`, `…ScreenShare` | the setting enums |
| `Service/WindowPickerTap.swift` | the event tap and its worker thread |
| `Service/WindowPickerSession.swift` | one show's observable state and its live AX elements |
| `Service/WindowThumbnailProvider.swift` | ScreenCaptureKit captures, off the main actor |
| `UI/WindowPickerCoordinator.swift` | enable, open, walk, switch, close/quit/hide, permissions |
| `UI/WindowPickerController.swift` | the panel and its frame |
| `UI/WindowPickerView.swift` | the grid, tiles, group header and hint row |
| `Settings/WindowPickerSettingsView.swift` | the Settings › Window Switcher pane |

**Order.** Unlike Switch Windows, which ranks per app, the picker ranks per window:
`WindowZOrder.ranks()` returns each on-screen window's position in the window server's list, and
`AXWindowAccess.windowID(of:)` maps a swept element onto it. Windows the list does not hold — another
Space, minimized — fall back to `WindowSwitchOrder`. So ⌘⇥ ⌘⇥ flips between the two most recent
windows even when they belong to different apps.

**Action keys follow the layout.** W, Q and H are resolved to key codes through
`ASCIIKeyboardLayout` on every open and handed to the engine, which falls back to the ANSI positions.

## Permissions

Accessibility, for the tap and the raise — the tap cannot be created without it, and
`healthCheck()` installs it once the grant arrives. Screen Recording, for previews only. Both are
asked from the Settings switch (`requestPermissions()`), never at launch.

The pane's **Permissions** section has one row per grant, each polled once a second and each with its
own button. Granting Accessibility from its row then opens the Screen Recording pane by itself when
previews need it — System Settings shows one pane at a time.

## Testing

`Tests/WindowPickerTests.swift` covers the pure half: the chords, opening and passing-through,
stepping, release, both Shift taps and the cases that are not taps, the keys swallowed while open,
the per-window order, the flat and grouped boards, opening and closing a group, selection across a
grouping toggle, removal, and the grid.

The tap, the sweep and the captures have no automated coverage and need a manual pass:

1. ⌘⇥ tapped once switches to the previous window; the Dock's own switcher never appears.
2. Held, ⇥ and ⇧⇥ walk both ways; esc cancels and the following ⌘ release switches nothing.
3. Left ⇧ groups and ungroups; a group opens after the delay and on right ⇧; right ⇧ closes it.
4. ⌥` lists only the front app's windows.
5. W, Q and H act on the selected tile, and the tiles leave.
6. Previews fill in with Screen Recording granted; icons show without it.
7. Typing in any app is unaffected while the switcher is closed, and with the feature off.
8. A window on another Space or minimized is listed, and switching brings it forward.
