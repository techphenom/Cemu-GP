#!/bin/bash
# Builds the Cemu + GamePad bridge AppImage (fork) in a container (podman or docker), so it runs on other
# distributions and SteamOS. Result: .appimage-build/artifacts/Cemu-<version>-x86_64.AppImage
#
#   dist/linux/build-appimage.sh
#
# The first run takes a while (container image, vcpkg dependencies); later runs are incremental.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$repo/.appimage-build
image=cemu-gp-appimage

if command -v podman >/dev/null; then
	engine=podman
elif command -v docker >/dev/null; then
	engine=docker
else
	echo "needs podman or docker (Arch: sudo pacman -S podman)" >&2
	exit 1
fi

git -C "$repo" submodule update --init --recursive
mkdir -p "$work"
"$engine" build -t "$image" -f "$repo/dist/linux/appimage-container/Containerfile" "$repo/dist/linux/appimage-container"
user=()
[ "$engine" = docker ] && user=(--user "$(id -u):$(id -g)" -e HOME=/work/home)   # podman (rootless) maps root to you
"$engine" run --rm "${user[@]}" \
	-v "$repo:/src:ro,z" -v "$work:/work:z" \
	"$image" bash /src/dist/linux/appimage-container/build.sh
echo
ls -1 "$work"/artifacts/*.AppImage
