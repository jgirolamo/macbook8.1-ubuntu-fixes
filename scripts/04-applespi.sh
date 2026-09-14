#!/bin/bash
# applespi: delay bind + recover if keyboard/touchpad missing after boot/resume.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }

install -m 644 "$ROOT/configs/applespi-delay.conf" /etc/modprobe.d/applespi-delay.conf
install -m 755 "$ROOT/scripts/applespi-recover" /usr/local/sbin/applespi-recover
install -m 644 "$ROOT/configs/applespi-recover.service" /etc/systemd/system/applespi-recover.service
install -m 755 "$ROOT/scripts/applespi-resume" /etc/systemd/system-sleep/applespi-resume

systemctl daemon-reload
systemctl enable applespi-recover.service
systemctl start applespi-recover.service || true

echo "04-applespi done"
echo "If keyboard is dead: Shut Down, or hold power 10s (SPI hardware reset)."
