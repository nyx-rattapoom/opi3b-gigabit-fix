#!/bin/sh
# rollback.sh - return to the proven 100M state. Run ON THE PI as root, then reboot.
set -u
OVL=opi3b-gmac1-clkout
ENV=/boot/dietpiEnv.txt; [ -f "$ENV" ] || ENV=/boot/armbianEnv.txt
cur=$(sed -n 's/^user_overlays=//p' "$ENV")
new=$(echo " $cur " | sed "s/ $OVL / /" | xargs)
sed -i "s/^user_overlays=.*/user_overlays=$new/" "$ENV"
echo "$(grep '^user_overlays=' "$ENV")"
systemctl disable --now gmac1-drive-strength.service 2>/dev/null
/usr/local/sbin/gmac1-drive-strength.py --reset 2>/dev/null
# watchdog v5 re-applies the 100M cap automatically once the overlay is gone (after reboot)
/usr/sbin/ethtool -s eth0 speed 100 duplex full autoneg on
echo "rolled back - reboot to drop the overlay; watchdog will keep eth0 at 100M"
