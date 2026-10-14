# Sourced by gamepad-setup.sh and pad-net.sh (root): keeping iwd off the GamePad's adapter.
#
# iwd (SteamOS's Wi-Fi daemon, NetworkManager's backend there) takes every Wi-Fi adapter for itself, whatever
# NetworkManager says: "nmcli device set IF managed no" leaves it registered on the radio, and hostapd then fails with
# "Frame command failed: ret=-16 (Device or resource busy)" (first SteamOS run, 2026-10-14). iwd can only be told to
# skip a phy when it starts (--nophys), and the adapter's phy changes on every plug-in, so: a runtime drop-in
# (/run: gone at reboot) that restarts iwd with --nophys=<the adapter's phy>. The PC's other Wi-Fi drops for a few
# seconds while iwd restarts. phy numbers are never reused before a reboot, so a drop-in left behind for an unplugged
# adapter is harmless. Without iwd running, all of this does nothing (wpa_supplicant systems: nmcli is enough).

IWD_DROPIN=/run/systemd/system/iwd.service.d/99-cemu-gamepad.conf

iwd_active() { systemctl is-active -q iwd.service 2>/dev/null; }

# The ordinary Wi-Fi interface (type 1, not a monitor) on a phy, if there is one
phy_iface() {
  local d
  for d in /sys/class/ieee80211/"$1"/device/net/*; do
    [ -e "$d/type" ] && [ "$(cat "$d/type")" = 1 ] && { basename "$d"; return; }
  done
}

# Is phy $1 in our drop-in's --nophys list?
iwd_skips() { grep -qE -- "^ExecStart=.*--nophys=([^ ]*,)?$1(,| |$)" "$IWD_DROPIN" 2>/dev/null; }

# Take interface $1's adapter away from iwd, if iwd runs. Prints the adapter's interface afterwards: iwd names its
# interfaces itself (wlan1), and if it removed this one on the way out, we add one back.
iwd_release() {
  local ifc=$1 phy argv a out="" next=0 merged=0
  [ -n "$ifc" ] && [ -e "/sys/class/net/$ifc/phy80211" ] || { echo "no Wi-Fi interface '$ifc'" >&2; return 1; }
  phy=$(basename "$(readlink -f "/sys/class/net/$ifc/phy80211")")
  if ! iwd_active || iwd_skips "$phy"; then
    echo "$ifc"
    return 0
  fi
  echo "iwd manages $ifc ($phy): restarting iwd without it" >&2
  rm -f "$IWD_DROPIN"
  systemctl daemon-reload
  # iwd's own command line (with any distribution drop-ins), from "{ path=... ; argv[]=/usr/lib/iwd/iwd ... ; ... }"
  argv=$(systemctl show -p ExecStart --value iwd.service | sed -n 's/.*argv\[\]=\([^;]*[^ ;]\) *;.*/\1/p' | head -1)
  [ -n "$argv" ] || { echo "can't read iwd's command line" >&2; return 1; }
  for a in $argv; do   # add our phy to a --nophys the distribution may already pass
    if [ $next = 1 ]; then a="$a,$phy" next=0 merged=1
    elif [ "$a" = -P ] || [ "$a" = --nophys ]; then next=1
    else case $a in --nophys=*) a="$a,$phy" merged=1 ;; esac
    fi
    out="$out $a"
  done
  [ $merged = 1 ] || out="$out --nophys=$phy"
  mkdir -p "$(dirname "$IWD_DROPIN")"
  printf '# Written by the Wii U GamePad network (cemu-gamepad, scripts/iwd.sh): iwd leaves the GamePad'"'"'s adapter alone.\n[Service]\nExecStart=\nExecStart=%s\n' \
    "$(echo "${out# }" | sed 's/%/%%/g')" > "$IWD_DROPIN"
  systemctl daemon-reload
  systemctl restart iwd.service || { echo "iwd didn't restart" >&2; return 1; }
  local n
  for n in $(seq 1 10); do
    ifc=$(phy_iface "$phy")
    [ -n "$ifc" ] && break
    sleep 0.5
  done
  if [ -z "$ifc" ]; then
    ifc=gamepad0
    iw phy "$phy" interface add "$ifc" type managed || { echo "can't add an interface to $phy" >&2; return 1; }
  fi
  echo "iwd restarted without $phy; the adapter is $ifc" >&2
  echo "$ifc"
}

# The adapter is gone (unplugged): drop the drop-in without restarting iwd (it doesn't need to be told).
iwd_forget() {
  [ -e "$IWD_DROPIN" ] || return 0
  rm -f "$IWD_DROPIN"
  systemctl daemon-reload
}

# Give the adapter back to iwd (reset, failed setup): iwd restarts once more and takes it as an ordinary adapter.
iwd_restore() {
  [ -e "$IWD_DROPIN" ] || return 0
  iwd_forget
  iwd_active && systemctl restart iwd.service
  return 0
}
