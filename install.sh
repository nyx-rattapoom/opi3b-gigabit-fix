#!/bin/sh
# install.sh - apply the Orange Pi 3B v1.1 gigabit eth0 fix on DietPi/Armbian (mainline kernel).
# Run ON THE PI as root, from the repo directory:   sh install.sh
# Idempotent. Backups get suffix .bak-<date>. Reboot afterwards (the overlay is applied by u-boot).
set -eu
cd "$(dirname "$0")"
TS=$(date +%Y%m%d)
OVL=opi3b-gmac1-clkout
ENV=/boot/dietpiEnv.txt; [ -f "$ENV" ] || ENV=/boot/armbianEnv.txt

say() { printf '\n== %s\n' "$*"; }
bak() { [ -e "$1" ] && [ ! -e "$1.bak-$TS" ] && cp -a "$1" "$1.bak-$TS" || true; }

[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
grep -qa "orangepi-3b" /proc/device-tree/compatible || { echo "not an Orange Pi 3B - aborting"; exit 1; }
[ -f "$ENV" ] || { echo "no /boot/dietpiEnv.txt or armbianEnv.txt - boot script layout unknown"; exit 1; }
grep -q user_overlays /boot/boot.cmd || { echo "boot.cmd has no user_overlays support - aborting"; exit 1; }

say "dependencies"
command -v dtc >/dev/null || apt-get install -y device-tree-compiler
command -v python3 >/dev/null || apt-get install -y python3-minimal
command -v ethtool >/dev/null || apt-get install -y ethtool

say "1/4 DT overlay: YT8531 125 MHz CLK_OUT"
mkdir -p /boot/overlay-user
cp overlay/$OVL.dts /boot/overlay-user/
dtc -q -@ -I dts -O dtb -o /boot/overlay-user/$OVL.dtbo overlay/$OVL.dts
FDT=$(sed -n 's/^fdtfile=//p' "$ENV")
if [ -n "$FDT" ] && [ -f "/boot/dtb/$FDT" ]; then
    fdtoverlay -i "/boot/dtb/$FDT" -o /tmp/ovl-test.dtb /boot/overlay-user/$OVL.dtbo
    echo "overlay applies cleanly to $FDT: $(fdtget /tmp/ovl-test.dtb /ethernet@fe010000/mdio/ethernet-phy@1 motorcomm,clk-out-frequency-hz)"
    rm -f /tmp/ovl-test.dtb
fi
bak "$ENV"
cur=$(sed -n 's/^user_overlays=//p' "$ENV")
case " $cur " in
    *" $OVL "*) echo "user_overlays already contains $OVL" ;;
    *) new=$(echo "$cur $OVL" | xargs)
       if grep -q '^user_overlays=' "$ENV"; then sed -i "s/^user_overlays=.*/user_overlays=$new/" "$ENV"
       else echo "user_overlays=$new" >> "$ENV"; fi ;;
esac
grep '^user_overlays=' "$ENV"

say "2/4 pin drive strength service"
install -m 755 scripts/gmac1-drive-strength.py /usr/local/sbin/
rm -f /usr/local/sbin/gmac1-drive-strength.sh
install -m 644 systemd/gmac1-drive-strength.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now gmac1-drive-strength.service

say "3/4 eth0 watchdog v5 (100M cap only if overlay missing)"
bak /usr/local/sbin/eth0-watchdog.sh
install -m 755 scripts/eth0-watchdog.sh /usr/local/sbin/
install -m 644 systemd/eth0-watchdog.service systemd/eth0-watchdog.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable eth0-watchdog.timer

say "4/4 remove DietPi 100M force-speed unit (if present)"
U=/etc/systemd/system/ethtool_force_speed.service
if [ -f "$U" ]; then
    cp -a "$U" "/root/ethtool_force_speed.service.bak-$TS"
    systemctl disable ethtool_force_speed.service || true
    rm -f "$U"; systemctl daemon-reload
    echo "removed (backup in /root)"
else echo "not present"; fi

install -m 755 tools/ytmii.py /usr/local/sbin/

say "eth0 boot config"
if [ -f /etc/network/interfaces.d/eth0.conf ] && ! grep -Eq '^(auto|allow-hotplug) +eth0' /etc/network/interfaces.d/eth0.conf; then
    echo "WARNING: eth0.conf has no 'allow-hotplug eth0' - eth0 will only come up via the watchdog (~30s)."
fi

say "done - reboot, then run: sh verify.sh"
