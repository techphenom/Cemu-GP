#pragma once

// Finds the GamePad bridge's files and starts the bridge daemon when Cemu needs it (fork-only, Linux).
//
// Two layouts, both found next to Cemu's executable:
//  - AppImage: <AppDir>/usr/bin/Cemu, with the bridge bundled in <AppDir>/usr/lib/cemu-gamepad/
//    (bin/, lib/, scripts/, harness/, packaging/; dist/linux/appimage.sh builds it)
//  - built from source: <repo>/bin/Cemu_release, with <repo>/gamepad-bridge/ (build/bridge/, scripts/, ...)

namespace GamePadBridgeProcess
{
	// The bridge's directory (the one holding scripts/gamepad-setup.sh), or empty if there is none.
	fs::path BundleRoot();

	// True when Cemu runs from its AppImage. Root-only setup steps then go through "pkexec <AppImage> gamepad-setup":
	// root can't read the AppImage's mount, which belongs to the user.
	bool InAppImage();

	// The AppImage file ($APPIMAGE) when InAppImage(), else empty.
	fs::path AppImageFile();

	// Starts the bridge if the GamePad network is up and no bridge Cemu started is running. True while a bridge
	// Cemu started is running and may still be coming up (the caller retries quietly). The bridge exits with Cemu.
	bool StartIfNeeded();
}
