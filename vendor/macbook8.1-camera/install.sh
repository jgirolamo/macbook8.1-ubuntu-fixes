#!/usr/bin/env bash
# Install FaceTime HD (Broadcom 1570) camera support on MacBook8,1
# Run with: sudo bash install.sh
set -euo pipefail

BASE="/home/thomas/Dev/macbook8.1-camera"
FW_SRC="$BASE/facetimehd-firmware/firmware.bin"
DRV_SRC="$BASE/bcwc_pcie"
VER="0.7.0.1"
DKMS_DIR="/usr/src/facetimehd-$VER"

echo "==> 1/4 Installing firmware (v1.43.0)"
install -dm755 /lib/firmware/facetimehd
install -m644 "$FW_SRC" /lib/firmware/facetimehd/firmware.bin
ls -l /lib/firmware/facetimehd/firmware.bin

echo "==> 2/4 Registering driver with DKMS ($VER)"
# Clean any prior install of this version
dkms remove -m facetimehd -v "$VER" --all 2>/dev/null || true
rm -rf "$DKMS_DIR"
mkdir -p "$DKMS_DIR"
cp -a "$DRV_SRC"/. "$DKMS_DIR"/
# Drop any stale build artifacts from the in-tree test compile
make -C "$DKMS_DIR" clean >/dev/null 2>&1 || true

dkms add -m facetimehd -v "$VER"
dkms build -m facetimehd -v "$VER"
dkms install -m facetimehd -v "$VER"
dkms status facetimehd

echo "==> 3/4 Loading module"
# bdc_pci is the stub that grabs the device; blacklisted by dkms.conf but unload if present
modprobe -r bdc_pci 2>/dev/null || true
modprobe facetimehd
sleep 2

echo "==> 4/4 Verifying"
echo "--- lsmod ---"; lsmod | grep facetimehd || true
echo "--- /dev/video* ---"; ls -l /dev/video* 2>&1 || true
echo "--- recent dmesg ---"; dmesg | grep -iE 'facetimehd|fthd' | tail -20 || true
echo
echo "DONE. If /dev/video0 exists, test with: ffplay /dev/video0   (or use Cheese/any app)"
