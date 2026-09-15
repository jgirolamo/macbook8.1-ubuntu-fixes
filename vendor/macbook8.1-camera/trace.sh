#!/usr/bin/env bash
# Full self-capturing trace. Everything (script diagnostics + verbose v4l2 + kernel log)
# goes into trace.log. Run as your normal user (it calls sudo itself):
#   ! bash /home/thomas/Dev/macbook8.1-camera/trace.sh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
OUT=/home/thomas/Dev/macbook8.1-camera/trace.log
exec > >(tee "$OUT") 2>&1   # tee all output into trace.log

echo "############ TRACE $(date '+%F %T') ############"

echo "== Stopping PipeWire/WirePlumber =="
systemctl --user stop wireplumber pipewire pipewire.socket pipewire-pulse 2>/dev/null
sleep 1
echo -n "holders before unload: "; fuser -v /dev/video0 2>&1; echo

echo "== Reload module (dyndbg ON) + clear dmesg (sudo) =="
sudo bash -c '
  echo "--- modprobe -r facetimehd ---"
  if modprobe -r facetimehd 2>&1; then echo "UNLOAD OK"; else echo "UNLOAD FAILED (in use?)"; fi
  sleep 1
  echo "--- modprobe facetimehd dyndbg==p ---"
  modprobe facetimehd dyndbg==p 2>&1 || { modprobe facetimehd 2>&1; echo "module facetimehd +p" > /sys/kernel/debug/dynamic_debug/control; }
  sleep 2
  echo "--- clearing kernel ring buffer ---"
  dmesg -C
  echo "lsmod: $(lsmod | grep facetimehd || echo NONE)"
'
echo -n "/dev/video0: "; ls -l /dev/video0 2>&1
echo -n "holders after reload (blank=free): "; fuser /dev/video0 2>&1; echo

echo "== Capture attempt (verbose, 5 frames) =="
cd /home/thomas/Dev/macbook8.1-camera
timeout 25 v4l2-ctl -d /dev/video0 --verbose --stream-mmap --stream-count=5 --stream-to=/dev/null 2>&1
echo "v4l2-ctl exit=$?"

echo "== KERNEL LOG (dmesg since clear) =="
sudo dmesg 2>&1

echo "== Restarting PipeWire =="
systemctl --user start pipewire.socket pipewire pipewire-pulse wireplumber 2>/dev/null
echo "############ END TRACE ############"
