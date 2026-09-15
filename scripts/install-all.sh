#!/bin/bash
# Run all MacBook8,1 Ubuntu fixes. Reboot when finished.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(id -u) -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }

"$ROOT/scripts/01-base-tune.sh"
"$ROOT/scripts/02-sleep.sh"
"$ROOT/scripts/03-speakers.sh"
"$ROOT/scripts/04-applespi.sh"
"$ROOT/scripts/05-bluetooth.sh"
"$ROOT/scripts/05b-bluetooth-crs.sh"
"$ROOT/scripts/06-opencore-labels.sh"
"$ROOT/scripts/07-battery-dashboard.sh"
"$ROOT/scripts/08-camera.sh"

echo
echo "All steps finished. Reboot now:"
echo "  sudo reboot"
echo "(Prefer full shutdown if the keyboard has been flaky.)"
