#!/bin/bash
# FaceTime HD camera on MacBook8,1 — IOMMU off + patched facetimehd DKMS.
# Upstream: https://github.com/thomas-shirley/macbook8.1-camera
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

apt-get install -y git make gcc dkms curl cpio xz-utils "linux-headers-$(uname -r)" \
  ffmpeg v4l-utils

SRC=/usr/local/src/macbook8.1-camera
if [[ ! -d "$SRC/.git" ]]; then
  rm -rf "$SRC"
  git clone --depth 1 https://github.com/thomas-shirley/macbook8.1-camera.git "$SRC"
else
  git -C "$SRC" pull --ff-only || true
fi

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
