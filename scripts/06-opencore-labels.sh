#!/bin/bash
# Rename OpenCore picker entries: EFI/ubuntu → Ubuntu, EFI/BOOT → Linux.
# Keeps OpenCanopy GUI (PickerMode=External). Does not break PickerAttributes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }

ESP="${ESP:-/boot/efi}"
OC="$ESP/EFI/OC"
ICON_DIR="$OC/Resources/Image/Acidanthera/GoldenGate"
[[ -d "$OC" ]] || { echo "OpenCore not found at $OC"; exit 1; }
[[ -f "$OC/Drivers/OpenCanopy.efi" ]] || echo "WARN: OpenCanopy.efi missing"

# Primary Ubuntu loader
printf 'Ubuntu\n' >"$ESP/EFI/ubuntu/.contentDetails"
printf 'Ubuntu:Linux:Other\n' >"$ESP/EFI/ubuntu/.contentFlavour"
rm -f "$ESP/EFI/ubuntu/.contentVisibility"

# Removable-path / fallback copy of shim
printf 'Linux\n' >"$ESP/EFI/BOOT/.contentDetails"
printf 'Linux:Ubuntu:Other\n' >"$ESP/EFI/BOOT/.contentFlavour"
rm -f "$ESP/EFI/BOOT/.contentVisibility"

# OpenCanopy only understands classic ic07-style icons in this theme.
# Pillow "TOC " ICNS files made Canopy fall back to text — use HardDrive clones.
if [[ -f "$ICON_DIR/HardDrive.icns" ]]; then
  install -m 644 "$ICON_DIR/HardDrive.icns" "$ICON_DIR/Ubuntu.icns"
  install -m 644 "$ICON_DIR/HardDrive.icns" "$ICON_DIR/Linux.icns"
fi

python3 - <<'PY'
import plistlib
from pathlib import Path
p = Path("/boot/efi/EFI/OC/config.plist")
cfg = plistlib.loads(p.read_bytes())
boot = cfg.setdefault("Misc", {}).setdefault("Boot", {})
old = int(boot.get("PickerAttributes", 0))
# Restore known-good GUI attrs used before the text-only regression:
# USE_VOLUME_ICON | USE_POINTER_CONTROL | USE_FLAVOUR_ICON  (= 145)
# Do NOT force USE_DISK_LABEL_FILE / USE_GENERIC_LABEL_IMAGE — those plus
# bad custom ICNS made OpenCanopy abort to Builtin text picker.
want = 0x1 | 0x10 | 0x80  # 145
boot["PickerAttributes"] = want
boot["PickerMode"] = "External"
if not boot.get("PickerVariant"):
    boot["PickerVariant"] = r"Acidanthera\GoldenGate"
# Ensure OpenCanopy driver stays enabled
for d in cfg.get("UEFI", {}).get("Drivers", []) or []:
    if isinstance(d, dict) and str(d.get("Path", "")).endswith("OpenCanopy.efi"):
        d["Enabled"] = True
p.write_bytes(plistlib.dumps(cfg, sort_keys=False))
print(f"PickerMode=External PickerAttributes {old} -> {want}")
PY

echo "06-opencore-labels done. Reboot into OpenCore — GUI picker should return with Ubuntu/Linux names."
