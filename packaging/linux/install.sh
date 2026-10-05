#!/bin/sh
# Installs DSPi Console for the current user: the AppImage in ~/.local/bin,
# a menu entry with its icon, and the udev rule that lets you open a DSPi
# without root (that step asks for your password).
#   ./install.sh               install or update
#   ./install.sh --uninstall   remove (the udev rule too)
set -e
cd "$(dirname "$0")"

bin="$HOME/.local/bin/DSPi-Console.AppImage"
desktop="$HOME/.local/share/applications/dspi-console.desktop"
icon="$HOME/.local/share/icons/hicolor/scalable/apps/dspi-console.svg"
rule=/etc/udev/rules.d/70-dspi.rules

as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"
    elif command -v sudo >/dev/null 2>&1; then sudo "$@"
    elif command -v pkexec >/dev/null 2>&1; then pkexec "$@"
    else echo "Run as root: $*" >&2; return 1
    fi
}

refresh_menus() {
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$HOME/.local/share/applications" || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" || true
}

if [ "$1" = "--uninstall" ]; then
    rm -f "$bin" "$desktop" "$icon"
    refresh_menus
    if [ -f "$rule" ]; then
        echo "Removing the udev rule (needs root)..."
        as_root rm -f "$rule" && as_root udevadm control --reload-rules || true
    fi
    echo "DSPi Console removed. Your settings stay in ~/.config/DSPi."
    exit 0
fi

app=$(ls DSPi-Console-*-x86_64.AppImage 2>/dev/null | head -n 1)
if [ -z "$app" ]; then
    echo "No DSPi-Console-*.AppImage next to this script." >&2
    exit 1
fi

mkdir -p "$(dirname "$bin")" "$(dirname "$desktop")" "$(dirname "$icon")"
install -m 755 "$app" "$bin"
install -m 644 dspi-console.svg "$icon"
cat > "$desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=DSPi Console
GenericName=DSP Controller
Comment=Configure and tune a DSPi audio processor
Exec="$bin"
Icon=dspi-console
Terminal=false
Categories=AudioVideo;Audio;Mixer;
Keywords=DSP;EQ;equalizer;crossover;audio;
StartupWMClass=DSPiConsole
DESKTOP
refresh_menus
echo "Installed $app to $bin, with a menu entry."

if [ -f "$rule" ] && cmp -s 70-dspi.rules "$rule"; then
    echo "The udev rule is already installed."
else
    echo "Installing the udev rule so DSPi Console can open the device (needs root)..."
    as_root install -D -m 644 70-dspi.rules "$rule"
    as_root udevadm control --reload-rules
    as_root udevadm trigger --subsystem-match=usb --attr-match=idProduct=feaa || true
    echo "Done. If the DSPi was already plugged in and still isn't found, unplug it and plug it back in."
fi
echo "Start DSPi Console from your application menu."
