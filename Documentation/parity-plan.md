# DSPi Console Linux — Parity Plan

Goal: bring the Linux Console up to the macOS Console (the reference) and the
Windows Console, against firmware **1.1.6 (wire format V32)**.

References (cloned for comparison):
- macOS: `WeebLabs/DSPi-Console`, branch `release/v1.1.6` (1.1.6-beta4). The README
  is the behavioural spec; the code breaks ties.
- Windows: `WeebLabs/DSPi-Console-Windows` (`docs/macos-parity-plan.md` lists the
  same phases with notes on firmware quirks).
- Firmware: `WeebLabs/DSPi`, branch `release/v1.1.6` (`firmware/DSPi/bulk_params.h`,
  `config.h`, `vendor_commands.c`).

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | Core protocol V32: new USB VID 0x2E8B, 17-channel unified model, chunked bulk get/set, 7-byte platform reply, 41-byte status, 5-bit EQ band wValue, all PEQ types (0-13) incl. Linkwitz Transform, crossover types (32-63) and their response math, band bypass, per-input preamp, master/user volume, output-config and master-volume modes, deferred preset load/save/delete, firmware compatibility check. Bridge maps app ids to wire channels; sidebar/matrix show active inputs; filter rows offer all PEQ types and band bypass | Done, untested on hardware |
| 1 | Channel pages: input header (Link n/n+1 with keep-which dialog, per-device links, preamp, Clear PEQ), output card (routing preview for inputs 1-2, gain, delay, mute, limiter button + settings popup with gain-reduction indicator), band list (bypass dots, per-band colours, Enable/Bypass All, Clear All, PEQ/XO tabs, crossover rows), type menu with slope submenus, Linkwitz Transform editor (outputs only), User/Master volume in the sidebar, Copy/Paste Parameters (sidebar right-click, Ctrl+C/V), Ctrl+scroll value stepping | Done, untested on hardware |
| UI | Sidebar to the macOS layout (meters, pills toggle curves, quick-access icons, Preset/Source/Volume), matrix mixer rebuilt to the macOS layout, client-side titlebar with menu button, KDE shadow (focused only) and sidebar blur via KWindowEffects, graph legend pills removed | Done |
| 2 | Device notifications (bulk IN EP 0x83, protocol v2): listener thread in the core, PARAM_CHANGED patched into the state by bulk offset (own HOST_SET echoes ignored), BULK_INVALIDATED / sequence gap / overflow re-read everything, PRESET_LOADED updates the active slot, INPUT_FORMAT re-polls status. The bridge applies a batch at most every 30 ms with one stateChanged, recomputing only the curves of channels whose bands changed. Siggen, ADAT, I2S-slave, IR-learn and aux events are left for the phases that add those features | Done; verified on hardware (OS volume → UAC1 user volume, own-write echoes, reconnect after reflash) |
| 3 | Tool windows: volume leveller, loudness/crossfeed output masks, psychoacoustic bass, subharmonic synth, tube modeller, stereo upmixer, output limiter | Leveller, Psychoacoustic Bass, Crossfeed (with output pairs), Loudness (ISO 226 curve, output mask), Subharmonic Synthesizer (bands graph, headroom cost, selectivity, ceiling, LF boost, sub meters, solo latch cleared on close, link pairs), Tube Modeller (Basic: tube shelf and showcase with output-peak glow; Advanced: transfer curve with 2nd/3rd harmonic readout, character, rectifier, output stage) and Stereo Upmixer (RP2350: live status gauges, Sinner/Logician engines; matrix shows the derived C/Ls/Rs rows) windows on the shared ToolHeader / ParamRow / ChannelChips / SegmentedControl components. The output limiter is the per-output popup from phase 1 | Done, untested on hardware |
| 4 | Signal generator, statistics (buffer stats), interrupt monitor | Statistics window restyled with the data the core reads today; buffer / S/PDIF / ADAT stats, signal generator and interrupt monitor not started |
| 5 | Spectrum analyser (RTA): engine, graph overlay, bar strip | Not started |
| 6 | On-graph editing; phase graphing (core already computes phase curves) | Not started |
| 7 | Settings: inputs (S/PDIF ×4, I2S multichannel, ADAT, clock modes), outputs (types, I2S/MCK, ADAT out), DAC hardware mute, LG Sound Sync, UART/I2C control | Not started |
| 8 | Control Surfaces + IR remote; presets "Copy to…", "Save as default", preset files | Preset right-click menu done (Save, Rename, Set as Default, Copy to, Clear, Clear All); control surfaces, IR remote and preset files not started |
| 9 | Firmware updater (bootloader + UF2 install), onboarding, What's New | Not started |

## Notes

- **Channel ids.** The core uses firmware wire indices
  (`[inputs 0..n_in-1][outputs n_in..]`). The Qt bridge exposes stable app ids
  like the Windows Console: 0-1 inputs 1-2, 2-10 outputs 1-9, 11-16 inputs 3-8.
- **Unmodeled sections round-trip.** `DspState.bulk_raw` keeps the last bulk
  image, and `encode_bulk` patches modeled fields into it, so SET_ALL never
  zeroes a section the core does not understand yet.
- **Old firmware.** Devices on the old VID 0x2E8A, or reporting a wire format
  other than V32, connect but show a banner and are not written to.
- **Delay limits** are 42 ms (RP2350) and 21 ms (RP2040).
- **Input delay:** the firmware has a per-input delay, but neither the macOS nor the
  Windows Console exposes it, so Linux doesn't either.
- **Logging:** Fedora's Qt logs to the systemd journal when stderr is not a terminal.
  Run with `QT_FORCE_STDERR_LOGGING=1` to see QML warnings in a log file.
- **KDE effects on Wayland** need `kwayland-integration` (KF5 KWindowSystem Wayland
  plugin). KWin reports effects asynchronously, so blur is enabled by polling after
  startup.
- **Notifications vs. local edits.** Setters change the state, not `bulk_raw`, so a
  notification is applied to `encode_bulk(state)`, never to the stale raw image
  (`encode_coverage` test guards that every decoded field is encoded). Echoes of our
  own writes (source HOST_SET) are ignored, which also ignores another host's EP0
  writes, as the Windows Console does.
- **System volume on Linux** reaches the DSPi only with the DSPi PipeWire card
  profile (DSPi repo `tools/linux-pipewire-card-profile`, PR 59). Without it PipeWire
  may pick the IEC958 profile with software volume and the DSPi never sees a change.
  Firmware before the `audio_set_volume()` return fix applied UAC1 volume without
  notifying it.
- `Documentation/core_spec.md` describes the pre-V32 core API and is out of date.
