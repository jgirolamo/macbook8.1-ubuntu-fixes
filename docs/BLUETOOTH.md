# Bluetooth on MacBook8,1

## Architecture

The Broadcom **BCM4350** is a combo chip:

- Wi‑Fi → PCIe (`brcmfmac`) — usually fine
- Bluetooth → UART on `PCI0.URT0` (`BCM2E7C` / `hci_uart_bcm`)

Two ACPI serdev children share that UART:

1. `SSDC` (`apple-uart-ssdc`) — SSD debug port (listed first)
2. `BLTH` (`BCM2E7C`) — real Bluetooth

Linux serdev only allows **one** slave per UART, so SSDC wins and Bluetooth never binds — unless SSDC `_STA` is forced to `Zero` via a DSDT override (early initrd).

## What works (validated)

After `05-bluetooth.sh` + `05b-bluetooth-crs.sh` and a reboot:

- `hci0` is **UP RUNNING** with a real BD address
- `bluetoothctl list` shows the controller
- dmesg may still log `Failed to set baudrate (-16)` and missing `brcm/BCM.hcd` — that is OK on this machine; the chip still initializes

## Fixes

### `05-bluetooth.sh`

1. **DSDT override** (`/boot/acpi_override_ssdc.img`) — hide SSDC, patch CRS/`_INI`
2. **GRUB** `GRUB_EARLY_INITRD_LINUX_CUSTOM=acpi_override_ssdc.img`
3. **DKMS** [leifliddy/macbook12-bluetooth-driver](https://github.com/leifliddy/macbook12-bluetooth-driver) patched `hci_uart`

### `05b-bluetooth-crs.sh`

Rebuilds the override without reinstalling DKMS:

- `SSDC._STA → Zero`
- `BLTH._CRS` always returns UART resources (stock DSDT returns a Darwin-only stub when Linux sets `_OSI("Darwin")`)
- `BLTH._INI` powers the chip (`BTPU`/`BTRS`/`BTLP`) and sets PCH **GPIO36** mux toward BT

Run **05b after 05** (or alone if DKMS is already installed). Reboot required.

## Verify after reboot

```bash
journalctl -b -k | grep 'Table Upgrade'
cat /sys/bus/serial/devices/serial0-0/firmware_node/path
# expect: \_SB_.PCI0.URT0.BLTH

rfkill list
hciconfig -a          # UP RUNNING, non-zero BD address
bluetoothctl list
```

## If still DOWN

1. Confirm patched module: `modinfo -n hci_uart` → under `updates/dkms/`
2. Flip GPIO36 mux polarity, rebuild, reboot:
   ```bash
   echo Zero | sudo tee /etc/macbook-bt-mux
   sudo ./scripts/05b-bluetooth-crs.sh
   sudo reboot
   ```
3. Optional: extract Broadcom BT `.hcd` from macOS / Boot Camp if you want to silence the firmware warning

## Uninstall override

```bash
sudo rm -f /boot/acpi_override_ssdc.img
sudo rm -f /etc/default/grub.d/macbook-bt.cfg
sudo update-grub
# optional: sudo /usr/local/src/macbook12-bluetooth-driver/install.bluetooth.sh -u
sudo reboot
```
