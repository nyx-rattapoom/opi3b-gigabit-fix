#!/bin/sh
# verify.sh - check the gigabit fix is active and TX is clean. Run ON THE PI as root.
#   sh verify.sh            checks + 10k full-size flood ping to the gateway
#   sh verify.sh --quick    checks only
export PATH=$PATH:/usr/local/sbin
ok=0; bad=0
pass() { echo "PASS  $*"; ok=$((ok+1)); }
fail() { echo "FAIL  $*"; bad=$((bad+1)); }

v=$(fdtget /sys/firmware/fdt /ethernet@fe010000/mdio/ethernet-phy@1 motorcomm,clk-out-frequency-hz 2>/dev/null)
[ "$v" = 125000000 ] && pass "DT overlay live (clk-out $v)" || fail "DT overlay missing -> check user_overlays in /boot/dietpiEnv.txt"

v=$(ytmii.py er a012 2>/dev/null)
[ "$v" = 00d0 ] && pass "PHY CLK_OUT reg 0xA012=$v" || fail "PHY 0xA012=$v (want 00d0)"

v=$(gmac1-drive-strength.py --show 2>/dev/null | awk 'NR==1{print $3}')
[ "$v" = 0x00003f3f ] && pass "pin drive strength level 5 ($v)" || fail "drive strength $v (want 0x00003f3f) -> systemctl status gmac1-drive-strength"

v=$(ethtool eth0 2>/dev/null | sed -n 's/.*Speed: //p')
[ "$v" = 1000Mb/s ] && pass "link speed $v" || fail "link speed $v -> ethtool_force_speed.service back? dietpi-config 'force speed'?"

[ -e /etc/systemd/system/ethtool_force_speed.service ] && fail "ethtool_force_speed.service present (forces 100M)" || pass "no force-speed unit"

grep -Eqs '^(auto|allow-hotplug) +eth0' /etc/network/interfaces.d/eth0.conf /etc/network/interfaces \
    && pass "eth0 starts at boot" || echo "WARN  eth0.conf lacks allow-hotplug (watchdog brings it up ~30s after boot)"

if [ "${1:-}" != "--quick" ]; then
    gw=$(ip -4 route show dev eth0 | awk '/^default/{print $3; exit}')
    [ -n "$gw" ] || gw=$(ip -4 addr show eth0 | awk '/inet /{split($2,a,"."); print a[1]"."a[2]"."a[3]".1"; exit}')
    crc0=$(ethtool -S eth0 | awk '/ rx_crc_errors:/{print $2}')
    loss=$(ping -f -s 1472 -c 10000 -I eth0 "$gw" 2>/dev/null | sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p')
    crc1=$(ethtool -S eth0 | awk '/ rx_crc_errors:/{print $2}')
    [ "$loss" = 0 ] && pass "flood ping $gw: 10000 x 1472B, ${loss}% loss" || fail "flood ping $gw: ${loss}% loss"
    [ "$crc0" = "$crc1" ] && pass "no new CRC errors" || fail "CRC errors $crc0 -> $crc1"
fi
echo "---- $ok passed, $bad failed"
[ "$bad" = 0 ]
