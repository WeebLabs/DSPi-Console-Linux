#!/usr/bin/env bash
# Builds DSPi Console as an AppImage, plus a release archive with the udev
# rule and an installer, in dist/. The build runs in an Ubuntu 22.04
# container (podman) so the result runs on older distributions too.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
version=v$(grep -oP 'setApplicationVersion\("\K[^"]+' "$repo/qt/src/main.cpp")

tools="$repo/dist/tools"
mkdir -p "$tools"
for t in linuxdeploy-x86_64.AppImage linuxdeploy-plugin-qt-x86_64.AppImage linuxdeploy-plugin-appimage-x86_64.AppImage; do
    [ -x "$tools/$t" ] && continue
    repo_name=${t%-x86_64.AppImage}
    curl -sSfL -o "$tools/$t" "https://github.com/linuxdeploy/$repo_name/releases/download/continuous/$t"
    chmod +x "$tools/$t"
done

podman build -t dspi-console-build -f "$here/Containerfile" "$here"
podman run --rm -v "$repo":/src:Z -e VERSION="$version" dspi-console-build /src/packaging/linux/appimage-inner.sh
echo "Built dist/DSPi-Console-$version-x86_64.AppImage and dist/DSPi-Console-$version-linux-x86_64.tar.gz"
