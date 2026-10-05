#!/usr/bin/env bash
# Runs inside the Fedora build container (see build-release.sh): the .rpm.
set -euo pipefail
rm -rf /work && mkdir /work
tar -C /src --exclude=./target --exclude=./qt/build --exclude=./.git --exclude=./dist -cf - . | tar -C /work -xf -
cd /work
cargo build --release
cmake -S qt -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
(cd build && cpack -G RPM && cp dspi-console-*.rpm /src/dist/)
