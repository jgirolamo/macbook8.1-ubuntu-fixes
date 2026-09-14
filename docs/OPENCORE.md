# OpenCore / dual-boot notes

This machine often has:

- ESP (`/boot/efi`) with **OpenCore** (`EFI/OC`) + **Ubuntu** (`EFI/ubuntu`) + fallback `EFI/BOOT/BOOTX64.EFI`
- Large **APFS** partition still holding macOS

## Why OpenCore shows two EFI entries

`EFI/BOOT/BOOTX64.EFI` is the same binary as `EFI/ubuntu/shimx64.efi`. OpenCore lists both as generic “EFI”, plus macOS from APFS.

To hide the fallback copy (optional):

```bash
printf 'Disabled\n' | sudo tee /boot/efi/EFI/BOOT/.contentVisibility
printf 'Ubuntu:Linux:Other\n' | sudo tee /boot/efi/EFI/ubuntu/.contentFlavour
```

To show the fallback again:

```bash
sudo rm -f /boot/efi/EFI/BOOT/.contentVisibility
```

macOS is unaffected either way.

## Apple Option (⌥) picker

Two disks/loaders there usually means OpenCore’s blessed loader and Ubuntu’s — expected with this ESP layout.
