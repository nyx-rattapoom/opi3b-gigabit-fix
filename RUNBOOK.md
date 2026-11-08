# Runbook: Orange Pi 3B gigabit eth0 (next time)

Board: Orange Pi 3B **v1.1**, RK3566, PHY Motorcomm **YT8531** (ID `4f51e91b`), DietPi / mainline kernel.
Placeholders: `<pi-ip>` = the Pi's eth0 address, `<router-ip>` = your gateway, `<pi-mac>` = eth0 MAC (`cat /sys/class/net/eth0/address`).
Keep a second way in (USB gadget, Wi-Fi, serial console) while experimenting with eth0.

## Path A: fresh OS install / reflash (≈5 min)

1. Boot DietPi, get a shell (eth0 works at 100M out of the box; usb0 or Wi-Fi also work).
2. Copy this repo to the Pi and install:
   ```sh
   scp -r opi3b-gigabit-fix root@<pi>:/root/
   ssh root@<pi> 'cd /root/opi3b-gigabit-fix && sh install.sh'
   ```
3. Reboot: `ssh root@<pi> 'systemd-run --on-active=3 /bin/systemctl reboot'`
   (a plain `ssh … reboot` can hang the SSH session).
4. Verify: `ssh root@<pi> 'sh /root/opi3b-gigabit-fix/verify.sh'` should print all PASS, 0% loss.
5. Network identity (see Path C) if the MAC changed.

## Path B: gigabit stopped working (diagnose in this order)

| # | Check | Expect | If not |
|---|-------|--------|--------|
| 1 | `sh verify.sh --quick` | all PASS | follow the FAIL hint |
| 2 | `ethtool eth0 \| grep Speed` | `1000Mb/s` | `ls /etc/systemd/system/ethtool_force_speed.service`: dietpi-config "Ethernet force speed" re-creates it, so delete it or set it to Auto |
| 3 | `fdtget /sys/firmware/fdt /ethernet@fe010000/mdio/ethernet-phy@1 motorcomm,clk-out-frequency-hz` | `125000000` | `grep user_overlays /boot/dietpiEnv.txt` must list `opi3b-gmac1-clkout`; `.dtbo` must exist in `/boot/overlay-user/`. Reboot. (The watchdog caps 100M meanwhile.) |
| 4 | `ytmii.py er a012` | `00d0` | Live hotfix: `ytmii.py ew a012 00d0` |
| 5 | `gmac1-drive-strength.py --show` | `0x00003f3f…` | `systemctl status gmac1-drive-strength`; live hotfix: `gmac1-drive-strength.py` |
| 6 | `ip -br a show eth0` has an IP | yes | `eth0.conf` needs `allow-hotplug eth0`; the watchdog does `ifup --force` within 30s |

Symptom map:
- **1G link, zero replies** (ARP `INCOMPLETE`): CLK_OUT is off (check 3/4).
- **1G link, 30–70% loss**: drive strength is at baseline (check 5).
- **Stuck at 100M**: force-speed unit, or the watchdog cap because the overlay is missing (check 2/3).

Things that are **not** the cause (proven by 160 sweep combinations, see `docs/investigation.md`):
MAC/PHY RGMII delays, TX-clock inversion, EEE, PHY auto-sleep.

## Path C: fixed IP via a DHCP reservation (OpenWrt example)

- The router reserves the Pi's IP by MAC: `ssh root@<router-ip> 'uci show dhcp | grep -A3 <hostname>'`
- DietPi/Armbian gives eth0 a locally-administered MAC that stays the same across reboots but **differs from the vendor OS MAC**,
  so a reservation made under the vendor OS stops matching. Update it after a reflash:
  ```sh
  uci set dhcp.@host[<N>].mac='<pi-mac>'; uci commit dhcp; service dnsmasq restart
  ```
  then renew on the Pi (detached so it survives the eth0 bounce):
  `systemd-run /bin/sh -c '/usr/sbin/ifdown --force eth0; /usr/sbin/ifup --force eth0'`
- DHCP pushes the reservation name as the hostname, so keep `/etc/hostname`, `/etc/hosts` (127.0.1.1) and
  `AUTO_SETUP_NET_HOSTNAME` in `/boot/dietpi.txt` the same as the reservation name, or the hostname changes on each lease renewal.
- SSH `known_hosts` complains after a reflash: compare fingerprints first, then
  `ssh-keygen -R <pi-ip>`.

## Path D: roll back to the known-good 100M state

`sh rollback.sh` then reboot. The watchdog keeps eth0 at 100M while the overlay is absent.

## Safety rules learned

- **Never bounce your fallback interface** (e.g. usb0): it's the backup way into the Pi.
- Stop the watchdog before 1G experiments on a broken setup (`systemctl stop eth0-watchdog.timer`) and restart it afterwards.
- dietpi-config / dietpi-network **regenerate** `/etc/network/interfaces.d/*.conf`, so check them after anyone uses the menu.
- Use unfiltered `tcpdump` and `ethtool -S eth0` counter deltas to tell TX from RX failures.
