#!/bin/bash
set -euo pipefail
ROOT=/home/g/Projects/macbook8.1-ubuntu-fixes
install -m 644 "$ROOT/configs/cs4208-macbook.fw" /lib/firmware/cs4208-macbook.fw
install -m 644 "$ROOT/configs/macbook-cs4208.conf" /etc/modprobe.d/macbook-cs4208.conf
amixer -c PCH set Master 100% unmute || true
amixer -c PCH set Front 100% unmute || true
amixer -c PCH set Surround 100% unmute || true
amixer -c PCH set "Auto-Mute Mode" Disabled || true
echo AUDIO_OK
"$ROOT/scripts/05b-bluetooth-crs.sh"
echo ALL_DONE
