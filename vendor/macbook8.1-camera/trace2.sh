#!/usr/bin/env bash
# Capture the stream-START sequence (CHINFO / CAMCONF / crop / output) with dynamic
# debug RELIABLY enabled, so we can see the 1675 sensor's reported resolutions.
#   ! bash /home/thomas/Dev/macbook8.1-camera/trace2.sh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
OUT=/home/thomas/Dev/macbook8.1-camera/trace2.log
exec > >(tee "$OUT") 2>&1

echo "######## TRACE2 $(date '+%F %T') ########"
systemctl --user stop wireplumber pipewire pipewire.socket pipewire-pulse 2>/dev/null
sleep 1

sudo bash -c '
  modprobe -r facetimehd 2>/dev/null; sleep 1
  modprobe facetimehd; sleep 2
  # reliably enable ALL pr_debug + hex dumps for the module
  echo "module facetimehd +p" > /sys/kernel/debug/dynamic_debug/control
  echo "dyndbg entries enabled for facetimehd:"
  grep -c "facetimehd.*=p" /sys/kernel/debug/dynamic_debug/control
  dmesg -C
'
echo -n "holders (blank=free): "; fuser /dev/video0 2>&1; echo

echo "== SHORT capture (2 frames, 6s timeout) =="
timeout 6 v4l2-ctl -d /dev/video0 --verbose --stream-mmap --stream-count=2 --stream-to=/dev/null 2>&1
echo "v4l2-ctl exit=$?"

echo "== dmesg: stream-start sequence (filtered, errors collapsed) =="
sudo dmesg 2>&1 | grep -avE 'Meta data buffer|SIF errors: sifIrq|send 00000000|channel TERMINAL' | head -120

systemctl --user start pipewire.socket pipewire pipewire-pulse wireplumber 2>/dev/null
echo "######## END (full log incl errors in trace2.log via the dmesg above is filtered; raw saved separately) ########"
sudo dmesg 2>&1 > /home/thomas/Dev/macbook8.1-camera/trace2.raw.log
