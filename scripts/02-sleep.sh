#!/bin/bash
# Force s2idle; disable hibernation; NVMe APST quirk for Apple SSD.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }

install -d /etc/systemd/sleep.conf.d
install -m 644 "$ROOT/configs/sleep-macbook.conf" /etc/systemd/sleep.conf.d/macbook.conf
install -m 644 "$ROOT/configs/macbook-sleep.cfg" /etc/default/grub.d/macbook-sleep.cfg

if echo s2idle >/sys/power/mem_sleep 2>/dev/null; then
  echo "mem_sleep now: $(cat /sys/power/mem_sleep)"
fi

update-grub
systemctl daemon-reload
echo "02-sleep done (reboot for NVMe cmdline)"
