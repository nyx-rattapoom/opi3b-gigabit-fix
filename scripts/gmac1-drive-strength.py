#!/usr/bin/python3 -I
"""Orange Pi 3B v1.1: raise GMAC1 RGMII pin drive strength to level 5.

Without this, 1G TX loses ~70% of frames even with the PHY clk-out overlay.
Values are the vendor OS rc.local pokes (GRF bank-3 drive-strength registers;
upper 16 bits = write-enable mask). Self-contained: uses /dev/mem directly, no
vendor `io` binary needed.

usage: gmac1-drive-strength.py          apply (default)
       gmac1-drive-strength.py --show   print current values only
       gmac1-drive-strength.py --reset  restore u-boot baseline values
"""
import mmap
import os
import struct
import sys

GRF_BASE = 0xFDC60000
APPLY = {0x284: 0x3F3F3F3F, 0x28C: 0x003F003F, 0x298: 0x3F003F00, 0x29C: 0x3F3F3F3F}
# u-boot baseline readback 0x707/0x303/0x703/0x307 -> write with full mask
RESET = {0x284: 0xFFFF0707, 0x28C: 0xFFFF0303, 0x298: 0xFFFF0703, 0x29C: 0xFFFF0307}


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "--apply"
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    try:
        m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=GRF_BASE)
        writes = {"--apply": APPLY, "--reset": RESET, "--show": {}}.get(mode)
        if writes is None:
            print(__doc__)
            return 2
        for off, val in writes.items():
            struct.pack_into("<I", m, off, val)
        for off in sorted(APPLY):
            print("0x%08x = 0x%08x" % (GRF_BASE + off, struct.unpack_from("<I", m, off)[0]))
        m.close()
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
