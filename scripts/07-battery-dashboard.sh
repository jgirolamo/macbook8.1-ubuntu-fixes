#!/bin/bash
# Install AlDente-style MacBook battery dashboard + applesmc-next charge limit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(id -u) -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

apt-get install -y \
  dkms "linux-headers-$(uname -r)" \
  python3-gi python3-gi-cairo python3-cairo \
  gir1.2-gtk-4.0 gir1.2-adw-1 \
  gir1.2-ayatanaappindicator3-0.1 libnotify-bin \
  curl ca-certificates

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/applesmc.deb" \
  https://github.com/netlinux-ai/applesmc-next/releases/download/v9-dualsuite/applesmc-next-dkms_0.1.6-9netlinux1.resolute1_all.deb
dpkg -i "$TMP/applesmc.deb" || apt-get install -fy

# Reload so charge_control_end_threshold appears
modprobe -r applesmc sbs 2>/dev/null || true
modprobe sbs || true
modprobe applesmc || true
sleep 1

install -m 755 "$ROOT/apps/battery-dashboard/macbook-bclm" /usr/local/sbin/macbook-bclm
install -m 644 "$ROOT/configs/polkit/com.macbook81.battery.policy" \
  /usr/share/polkit-1/actions/com.macbook81.battery.policy
install -m 755 "$ROOT/apps/battery-dashboard/macbook-battery.py" /usr/local/bin/macbook-battery
install -m 644 "$ROOT/apps/battery-dashboard/macbook-battery.desktop" \
  /usr/share/applications/macbook-battery.desktop

# Autostart for installing user
USER_NAME="${SUDO_USER:-}"
if [[ -n "$USER_NAME" && "$USER_NAME" != root ]]; then
  UH=$(getent passwd "$USER_NAME" | cut -d: -f6)
  install -d -o "$USER_NAME" -g "$USER_NAME" "$UH/.config/autostart"
  install -o "$USER_NAME" -g "$USER_NAME" -m 644 \
    "$ROOT/apps/battery-dashboard/macbook-battery.desktop" \
    "$UH/.config/autostart/macbook-battery.desktop"
fi

# Default 80% limit if sysfs ready
if [[ -w /sys/class/power_supply/BAT0/charge_control_end_threshold ]]; then
  echo 80 >/sys/class/power_supply/BAT0/charge_control_end_threshold
  echo "BCLM set to $(cat /sys/class/power_supply/BAT0/charge_control_end_threshold)%"
else
  echo "NOTE: charge_control_end_threshold not writable yet — reboot may be required after DKMS build."
  dkms status | grep -i apple || true
fi

echo "07-battery-dashboard done. Launch: macbook-battery  (or Activities → MacBook Battery)"
