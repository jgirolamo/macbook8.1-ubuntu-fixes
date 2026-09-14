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
| Speakers | CS4208 pins disabled | HDA pin patch (`cs4208-macbook.fw`) |
| Bluetooth | SSDC steals UART; Darwin `_CRS` stub | DSDT override + DKMS `hci_uart` |
| OpenCore | Two “EFI” tiles | Documented (optional) |

## Quick install (next Ubuntu install)

```bash
git clone git@github.com:YOUR_USER/macbook8.1-ubuntu-fixes.git
cd macbook8.1-ubuntu-fixes
sudo ./scripts/install-all.sh
sudo reboot
```

Local copy on this machine: `~/Projects/macbook8.1-ubuntu-fixes`
```

Or run steps one by one:

```bash
sudo ./scripts/01-base-tune.sh      # kdump off, UFW, zram, ModemManager
sudo ./scripts/02-sleep.sh          # s2idle + NVMe APST quirk
sudo ./scripts/03-speakers.sh       # CS4208 speaker pins
sudo ./scripts/04-applespi.sh       # keyboard/touchpad recovery
sudo ./scripts/05-bluetooth.sh      # SSDC DSDT override + DKMS driver
sudo reboot
```

After reboot, check:

```bash
free -h                    # ~7.7 GiB if kdump gone
cat /sys/power/mem_sleep   # [s2idle]
rfkill list
bluetoothctl list          # may still need CRS/mux work — see docs/BLUETOOTH.md
wpctl status               # speakers / Built-in Audio
```

## Hardware notes

- **CPU**: Intel Core M-5Y51 (fanless) — keep loads modest  
- **Wi‑Fi + BT**: Broadcom BCM4350 combo (PCIe Wi‑Fi works; BT is UART)  
- **Audio**: Cirrus CS4208 (`106b:6400`)  
- **Input**: `applespi` keyboard + Force Touch pad  
- **Disk**: often shared ESP with OpenCore + leftover APFS volume  

## Repo layout

```
configs/     drop-in files installed by the scripts
scripts/     installers (idempotent where possible)
docs/        deeper notes (Bluetooth, OpenCore, recovery)
```

## Status / known gaps

- **Bluetooth**: SSDC override + DKMS install; adapter still may stay DOWN until BLTH `_CRS` Darwin stub / GPIO36 mux is fixed — see `docs/BLUETOOTH.md`.
- **Camera**: FaceTime HD needs `facetimehd` DKMS + firmware (not automated here yet).
- **SPI keyboard**: if dead after soft reboot, **Shut Down** or hold power ~10 s.

## License

MIT — use at your own risk. ACPI/DSDT overrides and out-of-tree modules can brick a boot if mis-applied; keep a USB installer handy.
