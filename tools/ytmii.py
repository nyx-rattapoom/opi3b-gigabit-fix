#!/usr/bin/env python3
# ytmii.py: MII / YT8531 ext-register access via SIOCxMIIREG
# usage: ytmii.py r REG | w REG VAL | er EXT | ew EXT VAL   (hex values)
import fcntl, socket, struct, sys
IF = b"eth0"
SIOCGMIIPHY, SIOCGMIIREG, SIOCSMIIREG = 0x8947, 0x8948, 0x8949
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
def ioc(cmd, phy=0, reg=0, val=0):
    buf = struct.pack("16sHHHH", IF, phy, reg, val, 0).ljust(40, b"\0")
    r = fcntl.ioctl(s, cmd, buf)
    return struct.unpack("16sHHHH", r[:24])[1:]
PHY = ioc(SIOCGMIIPHY)[0]
def rd(reg): return ioc(SIOCGMIIREG, PHY, reg)[3]
def wr(reg, v): ioc(SIOCSMIIREG, PHY, reg, v)
def erd(a): wr(0x1e, a); return rd(0x1f)
def ewr(a, v): wr(0x1e, a); wr(0x1f, v)
a = sys.argv[1:]
h = lambda x: int(x, 16)
if a[0] == "r": print("%04x" % rd(h(a[1])))
elif a[0] == "w": wr(h(a[1]), h(a[2]))
elif a[0] == "er": print("%04x" % erd(h(a[1])))
elif a[0] == "ew": ewr(h(a[1]), h(a[2])); print("%04x" % erd(h(a[1])))
elif a[0] == "dump":
    for x in (0xa000,0xa001,0xa003,0xa010,0xa012,0xa00c,0xa00d): print("%04x=%04x" % (x, erd(x)))
