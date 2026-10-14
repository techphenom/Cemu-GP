#!/bin/bash
# Runs inside the container (dist/linux/build-appimage.sh starts it): builds Cemu, the GamePad bridge and the
# AppImage. The repo is mounted read-only at /src and copied to /work/src, so this build never touches the host's
# bin/ or gamepad-bridge/build/; /work persists between runs (incremental builds, vcpkg cache).
set -euo pipefail
export VCPKG_DEFAULT_BINARY_CACHE=/work/vcpkg-cache VCPKG_FORCE_DOWNLOADED_BINARIES=true
mkdir -p "$VCPKG_DEFAULT_BINARY_CACHE" /work/artifacts "$HOME"
git config --global --add safe.directory '*'

echo "== copying the source"
# Build outputs (the host's and this build's) stay out of the copy, and survive --delete.
rsync -a --delete --exclude /bin/Cemu_release --exclude /bin/Cemu --exclude /build/ --exclude /gamepad-bridge/build/ \
	--exclude /.appimage-build/ --exclude /AppDir/ --exclude /dependencies/vcpkg/vcpkg \
	--exclude /dependencies/vcpkg/downloads/ --exclude /dependencies/vcpkg/buildtrees/ \
	--exclude /dependencies/vcpkg/packages/ /src/ /work/src/
cd /work/src

echo "== Cemu"
[ -x dependencies/vcpkg/vcpkg ] || bash ./dependencies/vcpkg/bootstrap-vcpkg.sh -disableMetrics
cmake -S . -B build -DCMAKE_BUILD_TYPE=release -DCMAKE_C_COMPILER=/usr/bin/clang-15 \
	-DCMAKE_CXX_COMPILER=/usr/bin/clang++-15 -G Ninja -DCMAKE_MAKE_PROGRAM=/usr/bin/ninja
cmake --build build
cp bin/Cemu_release bin/Cemu   # appimage.sh's name for it (as upstream CI)

echo "== GamePad bridge"
JOBS=$(nproc) gamepad-bridge/build.sh

echo "== AppImage"
rm -rf AppDir
# appimage.sh downloads linuxdeploy and runs it with --appimage-extract-and-run (no FUSE needed in here)
export DEPLOY_GTK_VERSION=3
GITHUB_WORKSPACE=/work/src dist/linux/appimage.sh X64
cp -v /work/src/artifacts/*.AppImage /work/artifacts/
