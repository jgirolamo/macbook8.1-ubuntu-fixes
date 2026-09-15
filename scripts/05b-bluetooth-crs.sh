#!/bin/bash
# Apply updated DSDT for Bluetooth CRS + power/mux (does not reinstall DKMS).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Allow running from repo or copy
[[ -d "$ROOT/scripts" ]] || ROOT=/home/g/Projects/macbook8.1-ubuntu-fixes

# Reuse the patching half of 05-bluetooth without full DKMS reinstall
WORK=/var/lib/macbook-bt-ssdc
IMG=/boot/acpi_override_ssdc.img
mkdir -p "$WORK/build"
cd "$WORK/build"
rm -rf -- *
cp /sys/firmware/acpi/tables/DSDT dsdt.dat
extras=(); i=1
for t in /sys/firmware/acpi/tables/SSDT*; do
  [ -f "$t" ] || continue
  cp "$t" "ssdt$i.dat"; extras+=(-e "ssdt$i.dat"); i=$((i+1))
done
iasl "${extras[@]}" -d dsdt.dat >/tmp/iasl-d.log 2>&1 || true
test -f dsdt.dsl

python3 - <<'PY'
from pathlib import Path
import re
dsl = Path("dsdt.dsl").read_text(errors="replace")

def patch_sta(dsl, name):
    marker = f"Device ({name})"
    start = dsl.find(marker)
    if start < 0:
        raise SystemExit(f"missing {name}")
    brace = dsl.find("{", start)
    depth = 0
    end = None
    for j, ch in enumerate(dsl[brace:], brace):
        if ch == "{": depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = j; break
    block = dsl[start:end+1]
    new_sta = "Method (_STA, 0, NotSerialized)\n            {\n                Return (Zero)\n            }"
    block2, n = re.subn(r"Method\s*\(\s*_STA\b[^)]*\)[^{]*\{[^{}]*\}", new_sta, block, count=1, flags=re.S)
    if n != 1:
        raise SystemExit(f"{name} _STA failed")
    return dsl[:start] + block2 + dsl[end+1:]

dsl = patch_sta(dsl, "SSDC")

blth = dsl.find("Device (BLTH)")
crs = dsl.find("Method (_CRS", blth)
brace = dsl.find("{", crs)
depth = 0
end = None
for j, ch in enumerate(dsl[brace:], brace):
    if ch == "{": depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = j; break
new_crs = """Method (_CRS, 0, NotSerialized)
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
dsl = dsl[:crs] + new_crs + dsl[end+1:]

# Remove old _INI if present then insert fresh (try both mux polarities via param file)
blth = dsl.find("Device (BLTH)")
# strip existing _INI inside BLTH window
win = dsl[blth:blth+4000]
if "Method (_INI" in win:
    ini_s = dsl.find("Method (_INI", blth)
    brace = dsl.find("{", ini_s)
    depth = 0
    end = None
    for j, ch in enumerate(dsl[brace:], brace):
        if ch == "{": depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = j; break
    dsl = dsl[:ini_s] + dsl[end+1:]

mux = Path("/etc/macbook-bt-mux").read_text().strip() if Path("/etc/macbook-bt-mux").exists() else "One"
# iasl often inserts "// _STA: Status" between ) and { — allow any non-brace chars.
sta = re.search(
    r"(Device \(BLTH\)\s*\{[\s\S]*?Method \(_STA,\s*0,\s*NotSerialized\)[^{]*\{[\s\S]*?\}\s*)",
    dsl,
)
if not sta:
    raise SystemExit("BLTH._STA not found for _INI insert")
ini = f"""Method (_INI, 0, NotSerialized)
                    {{
                        GD36 = Zero
                        GP36 = {mux}
                        BTPU ()
                        Sleep (0x64)
                        BTRS ()
                        Sleep (0x64)
                        BTLP (Zero)
                        Sleep (0x20)
                    }}

                    """
dsl = dsl[:sta.end()] + ini + dsl[sta.end():]
print(f"Mux GP36 = {mux}")

def bump(m):
    parts=[p.strip() for p in m.group(1).split(",")]
    parts[5]=f"0x{int(parts[5],0)+1:08X}"
    return "DefinitionBlock ("+", ".join(parts)+")"
dsl,n=re.subn(r"DefinitionBlock\s*\(([^)]*)\)", bump, dsl, count=1)
Path("dsdt.dsl").write_text(dsl)
print("patched")
PY

iasl -ve dsdt.dsl >/tmp/iasl-c.log 2>&1 || { cat /tmp/iasl-c.log; exit 1; }
rm -rf overlay; mkdir -p overlay/kernel/firmware/acpi
cp dsdt.aml overlay/kernel/firmware/acpi/dsdt.aml
( cd overlay && find kernel | cpio -o --format=newc --quiet ) > "$IMG"
cp dsdt.dsl dsdt.aml "$WORK/"
install -m 644 "$ROOT/configs/macbook-bt.cfg" /etc/default/grub.d/macbook-bt.cfg
update-grub
echo "Bluetooth DSDT updated. Reboot required."
