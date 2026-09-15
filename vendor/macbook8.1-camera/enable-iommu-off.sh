#!/usr/bin/env bash
# Add intel_iommu=off so the FaceTime HD camera's ISP DMA command channel works.
# Run with: sudo bash enable-iommu-off.sh   (then reboot)
set -euo pipefail

GRUB=/etc/default/grub
KEY=GRUB_CMDLINE_LINUX_DEFAULT
PARAM=intel_iommu=off

cp -a "$GRUB" "$GRUB.bak.$(date +%Y%m%d-%H%M%S)"
echo "Backed up $GRUB"

if grep -qE "^${KEY}=.*\b${PARAM}\b" "$GRUB"; then
    echo "$PARAM already present, nothing to change."
else
    # Insert PARAM just inside the closing quote of the existing value
    sed -i -E "s|^(${KEY}=\")(.*)(\")|\1\2 ${PARAM}\3|" "$GRUB"
    # Tidy any accidental leading space inside the quotes
    sed -i -E "s|^(${KEY}=\") +|\1|" "$GRUB"
    echo "Added $PARAM"
fi

echo "--- new line ---"
grep -E "^${KEY}=" "$GRUB"

echo "--- updating grub ---"
if command -v update-grub >/dev/null; then update-grub; else grub-mkconfig -o /boot/grub/grub.cfg; fi

echo
echo "DONE. Reboot for it to take effect:  sudo reboot"
