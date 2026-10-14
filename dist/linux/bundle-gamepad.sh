#!/bin/bash
# Adds the GamePad bridge to Cemu's AppDir (fork), as AppDir/usr/lib/cemu-gamepad/ in the layout the scripts expect
# when bundled: bin/, lib/, scripts/, harness/, packaging/. Programs in bin/ find their libraries in lib/ through
# RPATH $ORIGIN/../lib, so the GamePad network service (root) can run copies of them outside the AppImage
# (scripts/install-system.sh). Run after gamepad-bridge/build.sh and after linuxdeploy (which mustn't touch these).
#
#   dist/linux/bundle-gamepad.sh AppDir
#
# Needs patchelf, and iw, dnsmasq and ethtool installed: they're bundled for systems without them (SteamOS).
set -euo pipefail
appdir=$(realpath "$1")
src=$(cd "$(dirname "$0")/../../gamepad-bridge" && pwd)
out=$appdir/usr/lib/cemu-gamepad

rm -rf "$out"
mkdir -p "$out/bin" "$out/lib" "$out/scripts" "$out/harness" "$out/packaging"
install -m 755 "$src/build/bridge/cemu-gamepad-bridge" "$src/build/bridge/tsf-probe" "$out/bin/"
install -m 755 "$src/build/drc-hostap/hostapd/hostapd" "$src/build/drc-hostap/hostapd/hostapd_cli" "$out/bin/"
for tool in iw dnsmasq ethtool; do
	path=$(PATH=$PATH:/usr/sbin:/sbin command -v "$tool") || { echo "missing $tool (bundled as a fallback)" >&2; exit 1; }
	install -m 755 "$path" "$out/bin/"
done
install -m 755 "$src"/scripts/{gamepad-setup.sh,pad-net.sh,install-system.sh} "$out/scripts/"
install -m 644 "$src/scripts/make-wps-cred.py" "$out/scripts/"
install -m 644 "$src"/harness/*.conf "$out/harness/"
install -m 644 "$src"/packaging/{cemu-gamepad-net.service,70-cemu-gamepad.rules} "$out/packaging/"
install -m 644 "$src/LICENSE" "$out/"

# Libraries: everything the programs link that a desktop Linux can't be counted on to have in a compatible version.
# Left to the system: glibc, the C++ runtime (the system's is newer than the build's), and graphics / X / D-Bus /
# systemd libraries, which must match the system.
exclude='^(ld-linux.*|linux-vdso.*|lib(c|m|dl|pthread|rt|resolv|util|anl|nsl|mvec|BrokenLocale)\.so.*|libstdc\+\+\.so.*|libgcc_s\.so.*|lib(GL|EGL|GLX|GLdispatch|OpenGL|gbm|drm|vulkan)\.so.*|libX[^.]*\.so.*|libxcb.*|libdbus-1\.so.*|libsystemd\.so.*|libudev\.so.*|libz\.so.*)$'
copy_deps() {
	local lib name
	ldd "$1" | awk '/=> \// { print $3 }' | while read -r lib; do
		name=$(basename "$lib")
		[[ $name =~ $exclude ]] && continue
		[ -e "$out/lib/$name" ] && continue
		cp -L "$lib" "$out/lib/$name"
		chmod 644 "$out/lib/$name"
	done
}
for f in "$out"/bin/*; do
	copy_deps "$f"
done
for f in "$out"/bin/*; do
	patchelf --set-rpath '$ORIGIN/../lib' "$f"
done
for f in "$out"/lib/*; do
	patchelf --set-rpath '$ORIGIN' "$f"
done

# Every program must resolve all its libraries from here or the system
for f in "$out"/bin/*; do
	if ldd "$f" | grep -q 'not found'; then
		echo "$f: unresolved libraries:" >&2
		ldd "$f" | grep 'not found' >&2
		exit 1
	fi
done
echo "bundled the GamePad bridge: $(ls "$out/bin" | tr '\n' ' '), $(ls "$out/lib" | wc -l) libraries"
