#!/bin/bash

if [ "$1" == 'X64' ]; then CPU_ARCH="x86_64"; else CPU_ARCH="aarch64"; fi

if [[ -z "${GITHUB_WORKSPACE}" ]]; then
	export GITHUB_WORKSPACE="."
fi

curl -sSfLO "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-"${CPU_ARCH}".AppImage"
chmod a+x linuxdeploy*.AppImage
curl -sSfL https://github.com"$(curl https://github.com/probonopd/go-appimage/releases/expanded_assets/continuous | grep "mkappimage-.*-"${CPU_ARCH}".AppImage" | head -n 1 | cut -d '"' -f 2)" -o mkappimage.AppImage
chmod a+x mkappimage.AppImage
curl -sSfLO "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh"
chmod a+x linuxdeploy-plugin-gtk.sh
curl -sSfLO "https://github.com/darealshinji/linuxdeploy-plugin-checkrt/releases/download/continuous/linuxdeploy-plugin-checkrt.sh"
chmod a+x linuxdeploy-plugin-checkrt.sh

if [[ ! -e /usr/lib/"${CPU_ARCH}"-linux-gnu ]]; then
	sed -i 's#lib\/"${CPU_ARCH}"-linux-gnu#lib64#g' linuxdeploy-plugin-gtk.sh
fi

mkdir -p AppDir/usr/bin
mkdir -p AppDir/usr/share/Cemu
mkdir -p AppDir/usr/share/applications
mkdir -p AppDir/usr/share/icons/hicolor/128x128/apps
mkdir -p AppDir/usr/share/metainfo
mkdir -p AppDir/usr/lib

cp dist/linux/info.cemu.Cemu.{desktop,png} AppDir/
cp dist/linux/info.cemu.Cemu.metainfo.xml AppDir/usr/share/metainfo/info.cemu.Cemu.appdata.xml

cp -r bin/* AppDir/usr/share/Cemu

mv AppDir/usr/share/Cemu/Cemu AppDir/usr/bin/
chmod +x AppDir/usr/bin/Cemu

cp /usr/lib/"${CPU_ARCH}"-linux-gnu/{libsepol.so.1,libffi.so.7,libpcre.so.3,libGLU.so.1,libthai.so.0} AppDir/usr/lib

# No UPD_INFO (fork): upstream's would let AppImage updaters replace this build with official Cemu.
export NO_STRIP=1
./linuxdeploy-"${CPU_ARCH}".AppImage --appimage-extract-and-run \
  --appdir="${GITHUB_WORKSPACE}"/AppDir/ \
  -d "${GITHUB_WORKSPACE}"/AppDir/info.cemu.Cemu.desktop \
  -i "${GITHUB_WORKSPACE}"/AppDir/info.cemu.Cemu.png \
  -e "${GITHUB_WORKSPACE}"/AppDir/usr/bin/Cemu \
  --custom-apprun=dist/linux/AppRun \
  --plugin gtk \
  --plugin checkrt

if ! GITVERSION="$(git rev-parse --short HEAD 2>/dev/null)"; then
	GITVERSION=experimental
fi
echo "Cemu Version Cemu-${GITVERSION}"

rm AppDir/usr/lib/libwayland-client.so.0
echo -e "export LC_ALL=C\nexport FONTCONFIG_PATH=/etc/fonts" >> AppDir/apprun-hooks/linuxdeploy-plugin-gtk.sh
# The GamePad bridge (fork), after linuxdeploy: its programs carry their own libraries (bundle-gamepad.sh)
if [ -x gamepad-bridge/build/bridge/cemu-gamepad-bridge ]; then
	dist/linux/bundle-gamepad.sh AppDir || exit 1
else
	echo "GamePad bridge not built (gamepad-bridge/build.sh): the AppImage won't include it"
fi

VERSION="${GITVERSION}" ./mkappimage.AppImage --appimage-extract-and-run "${GITHUB_WORKSPACE}"/AppDir

mkdir -p "${GITHUB_WORKSPACE}"/artifacts/
mv Cemu-"${GITVERSION}"-"${CPU_ARCH}".AppImage "${GITHUB_WORKSPACE}"/artifacts/
