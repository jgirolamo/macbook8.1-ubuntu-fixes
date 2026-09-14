#!/bin/bash
# Free kdump RAM, enable UFW, zram, disable ModemManager.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

echo "==> Disable kdump crashkernel reservation"
if [[ -f /etc/default/kdump-tools ]]; then
  sed -i 's/^USE_KDUMP=1/USE_KDUMP=0/' /etc/default/kdump-tools || true
fi
install -m 644 "$ROOT/configs/kdump-tools.cfg" /etc/default/grub.d/kdump-tools.cfg
systemctl disable --now kdump-tools.service 2>/dev/null || true
systemctl mask kdump-tools.service 2>/dev/null || true

echo "==> Enable UFW"
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

echo "==> zram"
apt-get update -qq
apt-get install -y systemd-zram-generator
install -m 644 "$ROOT/configs/zram-generator.conf" /etc/systemd/zram-generator.conf
install -m 644 "$ROOT/configs/99-zram.conf" /etc/sysctl.d/99-zram.conf
sysctl --system >/dev/null || true
systemctl daemon-reload
systemctl start systemd-zram-setup@zram0.service 2>/dev/null || true

echo "==> Optional: grow swap file to 8G if it is smaller"
if [[ -f /swap.img ]]; then
  size=$(stat -c%s /swap.img)
  if (( size < 8*1024*1024*1024 )); then
    swapoff /swap.img || true
    fallocate -l 8G /swap.img
    chmod 600 /swap.img
    mkswap /swap.img
    swapon /swap.img
  fi
fi

echo "==> Disable ModemManager (no WWAN)"
systemctl disable --now ModemManager.service 2>/dev/null || true
systemctl mask ModemManager.service 2>/dev/null || true

update-grub
echo "01-base-tune done"
