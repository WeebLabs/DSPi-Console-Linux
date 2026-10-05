# DSPi Console for Linux

Qt 5.15 / QML front end (`qt/`) on a Rust core (`core/`, C ABI via cbindgen) for
DSPi firmware 1.1.6 (wire format V32). The macOS Console
(`WeebLabs/DSPi-Console`) is the behavioural and visual reference; the Windows
Console (`WeebLabs/DSPi-Console-Windows`) is a second reference. Phase plan and
status: `Documentation/parity-plan.md`.

## Build and run

```
cargo build --release                      # core -> target/release/libdspi_core.a, include/dspi_core.h
make -C qt/build -j$(nproc)                 # app (cmake already configured in qt/build)
cd qt/build && QT_FORCE_STDERR_LOGGING=1 ./DSPiConsole
```

- New QML files must be added to `qt/resources.qrc` **and** the directory's
  `qmldir` (directory imports from qrc need the qmldir entry).
- Fedora's Qt logs to the journal unless `QT_FORCE_STDERR_LOGGING=1` is set; an
  empty log file proves nothing without it.
- `qmllint` checks syntax only. Runtime QML errors show in the log at load, or
  render a component offscreen with a stub `bridge` object:
  `QT_FORCE_STDERR_LOGGING=1 QT_QUICK_BACKEND=software QT_QPA_PLATFORM=offscreen qml-qt5 harness.qml`
  (set `font.family: "Noto Sans"` in the harness window, or text spacing is wrong;
  icons can be blank on the first offscreen run, so render twice).
- The user tests on real hardware. Don't drive the running app against the
  connected DSPi; build, lint, render offscreen, relaunch, and hand it over.

## Release

`packaging/linux/build-appimage.sh` builds `dist/DSPi-Console-v<version>-x86_64.AppImage`
and a `-linux-x86_64.tar.gz` (AppImage, `70-dspi.rules`, `install.sh`) in an
Ubuntu 22.04 podman container, so it runs on glibc 2.35+. The version comes from
`setApplicationVersion` in `qt/src/main.cpp`. Releases are tagged `v<version>`
and named `DSPi Console v<version>`, like the macOS and Windows repos.

## Git

- Work on `main`. Commit or push only when asked. Never commit
  `channel_editor.png`.

## Rendering and updates

**Never redraw anything unnecessarily.** During a drag or an animation,
update only what that drag or animation needs to look and behave correctly;
nothing else re-renders or recomputes.

- `bridge.stateChanged` re-evaluates every binding in the app. Never emit it
  per mouse move or animation frame. Live updates use the bridge's
  `sendOnly` variants (device and core state change, no signal), and the
  release commits once with the normal call.
- While dragging, the dragged control's own number and graph read the
  slider's value directly (`slider.pressed ? slider.value : stored`, or
  `ParamRow.displayValue`), not a round-trip through the bridge.
- Device updates during a drag go through `Throttle` (first value at once,
  then the latest every 30 ms; `cancel()` before the release commits).
- Graphs redraw only the curves affected, and without animation mid-drag
  (`previewChanged` → `BodePlotItem::refreshNow`).
- No polling or timers that repaint when nothing changed; no bindings that
  rebuild models or lists on unrelated state.

## UI design language

The app follows the redesigned macOS-style look. New or changed UI must match it.

### Rules

- **Reuse the shared components** (below). Never use stock Qt Quick Controls
  `Menu`, `Dialog`, `ComboBox`, `Switch`, `Slider` or bare `TextField` in app UI;
  they render in the Fusion style and look out of place.
- **Keep scale proportionate.** New UI must sit at the same scale as the main
  window (sidebar rows 30 px, menu rows 28 px, 13 px body text, 22–28 px
  controls, the 72 px output channel card). Popups and panels should be compact:
  just big enough for their controls, not covering the page they adjust. Before
  finishing, compare a render against the main window and the existing menus;
  if anything (icon tiles, titles, padding, control heights) is a size up from
  its neighbours, bring it down. Put one-off explanations in tooltips rather
  than extra lines. Reference: the output limiter popup is ~270 × 320 px
  (padding 12, section gap 10, 28 px header tile, 26 px buttons).
- **Change only what was asked.** Don't restyle colours app-wide or touch other
  screens as a side effect; propose wider changes first.
- **Match macOS layouts.** Check the macOS Console (its README and `Images/`)
  before designing a screen, and mirror its structure.
- **Icons**: stroke icons drawn by `components/Icon.qml` (24×24 viewBox,
  1.7 stroke). Add new shapes to its `shapes` map (and an SVG in `qt/icons/`).
  No emoji or Unicode glyphs as icons.
- **No shader effects** (QtGraphicalEffects): they vanish under the software
  renderer. Shadows are layered rectangles; tinting is done in `Icon`.

### Palette

| Use | Value |
|---|---|
| Accent (selection, on states, primary buttons) | `#0a7cff` (lit icons `#3a96dd` / `#3a96ff`) |
| Warning / active-but-attention (INV, limiting, conflicts) | `#ff9f0a` |
| Danger (mute, destructive) | `#ff453a`; destructive fill `#d9363e`, text `#ff6961` |
| OK / connected | `#32d74b` |
| Menus, popups, dialogs background | `MenuStyle.background` (`#1d1d1f`), border `rgba(255,255,255,0.08)` |
| Secondary windows | `#1e1e20` (`AppWindow` default) |
| Cards in Settings / tool windows / matrix | fill `rgba(255,255,255,0.045)`, border `rgba(255,255,255,0.07)`, radius 10 |
| Channel-page cards (top card + band list) | `nativeAltBaseColor` (macOS: `rgba(0.21,0.21,0.21,0.6)`), border `rgba(255,255,255,0.1)`, radius 10 |
| Hairlines / dividers | `rgba(255,255,255,0.07–0.08)` |
| Text | primary white at 0.9; secondary 0.5–0.65; disabled 0.3–0.4; units 0.45 |
| Hover fill | `rgba(255,255,255,0.06–0.08)`; pressed 0.12–0.14 |

Channel colours come from the bridge (`bridge.channelColor`).

### Type and spacing

- UI font (Noto Sans), 13 px body; 11–12 px secondary; small caps section labels
  11 px bold, letter-spacing 0.4, grey (`GAIN`, `DELAY`, `THRESHOLD`).
- Section titles above cards: 13 px DemiBold, grey 0.6, Title Case.
- Numbers use the UI font (not monospace) with a grey unit after them.
- Titlebar 30 px. Menu rows 28 px, icons 15 px. Card padding 14–18 px; gap
  between stacked cards 16–18 px; content margins 16 px.

### Shared components (`qt/qml/components/`)

| Need | Use |
|---|---|
| A secondary window | `AppWindow` (custom titlebar, resize edges, shadow/blur); declare content as children |
| Titlebar | `WindowTitleBar` (used by `AppWindow` and the main window) |
| Right-click / action menu | `ActionMenu` (`openAt(item, x, y)`, items with icon, shortcut, separator, danger, enabled) |
| Pick one of several | `ChoiceMenu` (+ `SidebarPicker` for sidebar rows) |
| App menu | `AppMenu` |
| Filter type | `FilterTypeMenu` (inline slope chips) |
| Confirmation / question | `AppDialog` (buttons fill the width equally; roles primary / destructive / secondary; optional `details` box) |
| Number entry | `ValueField` (in-place edit, hover fill, accent ring, Esc cancels) |
| Slider | `StyledSlider` |
| On/off | `ToggleSwitch` |
| Drop-down in a form | `StyledComboBox` |
| Menu sizes / colours | `MenuStyle` singleton |
| Tool window header / parameter row / channel chips | `ToolHeader`, `ParamRow`, `ChannelChips` |
| Settings page parts | `qt/qml/settings/` (`SettingsPage`, `SettingsSection`, `Settings*Row`); add pages to the registry in `SettingsWindow.qml` |
| Window blur and shadow | `windowEffects` (C++ `WindowEffects`) |
| Tooltip | attached `ToolTip.text` / `ToolTip.visible`; styled app-wide by `qml/style/ToolTip.qml` (the app style overrides only ToolTip, falling back to Fusion) |

### Patterns

- **Popups and menus**: dark rounded card (radius 9–14), soft layered shadow,
  fade + slight scale-in (≈120 ms), open toward the side with room, close on
  Esc / outside click, keyboard ↑/↓/Enter where there's a list.
- **Selection**: accent fill with white text for the hovered/selected row;
  check mark for the current choice.
- **Segmented choices**: rounded track `rgba(255,255,255,0.06)`, selected segment
  filled with the accent (see the limiter link group).
- **Buttons**: outlined (`rgba(255,255,255,0.18)` border, radius 8) for secondary
  actions; filled accent for primary; filled red for destructive.
- **Sections in a card**: label left, value right on top, control (slider)
  underneath; sections separated by full-height hairlines (output channel card).
- **Right-click resets** sliders and level fields to their default.
- **Text field focus** is released app-wide by `TextFocusReleaser` (`qt/src/TextFocusReleaser.h`, installed in main.cpp):
  clicking outside a focused field, or Return/Enter in a single-line field,
  commits the edit and drops focus. Don't add per-page focus handling for this.
