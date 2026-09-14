# MacBook8,1 Ubuntu fixes

Scripts and configs for **Apple MacBook8,1** (12-inch Retina, early 2015) on **Ubuntu 26.04+**.

Tested on: Ubuntu 26.04.1 LTS, kernel 7.0, dual-boot with OpenCore Legacy Patcher + macOS APFS.

## Why this exists

A fresh Ubuntu install works, but this machine needs several Mac-specific and 8 GB-RAM tweaks:

| Area | Problem | Fix |
|------|---------|-----|
| RAM | `kdump` reserves ~512 MB | Disable crashkernel |
| Swap | Disk swap only | zram + 8 GB swap file |
| Firewall | UFW installed but off | Enable deny-in/allow-out |
| Sleep | S3 `deep` hangs / kills SPI | Force `s2idle` |
| Keyboard | SPI timeouts after reboot | Delay load + recover service |
| Speakers | CS4208 TDM amp silent | DKMS [macbook8.1-speaker-driver](https://github.com/thomas-shirley/macbook8.1-speaker-driver) |
| Bluetooth | SSDC steals UART; Darwin `_CRS` stub | DSDT override (`05`/`05b`) + DKMS `hci_uart` |
| Battery | No charge ceiling (AlDente) | `applesmc-next` + **MacBook Battery** dashboard |
| OpenCore | Two generic “EFI” tiles | Labels/icons via `06-opencore-labels.sh` |

## Quick install (next Ubuntu install)

```bash
git clone https://github.com/jgirolamo/macbook8.1-ubuntu-fixes.git
cd macbook8.1-ubuntu-fixes
sudo ./scripts/install-all.sh
sudo reboot
```

Repo: https://github.com/jgirolamo/macbook8.1-ubuntu-fixes  
Local copy: `~/Projects/macbook8.1-ubuntu-fixes`

Or run steps one by one:

```bash
sudo ./scripts/01-base-tune.sh         # kdump off, UFW, zram, ModemManager
sudo ./scripts/02-sleep.sh             # s2idle + NVMe APST quirk
sudo ./scripts/03-speakers.sh          # TDM speaker DKMS (thomas-shirley)
sudo ./scripts/04-applespi.sh          # keyboard/touchpad recovery
sudo ./scripts/05-bluetooth.sh         # SSDC DSDT + DKMS hci_uart
sudo ./scripts/05b-bluetooth-crs.sh    # BLTH _CRS + mux/_INI (required)
sudo ./scripts/06-opencore-labels.sh   # Ubuntu / Linux picker names (optional)
sudo ./scripts/07-battery-dashboard.sh # charge limit + dashboard
sudo reboot
```

After reboot, check:

```bash
free -h                              # ~7.7 GiB if kdump gone
cat /sys/power/mem_sleep             # [s2idle]
bluetoothctl list                    # controller present, UP
wpctl status | grep -i MacBook       # input.MacBook_Speaker
macbook-battery                      # charge-limit dashboard
```

## Hardware notes

- **CPU**: Intel Core M-5Y51 (fanless) — keep loads modest  
- **Wi‑Fi + BT**: Broadcom BCM4350 combo (PCIe Wi‑Fi works; BT is UART)  
- **Audio**: Cirrus CS4208 TDM → class-D amp (`input.MacBook_Speaker`)  
- **Input**: `applespi` keyboard + Force Touch pad  
- **Disk**: often shared ESP with OpenCore + leftover APFS volume  

## Repo layout

```
apps/        MacBook Battery dashboard
configs/     drop-in files installed by the scripts
scripts/     installers (idempotent where possible)
docs/        deeper notes (Bluetooth, OpenCore)
```

## Status / known gaps

Validated working on this machine after reboot: **speakers**, **Bluetooth**, **battery charge limit**, **OpenCore Ubuntu/Linux labels**.

- **Camera**: FaceTime HD needs `facetimehd` DKMS + firmware (not automated here yet).
- **SPI keyboard**: if dead after soft reboot, **Shut Down** or hold power ~10 s.
- **BT firmware**: dmesg may show missing `brcm/BCM.hcd` and a benign baud-change `-16`; controller still comes UP.

## License

MIT — use at your own risk. ACPI/DSDT overrides and out-of-tree modules can brick a boot if mis-applied; keep a USB installer handy.
