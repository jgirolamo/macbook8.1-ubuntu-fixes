#!/bin/bash
# FaceTime HD camera on MacBook8,1 — IOMMU off + patched facetimehd DKMS.
# Upstream: https://github.com/thomas-shirley/macbook8.1-camera
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=_lib.sh
. "$ROOT/scripts/_lib.sh"
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }

apt_install git make gcc dkms curl cpio xz-utils "linux-headers-$(uname -r)" \
  ffmpeg v4l-utils

SRC=/usr/local/src/macbook8.1-camera
install_vendor_src macbook8.1-camera "$SRC" \
  https://github.com/thomas-shirley/macbook8.1-camera.git

cd "$SRC"
bash enable-iommu-off.sh

# Upstream install.sh hardcodes the author's home path — rewrite to this clone.
sed -i "s|^BASE=.*|BASE=\"$SRC\"|" install.sh

cd "$SRC/facetimehd-firmware"
make
cd "$SRC"
bash install.sh

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
  usermod -aG video "$SUDO_USER" || true
fi

echo "08-camera done. Reboot required for intel_iommu=off."
echo "After reboot: ffplay /dev/video0  or GNOME Camera / Cheese."
