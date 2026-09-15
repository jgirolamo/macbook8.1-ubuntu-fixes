#!/bin/bash
# Bluetooth: hide SSDC (DSDT), wire early initrd, install macbook12-bluetooth DKMS.
# See docs/BLUETOOTH.md — may still need CRS/mux follow-up on MacBook8,1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y acpica-tools cpio dkms gcc make git wget xz-utils build-essential linux-headers-$(uname -r)

WORK=/var/lib/macbook-bt-ssdc
IMG=/boot/acpi_override_ssdc.img
mkdir -p "$WORK/build"
cd "$WORK/build"
rm -rf -- *

cp /sys/firmware/acpi/tables/DSDT dsdt.dat
extras=()
i=1
for t in /sys/firmware/acpi/tables/SSDT*; do
  [ -f "$t" ] || continue
  cp "$t" "ssdt$i.dat"
  extras+=(-e "ssdt$i.dat")
  i=$((i + 1))
done

iasl "${extras[@]}" -d dsdt.dat >/tmp/iasl-decompile.log 2>&1 || true
test -f dsdt.dsl

python3 - <<'PY'
from pathlib import Path
import re
dsl = Path("dsdt.dsl").read_text(errors="replace")

def patch_device_sta(dsl, name, return_expr="Zero"):
    marker = f"Device ({name})"
    start = dsl.find(marker)
    if start < 0:
        raise SystemExit(f"No {marker}")
    brace = dsl.find("{", start)
    depth = 0
    end = None
    for j, ch in enumerate(dsl[brace:], brace):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = j
                break
    block = dsl[start:end + 1]
    new_sta = (
        f"Method (_STA, 0, NotSerialized)\n"
        f"            {{\n"
        f"                Return ({return_expr})\n"
        f"            }}"
    )
    block2, n = re.subn(
        r"Method\s*\(\s*_STA\b[^)]*\)[^{]*\{[^{}]*\}",
        new_sta,
        block,
        count=1,
        flags=re.S,
    )
    if n != 1:
        raise SystemExit(f"Could not patch {name} _STA (matches={n})")
    return dsl[:start] + block2 + dsl[end + 1:]

dsl = patch_device_sta(dsl, "SSDC", "Zero")

# BLTH._CRS: Linux sets Darwin _OSI on Apple hardware; stock DSDT then returns
# a stub buffer instead of UART resources → baud/power probe fails.
blth = dsl.find("Device (BLTH)")
if blth < 0:
    raise SystemExit("No Device (BLTH)")
crs = dsl.find("Method (_CRS", blth)
brace = dsl.find("{", crs)
depth = 0
end = None
for j, ch in enumerate(dsl[brace:], brace):
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = j
            break
new_crs = """Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
                    {
                        Name (UBUF, ResourceTemplate ()
                        {
                            UartSerialBusV2 (0x002DC6C0, DataBitsEight, StopBitsOne,
                                0xC0, LittleEndian, ParityTypeNone, FlowControlHardware,
                                0x0020, 0x0020, \"\\\\_SB.PCI0.URT0\",
                                0x00, ResourceProducer, , Exclusive,
                                )
                        })
                        Return (UBUF)
                    }"""
dsl = dsl[:crs] + new_crs + dsl[end + 1:]

# Power-up + mux hint on init (GPIO36 selects BT vs SSD debug on MacBook8,1)
if "Method (_INI" not in dsl[blth:blth + 3500]:
    # iasl often inserts "// _STA: Status" between ) and { — allow any non-brace chars.
    sta = re.search(
        r"(Device \(BLTH\)\s*\{[\s\S]*?Method \(_STA,\s*0,\s*NotSerialized\)[^{]*\{[\s\S]*?\}\s*)",
        dsl,
    )
    if not sta:
        raise SystemExit("BLTH._STA not found for _INI insert")
    ini = """Method (_INI, 0, NotSerialized)
                    {
                        GD36 = Zero
                        GP36 = One
                        BTPU ()
                        Sleep (0x32)
                        BTRS ()
                        Sleep (0x32)
                    }

                    """
    dsl = dsl[:sta.end()] + ini + dsl[sta.end():]

def bump(m):
    parts = [p.strip() for p in m.group(1).split(",")]
    parts[5] = f"0x{int(parts[5], 0) + 1:08X}"
    return "DefinitionBlock (" + ", ".join(parts) + ")"

dsl, n = re.subn(r"DefinitionBlock\s*\(([^)]*)\)", bump, dsl, count=1)
if n != 1:
    raise SystemExit("OEM revision bump failed")
Path("dsdt.dsl").write_text(dsl)
print("Patched SSDC + BLTH._CRS (+ _INI)")
PY

iasl -ve dsdt.dsl > /tmp/iasl-compile.log 2>&1 || {
  echo "iasl compile failed:"; cat /tmp/iasl-compile.log; exit 1
}

rm -rf overlay
mkdir -p overlay/kernel/firmware/acpi
cp dsdt.aml overlay/kernel/firmware/acpi/dsdt.aml
( cd overlay && find kernel | cpio -o --format=newc --quiet ) > "$IMG"
chmod 644 "$IMG"
cp dsdt.dsl dsdt.aml "$WORK/"

install -m 644 "$ROOT/configs/macbook-bt.cfg" /etc/default/grub.d/macbook-bt.cfg
update-grub

# DKMS Broadcom UART with Apple ACPI power methods
SRC=/usr/local/src/macbook12-bluetooth-driver
mkdir -p /usr/local/src
if [[ ! -d $SRC/.git ]]; then
  rm -rf "$SRC"
  git clone --depth 1 https://github.com/leifliddy/macbook12-bluetooth-driver.git "$SRC"
fi
cd "$SRC"
chmod +x install.bluetooth.sh dkms.sh
./install.bluetooth.sh -i || ./install.bluetooth.sh || true
dkms status || true

echo "05-bluetooth done — reboot required"
echo "See docs/BLUETOOTH.md if hci0 stays DOWN after reboot."
