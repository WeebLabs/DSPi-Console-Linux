#!/usr/bin/env bash
# Builds every Linux release file into dist/:
#   DSPi-Console-v<version>-x86_64.AppImage       any distribution (glibc 2.35+)
#   DSPi-Console-v<version>-linux-x86_64.tar.gz   the AppImage, udev rule and installer
#   dspi-console_<version>_amd64.deb              Ubuntu 22.04+, Debian 12+
#   dspi-console-<version>-1.x86_64.rpm           Fedora 42+
# Each is built in a podman container of the oldest distribution it targets.
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
rm -f "$repo"/dist/*.AppImage "$repo"/dist/*.tar.gz "$repo"/dist/*.deb "$repo"/dist/*.rpm

podman build -t dspi-console-build -f "$here/Containerfile.ubuntu" "$here"
podman run --rm -v "$repo":/src:z -e VERSION="$version" dspi-console-build /src/packaging/linux/build-ubuntu.sh
podman build -t dspi-console-build-fedora -f "$here/Containerfile.fedora" "$here"
podman run --rm -v "$repo":/src:z dspi-console-build-fedora /src/packaging/linux/build-fedora.sh
ls -l "$repo"/dist/*.AppImage "$repo"/dist/*.tar.gz "$repo"/dist/*.deb "$repo"/dist/*.rpm
