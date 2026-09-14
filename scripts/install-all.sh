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

echo
echo "All steps finished. Reboot now:"
echo "  sudo reboot"
echo "(Prefer full shutdown if the keyboard has been flaky.)"
