#!/bin/bash
# Rename OpenCore picker entries: EFI/ubuntu → Ubuntu, EFI/BOOT → Linux.
# Also installs Ubuntu.icns / Linux.icns into the active OpenCanopy theme.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }

ESP="${ESP:-/boot/efi}"
OC="$ESP/EFI/OC"
ICON_DIR="$OC/Resources/Image/Acidanthera/GoldenGate"
[[ -d "$OC" ]] || { echo "OpenCore not found at $OC"; exit 1; }

install -m 644 "$ROOT/configs/opencore-icons/Ubuntu.icns" "$ICON_DIR/Ubuntu.icns"
install -m 644 "$ROOT/configs/opencore-icons/Linux.icns" "$ICON_DIR/Linux.icns"

# Primary Ubuntu loader
printf 'Ubuntu\n' >"$ESP/EFI/ubuntu/.contentDetails"
printf 'Ubuntu:Linux:Other\n' >"$ESP/EFI/ubuntu/.contentFlavour"
rm -f "$ESP/EFI/ubuntu/.contentVisibility"

# Removable-path / fallback copy of shim
printf 'Linux\n' >"$ESP/EFI/BOOT/.contentDetails"
printf 'Linux:Ubuntu:Other\n' >"$ESP/EFI/BOOT/.contentFlavour"
rm -f "$ESP/EFI/BOOT/.contentVisibility"

# Enable flavour icons + custom rendered titles (bit0 + bit2 + bit4 + bit7 = 149)
# Existing value on this machine was 145 (volume + pointer + flavour).
python3 - <<'PY'
import plistlib
from pathlib import Path
p = Path("/boot/efi/EFI/OC/config.plist")
cfg = plistlib.loads(p.read_bytes())
boot = cfg.setdefault("Misc", {}).setdefault("Boot", {})
old = int(boot.get("PickerAttributes", 0))
# OC_ATTR_USE_VOLUME_ICON|USE_DISK_LABEL_FILE|USE_GENERIC_LABEL_IMAGE|USE_POINTER_CONTROL|USE_FLAVOUR_ICON
want = old | 0x1 | 0x2 | 0x4 | 0x10 | 0x80
boot["PickerAttributes"] = want
p.write_bytes(plistlib.dumps(cfg, sort_keys=False))
print(f"PickerAttributes {old} -> {want}")
PY

echo "06-opencore-labels done. Reboot into OpenCore to see Ubuntu / Linux."
