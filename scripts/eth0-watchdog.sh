#!/bin/sh
# eth0-watchdog (v5): keeps eth0 usable on this ifupdown-only Orange Pi 3B v1.1.
# 1) gigabit guard: 1G TX works only when the YT8531 drives its 125 MHz CLK_OUT
#    (ext reg 0xA012=0xd0), set by DT overlay
#    /boot/overlay-user/opi3b-gmac1-clkout.dtbo (user_overlays= in
#    /boot/dietpiEnv.txt). If the live DT lacks that property (overlay lost),
#    fall back to the 100M cap - 1G TX would be dead.
# 2) recovers after cable/link events (ifupdown state may be stale when the
#    interface was bounced below ifupdown's radar, hence --force everywhere):
#    - admin-down         -> ifup --force
#    - admin-up, no IPv4  -> ifdown --force + ifup --force
# Never touches other interfaces (e.g. a usb0 fallback link must not bounce).
IFACE=eth0
SYS=/sys/class/net/$IFACE
ETHTOOL=/usr/sbin/ethtool
IFUP=/usr/sbin/ifup
IFDOWN=/usr/sbin/ifdown
CLKOUT=/proc/device-tree/ethernet@fe010000/mdio/ethernet-phy@1/motorcomm,clk-out-frequency-hz

[ -d "$SYS" ] || exit 0

if [ ! -e "$CLKOUT" ]; then
    speed=$("$ETHTOOL" "$IFACE" 2>/dev/null | sed -n "s/^Speed: //p")
    if [ "$speed" != "100Mb/s" ]; then
        logger -t eth0-watchdog "clk-out overlay missing, speed '$speed' -> forcing 100M cap"
        "$ETHTOOL" -s "$IFACE" speed 100 duplex full autoneg on
    fi
fi

if [ "$(cat "$SYS/operstate" 2>/dev/null)" != "up" ]; then
    logger -t eth0-watchdog "$IFACE admin-down -> ifup --force"
    "$IFUP" --force "$IFACE"
    exit 0
fi

[ -n "$(ip -4 -o addr show dev "$IFACE" 2>/dev/null)" ] || {
    logger -t eth0-watchdog "$IFACE admin-up but no IPv4 -> reconfigure"
    "$IFDOWN" --force "$IFACE" 2>/dev/null
    "$IFUP" --force "$IFACE"
}
