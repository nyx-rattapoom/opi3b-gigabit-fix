# opi3b-gigabit-fix

Restores **1 Gbit/s on eth0** for the **Orange Pi 3B v1.1** (RK3566 + Motorcomm YT8531 PHY) on
DietPi / Armbian with a **mainline** kernel (tested on 6.18.54-current-rockchip64, 2026-11-08).

## Root cause

Mainline negotiates 1G but TX is dead (RX is fine). It needs two things the vendor BSP did and mainline doesn't:

1. **PHY 125 MHz CLK_OUT**: the YT8531 must drive its clock output (ext reg `0xA012 = 0xd0`).
   Mainline enables it only if the DT asks, via `motorcomm,clk-out-frequency-hz`, and the 3B v1.1 DT doesn't.
   Without it: 100% TX loss at 1G, whatever the delays.
2. **GMAC1 pin drive strength level 5**: at the u-boot baseline, 1G TX loses ~70% of frames.

RGMII delays were **not** the problem: mainline defaults (`rgmii-id`, PHY `0xA003=0x34fd`, MAC delay 0) are fine.

## Result

| Test | Result |
|------|--------|
| Link | 1000 Mb/s Full |
| Flood ping, 10,000 × 1472 B | 0% loss, 0 CRC errors |
| Ookla speedtest ×3 | ~930 Mbps down / ~803 Mbps up, 0% loss |
| Cold reboots | 3, fix applied automatically each time |

## Layout

| Path | What |
|------|------|
| `overlay/opi3b-gmac1-clkout.dts` | DT overlay → `/boot/overlay-user/`, enabled via `user_overlays=` |
| `scripts/gmac1-drive-strength.py` + `systemd/gmac1-drive-strength.service` | sets pin drive strength early in boot via `/dev/mem` (`--show`, `--reset`) |
| `scripts/eth0-watchdog.sh` + `systemd/eth0-watchdog.{service,timer}` | v5: recovers eth0 every 15 s; caps 100M **only** if the overlay is missing |
| `tools/ytmii.py` | MII / YT85xx extended-register read/write (`r`, `w`, `er`, `ew`, `dump`) |
| `install.sh` / `verify.sh` / `rollback.sh` | apply / check / undo (run on the Pi as root) |
| `RUNBOOK.md` | **what to do next time**: reinstall, diagnose, rollback |
| `docs/investigation.md` | evidence, register dumps, experiment table |
| `docs/report.html` | visual report (diagram, experiment table, change list) |

## Quick start

```sh
scp -r opi3b-gigabit-fix root@<pi>:/root/
ssh root@<pi> 'cd /root/opi3b-gigabit-fix && sh install.sh'
ssh root@<pi> 'systemd-run --on-active=3 /bin/systemctl reboot'
ssh root@<pi> 'sh /root/opi3b-gigabit-fix/verify.sh'
```

## References

- orangepi-xunlong/linux-orangepi#135 (YT8531 on 3B v1.1; drive-strength pokes)
- armbian/build#7490
- Vendor BSP driver `drivers/net/phy/motorcomm.c` (orange-pi-5.10-rk35xx): `yt8511_config_out_125m()` writes `0xA012=0xd0`
