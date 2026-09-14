# OpenCore / dual-boot notes

This machine often has:

- ESP (`/boot/efi`) with **OpenCore** (`EFI/OC`) + **Ubuntu** (`EFI/ubuntu`) + fallback `EFI/BOOT/BOOTX64.EFI`
- Large **APFS** partition still holding macOS

## Why OpenCore showed two “EFI” entries

`EFI/BOOT/BOOTX64.EFI` is the same binary as `EFI/ubuntu/shimx64.efi`. Without flavour/name files, OpenCore lists both as generic “EFI”, plus macOS from APFS.

## Names + icons (Ubuntu / Linux)

```bash
sudo ./scripts/06-opencore-labels.sh
```

That script:

- Sets `EFI/ubuntu/.contentDetails` → **Ubuntu** and flavour `Ubuntu:Linux:Other`
- Sets `EFI/BOOT/.contentDetails` → **Linux** and flavour `Linux:Ubuntu:Other`
- Installs `Ubuntu.icns` / `Linux.icns` into OpenCanopy’s GoldenGate theme
- Enables flavour icons + custom labels in `config.plist` (`PickerAttributes`)

Reboot through OpenCore to see the new labels. macOS is unchanged.

To hide the fallback instead of renaming it:

```bash
printf 'Disabled\n' | sudo tee /boot/efi/EFI/BOOT/.contentVisibility
```

## Apple Option (⌥) picker

Two disks/loaders there usually means OpenCore’s blessed loader and Ubuntu’s — expected with this ESP layout. The `.content*` files only affect the **OpenCore** picker, not Apple’s firmware menu.
