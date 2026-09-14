#!/bin/bash
# MacBook8,1 speakers: install the TDM/class-D DKMS stack (pin patches alone are not enough).
# Upstream: https://github.com/thomas-shirley/macbook8.1-speaker-driver
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

apt-get install -y gcc make dkms wget git "linux-headers-$(uname -r)"

SRC=/usr/local/src/macbook8.1-speaker-driver
if [[ ! -d "$SRC/.git" ]]; then
  rm -rf "$SRC"
  git clone --depth 1 https://github.com/thomas-shirley/macbook8.1-speaker-driver.git "$SRC"
else
  git -C "$SRC" pull --ff-only || true
fi

# Pin-only firmware patch fights the real TDM driver — keep it disabled.
if [[ -f /etc/modprobe.d/macbook-cs4208.conf ]]; then
  mv -f /etc/modprobe.d/macbook-cs4208.conf /etc/modprobe.d/macbook-cs4208.conf.disabled-pinonly
fi
rm -f /etc/wireplumber/wireplumber.conf.d/51-macbook8-speakers.conf

cd "$SRC"
bash install.sh

echo "03-speakers done via macbook8.1-speaker-driver. Reboot required."
echo "After reboot, play to sink input.MacBook_Speaker (should be default)."
