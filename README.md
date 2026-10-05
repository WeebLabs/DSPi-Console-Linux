# DSPi Console for Linux

A Linux control application for the [DSPi audio processor](https://github.com/WeebLabs/DSPi), open source DSP
firmware that turns a Raspberry Pi Pico (RP2040) or Pico 2 (RP2350) into a multi-output USB audio interface with
an onboard signal processor.

DSPi Console controls the whole device: parametric equalisation, active crossovers, routing, time alignment,
loudness compensation, headphone crossfeed, dynamics, bass enhancement, stereo upmixing, a limiter on every
output, physical control surfaces and hardware configuration, all applied live over USB with no reflashing.

It is a Qt 5 / QML interface on a Rust core, and follows the design and behaviour of
[DSPi Console for macOS](https://github.com/WeebLabs/DSPi-Console).

---

## Contents

- [Match Console and firmware versions](#match-console-and-firmware-versions)
- [Installing](#installing)
- [Getting started](#getting-started)
- [Features](#features)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Troubleshooting](#troubleshooting)
- [Building from source](#building-from-source)
- [Project structure](#project-structure)
- [Related projects](#related-projects)

---

## Match Console and firmware versions

**Run Console and firmware at exactly the same version, including any beta or hotfix suffix.** They share a USB
control protocol that changes with each release. With mismatched versions, features disappear (Console hides
anything the firmware doesn't report), and settings may be written to the wrong place.

Each release of Console carries the matching firmware for RP2040 and RP2350 boards and installs it from
**Firmware Update** in the menu. A banner appears when the connected device runs a different version.

---

## Installing

Download the latest release from the [Releases page](https://github.com/WeebLabs/DSPi-Console-Linux/releases).
It needs 64-bit x86 Linux with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora 36 or later), on X11 or
Wayland.

### With the installer (recommended)

```
tar -xzf DSPi-Console-<version>-linux-x86_64.tar.gz
cd DSPi-Console-<version>
./install.sh
```

The installer copies the AppImage to `~/.local/bin`, adds DSPi Console to your application menu, and installs
a udev rule so the app can open the DSPi without root (it asks for your password once). Run it again to
update, or `./install.sh --uninstall` to remove everything. Settings are kept in `~/.config/DSPi`.

### Running the AppImage directly

```
chmod +x DSPi-Console-<version>-x86_64.AppImage
./DSPi-Console-<version>-x86_64.AppImage
```

### The udev rule

Linux only lets root open USB devices unless a udev rule says otherwise. The installer handles this; to do it
by hand, use `70-dspi.rules` from the release:

```
sudo cp 70-dspi.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
```

Then unplug the DSPi and plug it in again. The rule covers current firmware (USB vendor ID `2e8b`) and older
firmware (`2e8a`). Playback through the DSPi doesn't need it: it's a standard USB audio device.

---

## Getting started

On first launch a **Getting Started** wizard takes a new board from a blank Pico to verified DSPi firmware.
Skip it if your board already runs DSPi; it can be run again from **Help** in the menu.

Console connects to the DSPi automatically. With several connected, click the device name in the sidebar
footer to pick one; right-click it to rescan for a device plugged in later.

**Changes are applied live but not saved.** Press **Ctrl+S** (Commit Parameters) to store them in the active
preset on the device. The menu also offers Revert to Saved and Factory Reset. Console
tracks unsaved changes and asks before switching presets or devices, or quitting.

---

## Features

- **Channel pages** for every input and output: up to 10 PEQ bands per channel with all filter types,
  including shelves and cuts by slope, all-pass and the Linkwitz Transform; crossover bands on outputs; preamp,
  gain, delay, mute, polarity and routing; copy and paste of a channel's settings.
- **On-graph editing:** drag a band's dot to change frequency and gain, scroll to change its width, and use
  the card beside it for exact values and shape. Select and move several bands at once. The graph can show
  phase.
- **Spectrum analyser** behind the response graph, as third-octave bars beneath it, or in its own window. The
  device measures, so every source works (USB, S/PDIF, ADAT, I2S).
- **Dashboard** of every channel's bands and output delays, in Auto, 1, 2 or 3 cards per row.
- **Matrix mixer** with per-crosspoint gain and inversion, input trims, Direct 1:1 and Clear.
- **Effects:** loudness compensation, headphone crossfeed, volume leveller, psychoacoustic bass, subharmonic
  synthesizer, tube modeller and stereo upmixer.
- **Output limiter** on every output, with threshold and release.
- **Presets** on the device, with names, startup preset and unsaved-change tracking. Configurations export and
  import as `.dspipreset` files shared with the macOS and Windows Consoles; filters as REW or AutoEQ text.
- **AutoEQ browser** for the bundled headphone correction database.
- **Control surfaces:** buttons, potentiometers, encoders, switches, LEDs, an IR remote and a small display on
  spare GPIOs, with channel groups, macros and auxiliary outputs (Settings > Control).
- **Tools:** signal generator, Stats for Nerds and an interrupt monitor.
- **Firmware Update** for RP2040 and RP2350, with a configuration export offered first.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Ctrl+S | Commit parameters to the active preset |
| Ctrl+I / Ctrl+E | Import / export filters |
| Ctrl+C / Ctrl+V | Copy / paste a channel page's settings |
| Ctrl+, | Settings |
| Ctrl+Shift+M | Matrix Mixer |
| Ctrl+Shift+A | Spectrum Analyser |
| Ctrl+Shift+G | Signal Generator |
| Ctrl+Shift+B | AutoEQ profiles |
| Ctrl+Shift+L | Loudness Compensation |
| Ctrl+Shift+X | Headphone Crossfeed |
| Ctrl+Shift+V | Volume Leveller |
| Ctrl+Shift+P | Psychoacoustic Bass |
| Ctrl+Shift+S | Subharmonic Synthesizer |
| Ctrl+Shift+D | Tube Modeller |
| Ctrl+Shift+U | Stereo Upmixer |
| Ctrl+Shift+T | Stats for Nerds |
| Ctrl+Shift+I | Interrupt Monitor |
| Ctrl+Q | Quit |

Right-click a slider or level field to reset it to its default.

---

## Troubleshooting

**"Could not open DSPi".** The udev rule is missing or hasn't applied yet. Install it (see
[The udev rule](#the-udev-rule)), then unplug and replug the device.

**The AppImage won't start, with a FUSE error.** Install your distribution's FUSE package (`libfuse2` or
`fuse`), or run it with `--appimage-extract-and-run`.

**Controls or whole windows are missing.** Console hides features the firmware doesn't report, which almost
always means a version mismatch. Install the matching firmware from **Firmware Update**.

**The device isn't detected at all.** Check that the cable carries data and that the DSPi appears as a USB
audio device (`lsusb` shows `2e8b:feaa`). A board left in bootloader mode appears as a removable drive
instead; Firmware Update finds it.

**Changes are lost after a power cycle.** Changes are live until saved: press Ctrl+S.

**No blurred sidebar.** The translucent, blurred sidebar needs KDE Plasma (KWin) with its blur effect on.
Elsewhere the sidebar is solid; everything else is the same.

---

## Building from source

Install a Rust toolchain ([rustup](https://rustup.rs)), CMake, a C++17 compiler, Qt 5.15 with Qt Quick
Controls 2, libusb and libudev. KF5 WindowSystem is optional and enables the KDE blur and window shadows.

```
# Fedora
sudo dnf install cmake gcc-c++ libusb1-devel systemd-devel qt5-qtbase-devel qt5-qtdeclarative-devel \
    qt5-qtquickcontrols2-devel qt5-qtsvg qt5-qtwayland kf5-kwindowsystem-devel

# Debian / Ubuntu
sudo apt install build-essential cmake pkg-config libusb-1.0-0-dev libudev-dev qtbase5-dev \
    qtdeclarative5-dev qtquickcontrols2-5-dev libqt5svg5 qtwayland5 libkf5windowsystem-dev \
    qml-module-qtquick2 qml-module-qtquick-window2 qml-module-qtquick-layouts \
    qml-module-qtquick-controls2 qml-module-qtquick-templates2 qml-module-qt-labs-settings \
    qml-module-qt-labs-platform

# Arch
sudo pacman -S cmake qt5-base qt5-declarative qt5-quickcontrols2 qt5-svg qt5-wayland kwindowsystem5 libusb
```

Then:

```
cargo build --release                         # Rust core and include/dspi_core.h
cmake -S qt -B qt/build -DCMAKE_BUILD_TYPE=Release
cmake --build qt/build -j"$(nproc)"
./qt/build/DSPiConsole
```

The QML, firmware images and AutoEQ database are compiled into the binary.

### Release builds

`packaging/linux/build-appimage.sh` builds the AppImage and the release archive into `dist/`. It builds in an
Ubuntu 22.04 container (podman) so the result runs on older distributions as well.

---

## Project structure

| Path | Contents |
|---|---|
| `core/` | Rust core: USB protocol, device state, preset tracking, control surfaces, filter response math. Exposes a C API (generated into `include/` by cbindgen). |
| `qt/src/` | C++: the bridge between the core and QML, the response graph and on-graph editor, analyser and meter views, firmware updater, AutoEQ library. |
| `qt/qml/` | The interface: main window, channel pages, tool windows, settings and shared components. |
| `qt/firmware/` | The bundled DSPi firmware images. |
| `qt/autoeq/` | The bundled AutoEQ headphone database. |
| `packaging/linux/` | AppImage build, udev rule, desktop entry and installer. |
| `Documentation/` | Core specification and the macOS parity plan. |

---

## Related projects

- [DSPi](https://github.com/WeebLabs/DSPi): the firmware, with the hardware documentation, signal chain
  reference and USB control protocol specification.
- [DSPi Console for macOS](https://github.com/WeebLabs/DSPi-Console): the macOS application.
- [DSPi Console for Windows](https://github.com/WeebLabs/DSPi-Console-Windows): the Windows application.
- [dspictl](https://github.com/WeebLabs/dspictl): command-line control, for scripting and automation.
- [DSPiCliRemote](https://github.com/WeebLabs/DSPiCliRemote): web- and application-based remote control.

The [official Discord server](https://discord.gg/RCyqxAQ5xS) is the best place for development updates,
discussion and help.

### Acknowledgements

- Headphone correction profiles come from the [AutoEQ project](https://github.com/jaakkopasanen/AutoEq).
- Crossfeed is derived from the BS2B algorithm.
- Loudness compensation follows the ISO 226:2003 equal-loudness contours.
