#!/usr/bin/env bash
# Rebuild the patched facetimehd in-tree, swap it in, and test a real capture.
#   ! bash /home/thomas/Dev/macbook8.1-camera/build_test.sh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
cd /home/thomas/Dev/macbook8.1-camera/bcwc_pcie
OUT=/home/thomas/Dev/macbook8.1-camera/build_test.log
exec > >(tee "$OUT") 2>&1
echo "######## BUILD+TEST $(date '+%F %T') ########"

echo "== Building module =="
make clean >/dev/null 2>&1
if ! make 2>&1 | tail -5; then echo "BUILD FAILED"; exit 1; fi
ls -l facetimehd.ko || { echo "no .ko"; exit 1; }

echo "== Stop PipeWire, swap module =="
systemctl --user stop wireplumber pipewire pipewire.socket pipewire-pulse 2>/dev/null
sleep 1
sudo bash -c '
  set -e
  modprobe -r facetimehd 2>/dev/null || true
  KDIR="/lib/modules/$(uname -r)/updates/dkms"
  # back up the DKMS module once, then drop our patched build in its place so
  # modprobe (which resolves the videobuf2 dep chain correctly) loads our code
  [ -f "$KDIR/facetimehd.ko.zst" ] && [ ! -f "$KDIR/facetimehd.ko.zst.orig" ] && cp "$KDIR/facetimehd.ko.zst" "$KDIR/facetimehd.ko.zst.orig"
  rm -f "$KDIR/facetimehd.ko.zst"
  cp -f facetimehd.ko "$KDIR/facetimehd.ko"
  depmod -a
  modprobe facetimehd && echo "modprobe OK (patched build)" || { echo "modprobe FAILED"; exit 1; }
  sleep 2
  echo "module facetimehd +p" > /sys/kernel/debug/dynamic_debug/control
  dmesg -C
'
echo -n "/dev/video0: "; ls -l /dev/video0 2>&1

echo "== Capture 5 frames to test.raw =="
cd /home/thomas/Dev/macbook8.1-camera
rm -f test.raw
timeout 20 v4l2-ctl -d /dev/video0 --verbose --stream-mmap --stream-count=5 --stream-to=test.raw 2>&1
echo "v4l2-ctl exit=$?"
echo -n "test.raw size: "; stat -c %s test.raw 2>/dev/null
echo "   (expected per frame: $((848*588*2)) bytes; 5 frames = $((848*588*2*5)))"

echo "== Verdict =="
SIF=$(sudo dmesg | grep -c 'SIF errors')
echo "SIF error count in dmesg: $SIF"
echo "--- stream-start sequence (filtered) ---"
sudo dmesg | grep -aE 'set crop|output config|set camera config|CAMCONF0 0000000|channel start|frame|VIDIOC' | grep -avE 'SIF|Meta data|send 0000|TERMINAL' | head -20

echo "== Restore PipeWire =="
systemctl --user start pipewire.socket pipewire pipewire-pulse wireplumber 2>/dev/null
echo "######## END ########"
