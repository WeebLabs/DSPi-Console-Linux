#!/usr/bin/env bash
# Runs inside the build container (see build-appimage.sh).
set -euo pipefail
export APPIMAGE_EXTRACT_AND_RUN=1
tools=/src/dist/tools
name="DSPi-Console-$VERSION"

# Build from a copy, leaving the host's build directories alone
rm -rf /work && mkdir /work
tar -C /src --exclude=./target --exclude=./qt/build --exclude=./.git --exclude=./dist -cf - . | tar -C /work -xf -
cd /work
cargo build --release
cmake -S qt -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"

# The app, its Qt libraries, QML modules and plugins (X11 and Wayland)
export QMAKE=/usr/lib/qt5/bin/qmake
export QML_SOURCES_PATHS=/work/qt/qml
export EXTRA_PLATFORM_PLUGINS="libqwayland-generic.so;libqwayland-egl.so"
export EXTRA_QT_PLUGINS="waylandcompositor;svg"
cp qt/dspi-console.svg build/dspi-console.svg
"$tools/linuxdeploy-x86_64.AppImage" --appdir AppDir -e build/DSPiConsole \
    -d packaging/linux/dspi-console.desktop -i build/dspi-console.svg --plugin qt

# KDE window effects (blur, shadow) load these at run time
plugins=/usr/lib/x86_64-linux-gnu/qt5/plugins
mkdir -p AppDir/usr/plugins/kf5
cp -r "$plugins/kf5/kwindowsystem" AppDir/usr/plugins/kf5/
# Native file dialogs through the desktop portal
mkdir -p AppDir/usr/plugins/platformthemes
cp "$plugins/platformthemes/libqxdgdesktopportal.so" AppDir/usr/plugins/platformthemes/
"$tools/linuxdeploy-x86_64.AppImage" --appdir AppDir --deploy-deps-only AppDir/usr/plugins/kf5/kwindowsystem \
    --deploy-deps-only AppDir/usr/plugins/platformthemes
# Named to run after linuxdeploy-plugin-qt-hook.sh
cp packaging/linux/apprun-hook.sh AppDir/apprun-hooks/zz-dspi-console.sh

OUTPUT="$name-x86_64.AppImage" "$tools/linuxdeploy-x86_64.AppImage" --appdir AppDir --output appimage

# Release archive: the AppImage, the udev rule and the installer
rm -rf "$name" && mkdir "$name"
cp "$name-x86_64.AppImage" packaging/linux/70-dspi.rules packaging/linux/install.sh qt/dspi-console.svg "$name/"
cp packaging/linux/README.txt "$name/"
tar -czf "$name-linux-x86_64.tar.gz" "$name"
cp "$name-x86_64.AppImage" "$name-linux-x86_64.tar.gz" /src/dist/
