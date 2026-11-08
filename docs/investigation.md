# Investigation: Orange Pi 3B v1.1 gigabit TX dead on mainline

## Symptom

- Orange Pi 3B **v1.1**, RK3566, GMAC1 `fe010000.ethernet`, PHY Motorcomm **YT8531** (ID `4f51e91b`, IRQ=POLL).
- DietPi (Debian trixie), kernel `6.18.54-current-rockchip64`, DTB `rockchip/rk3566-orangepi-3b-v1.1.dtb`.
- Link negotiates **1000/Full**, but no unicast reply ever comes back (ARP stays `INCOMPLETE`).
- 100M works fine (~0.8 ms RTT, clean transfers), so a 100M cap was the stop-gap.
- The vendor OS (BSP 5.10 kernel) ran 1G on the same hardware, cable and switch port.

## Starting state on mainline

| Item | Value |
|------|-------|
| DT `phy-mode` | `rgmii-id`, no `tx_delay`/`rx_delay` |
| GRF_GMAC1_CON0 `0xFDC60388` (MAC delays) | `0x0` |
| GRF_GMAC1_CON1 `0xFDC6038C` | `0x13` (RGMII select + delay-line enable bits) |
| YT8531 ext `0xA003` (RGMII config 1) | `0x34fd`: PHY RX and TX delay ≈ 1.95 ns, TX clock not inverted |
| YT8531 ext `0xA001` (chip config) | `0x8000` |
| YT8531 ext `0xA012` (SyncE / CLK_OUT) | `0x0088`: **clock output disabled** |
| Pin drive strength `0xFDC60284/28C/298/29C` | u-boot baseline `0x707 / 0x303 / 0x703 / 0x307` |
| Clock tree | `clk_gmac1` ← `clk_mac1_2top` ← `cpll_125m` (internal), same parents as the vendor DT |

The vendor OS used `phy-mode = "rgmii"`, `tx_delay = <0x30>`, `rx_delay = <0x10>` in its DT, plus an
`rc.local` that wrote the drive-strength registers to level 5 and GRF_GMAC1_CON0 = `0xFFFF0049`.

## Method

Every test ran live at 1G without rebooting. PHY registers were accessed through `SIOCGMIIREG` /
`SIOCSMIIREG` (`tools/ytmii.py`; extended registers via reg `0x1E` address / `0x1F` data) and GRF registers via `/dev/mem`.
A test passed only if **unicast** replies arrived from the gateway (ARP neighbour flushed before each test).
`ethtool -S eth0` counter deltas separated TX from RX problems.

## Experiments

| # | Change (everything else at mainline default) | Result | Conclusion |
|---|------|--------|------------|
| 1 | None; counters during ping | MAC TX frames ↑, RX clean, 0 CRC errors | Fault is TX-only |
| 2 | PHY TX-clock inversion (`0xA003` bit 14) | 0 replies | Not it |
| 3 | PHY TX delay 0–15 (0–2.25 ns) × inversion on/off | 0 / 32 | PHY delay not the cause |
| 4 | EEE off (`ethtool --set-eee eth0 eee off`) | 0 replies | Not it |
| 5 | MAC TX delay `0x00–0x7c` (step 4) × 4 PHY configs, drive strength at level 5 | 0 / 128 | **No delay combination works** |
| 6 | Replicate the vendor BSP PHY init: `0xA012=0xd0`, ext `0x27` bit 15 cleared (auto-sleep off), ext `0xC` \|= 6 | 4 / 4 replies, with mainline delays | First working 1G TX |
| 7 | Same three registers, one at a time | only `0xA012=0xd0` works | **Root cause 1: PHY CLK_OUT** |
| 8 | Reboot with DT overlay (CLK_OUT) only; drive strength at baseline | 1G, **~69% loss** | Marginal signal |
| 9 | + drive strength level 5 (live, same link) | 0% loss / 5000 frames | **Root cause 2: pin drive strength** |
| 10 | Cold reboots, 10k × 1472 B flood, 3× Ookla speedtest | 0% loss, 0 CRC, ~930 / 803 Mbps | Stable |

## Root cause

1. **YT8531 125 MHz CLK_OUT is disabled on mainline.** The vendor BSP driver
   (`drivers/net/phy/motorcomm.c`, `yt8511_config_out_125m()`, applied to PHY ID `0x4f51e91b`)
   unconditionally writes ext `0xA012 = 0xd0`. Mainline's `yt8531_probe()` enables CLK_OUT only when the DT has
   `motorcomm,clk-out-frequency-hz`; without it, it writes "output disabled". The 3B v1.1 board evidently relies on
   that clock for the TX path, although the SoC clock tree reports an internal 125 MHz source.
2. **GMAC1 RGMII pin drive strength** at the u-boot baseline is too weak for 1G TX on this board revision
   (matches the vendor `rc.local` "temporary fix ether won't work" pokes and linux-orangepi#135).

Not causes: RGMII delays (mainline `rgmii-id` defaults are fine), TX-clock inversion, EEE, PHY auto-sleep,
ext `0xC` clock-select.

## Fix

- DT overlay `overlay/opi3b-gmac1-clkout.dts` adds `motorcomm,clk-out-frequency-hz = <125000000>` to
  `/ethernet@fe010000/mdio/ethernet-phy@1`; u-boot loads it through `user_overlays=` in `/boot/dietpiEnv.txt`.
  Mainline then writes `0xA012` = `(0x88 & ~0x5e) | 0x50` = `0xd0`.
- `gmac1-drive-strength.service` writes the four drive-strength registers at sysinit, before `network-pre.target`.

## Possible upstream fix

Add `motorcomm,clk-out-frequency-hz = <125000000>;` to the PHY node in
`arch/arm64/boot/dts/rockchip/rk3566-orangepi-3b-v1.1.dts`, and set the GMAC1 RGMII pinctrl groups to a level-5
drive-strength pcfg. Not yet submitted.
