#!/bin/bash
# MacBook8,1 speakers: install the TDM/class-D DKMS stack (pin patches alone are not enough).
# Upstream: https://github.com/thomas-shirley/macbook8.1-speaker-driver
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=_lib.sh
. "$ROOT/scripts/_lib.sh"
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }

apt_install gcc make dkms wget git "linux-headers-$(uname -r)"

SRC=/usr/local/src/macbook8.1-speaker-driver
install_vendor_src macbook8.1-speaker-driver "$SRC" \
  https://github.com/thomas-shirley/macbook8.1-speaker-driver.git

# Pin-only firmware patch fights the real TDM driver — keep it disabled.
if [[ -f /etc/modprobe.d/macbook-cs4208.conf ]]; then
  mv -f /etc/modprobe.d/macbook-cs4208.conf /etc/modprobe.d/macbook-cs4208.conf.disabled-pinonly
fi
rm -f /etc/wireplumber/wireplumber.conf.d/51-macbook8-speakers.conf

cd "$SRC"
bash install.sh

echo "03-speakers done via macbook8.1-speaker-driver. Reboot required."
echo "After reboot, play to sink input.MacBook_Speaker (should be default)."
