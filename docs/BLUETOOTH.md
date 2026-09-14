# Bluetooth on MacBook8,1

## Architecture

The Broadcom **BCM4350** is a combo chip:

- Wi‑Fi → PCIe (`brcmfmac`) — usually fine
- Bluetooth → UART on `PCI0.URT0` (`BCM2E7C` / `hci_uart_bcm`)

Two ACPI serdev children share that UART:

1. `SSDC` (`apple-uart-ssdc`) — SSD debug port (listed first)
2. `BLTH` (`BCM2E7C`) — real Bluetooth

Linux serdev only allows **one** slave per UART, so SSDC wins and Bluetooth never binds — unless SSDC `_STA` is forced to `Zero` via a DSDT override (early initrd).

## Fixes in `05-bluetooth.sh`

1. **DSDT override** (`/boot/acpi_override_ssdc.img`)
   - `SSDC._STA → Zero`
   - `BLTH._CRS` always returns UART resources (stock DSDT returns a Darwin-only stub when Linux sets `_OSI("Darwin")` on Apple hardware)
   - `BLTH._INI` powers the chip (`BTPU`/`BTRS`) and sets PCH **GPIO36** mux toward BT
2. **GRUB** `GRUB_EARLY_INITRD_LINUX_CUSTOM=acpi_override_ssdc.img`
3. **DKMS** [leifliddy/macbook12-bluetooth-driver](https://github.com/leifliddy/macbook12-bluetooth-driver) patched `hci_uart`

## Verify after reboot

```bash
# Override applied?
journalctl -b -k | grep 'Table Upgrade'

# Bound to Bluetooth, not SSDC?
cat /sys/bus/serial/devices/serial0-0/firmware_node/path
# expect: \_SB_.PCI0.URT0.BLTH

rfkill list
hciconfig -a
bluetoothctl list
```

## If still DOWN

Symptoms we still saw: `No reset resource`, `failed to write update baudrate (-110)`.

Things to try:

1. Confirm patched module: `modinfo -n hci_uart` should be under `updates/dkms/`
2. Confirm `_CRS` patch took (no Darwin stub) by rebuilding override from this repo’s script
3. Try the other GPIO36 polarity in DSDT (`GP36 = Zero` instead of `One`)
4. Extract Broadcom BT `.hcd` firmware from macOS / Boot Camp if the driver requests it

## Uninstall override

```bash
sudo rm -f /boot/acpi_override_ssdc.img
sudo rm -f /etc/default/grub.d/macbook-bt.cfg
sudo update-grub
# optional: sudo /usr/local/src/macbook12-bluetooth-driver/install.bluetooth.sh -u
sudo reboot
```
