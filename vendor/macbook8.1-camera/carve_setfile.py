#!/usr/bin/env python3
import struct, re
SYS = "sys_extract/AppleCamera64/AppleCamera.sys"
data = open(SYS, "rb").read()
IMAGEBASE = 0x140000000
SECTIONS = [
    (".text",  0x140001000, 0x000400, 0x1459f),
    (".rdata", 0x140016000, 0x014a00, 0x15cd24),
    (".data",  0x140173000, 0x171800, 0x5f400),
    (".pdata", 0x1401d3000, 0x1d0c00, 0xaf8),
]
def off_to_vma(off):
    for n,vma,fo,sz in SECTIONS:
        if fo <= off < fo+sz: return vma+(off-fo)
def vma_to_off(vma):
    for n,base,fo,sz in SECTIONS:
        if base <= vma < base+sz: return fo+(vma-base)

strings = {}
for m in re.finditer(rb'/usr/local/share/firmware/isp/(\d{4})_01XX\.dat', data):
    strings[m.group(1).decode()] = (m.start(), off_to_vma(m.start()))

print("=== 4-byte RVA refs to each path string (lea rip-relative would NOT match; this finds data-table RVAs) ===")
for sid,(off,vma) in sorted(strings.items()):
    rva = vma - IMAGEBASE
    needle = struct.pack("<I", rva)
    hits = [i for i in range(0,len(data)-4) if data[i:i+4]==needle]
    print("  %s rva=0x%x hits=%s" % (sid, rva, [hex(h) for h in hits]))

print("\n=== hex dump right AFTER the string cluster (0x14770..0x14a00) ===")
region = data[0x147a0:0x14a00]
for i in range(0, len(region), 16):
    chunk = region[i:i+16]
    hx = " ".join("%02x"%b for b in chunk)
    asc = "".join(chr(b) if 32<=b<127 else "." for b in chunk)
    print("  0x%06x  %-47s  %s" % (0x147a0+i, hx, asc))

print("\n=== search for RIP-relative lea displacements to 1675 string in .text ===")
# lea reg,[rip+disp32]: 48/4C 8D xx disp32 ; instr_end = addr_of_disp+4; target = instr_end + disp
vma1675 = strings['1675'][1]
for off in range(0x400, 0x1459f):
    disp = struct.unpack_from("<i", data, off)[0]
    instr_end_vma = off_to_vma(off+4)
    if instr_end_vma and instr_end_vma + disp == vma1675:
        print("  disp32@0x%x -> references 1675 string (instr near 0x%x)" % (off, off-3))
