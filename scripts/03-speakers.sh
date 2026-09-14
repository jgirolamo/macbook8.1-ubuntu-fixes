#!/bin/bash
# Restore CS4208 internal speaker pins on MacBook8,1 (SSID 106b:6400).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }

install -m 644 "$ROOT/configs/cs4208-macbook.fw" /lib/firmware/cs4208-macbook.fw
install -m 644 "$ROOT/configs/macbook-cs4208.conf" /etc/modprobe.d/macbook-cs4208.conf

# Live apply if codec sysfs is free
if [[ -w /sys/class/sound/hwC1D0/reconfig ]]; then
  systemctl --user -M "${SUDO_USER:-g}@.host" stop pipewire.socket pipewire.service pipewire-pulse.socket pipewire-pulse.service wireplumber.service 2>/dev/null || true
  sleep 1
  echo 0x10 0x032b401f >/sys/class/sound/hwC1D0/user_pin_configs
  echo 0x11 0x90170010 >/sys/class/sound/hwC1D0/user_pin_configs
  echo 0x12 0x90170011 >/sys/class/sound/hwC1D0/user_pin_configs
  echo 0x13 0x90170012 >/sys/class/sound/hwC1D0/user_pin_configs
  echo 0x14 0x90170014 >/sys/class/sound/hwC1D0/user_pin_configs
  echo 0x1d 0x400000f0 >/sys/class/sound/hwC1D0/user_pin_configs
  echo 1 >/sys/class/sound/hwC1D0/reconfig || true
  systemctl --user -M "${SUDO_USER:-g}@.host" start pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true
  amixer -c PCH set Master 80% unmute >/dev/null 2>&1 || true
fi

echo "03-speakers done (reboot applies patch= firmware reliably)"
