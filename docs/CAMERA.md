# FaceTime HD camera (MacBook8,1)

The internal camera is Broadcom PCIe `14e4:1570`. Stock `facetimehd` assumes a
1280×720 MacBook**Pro** sensor; this 12-inch model is **848×588** (sensor 1675),
so streaming fails with SIF errors unless a patched driver is used.

## Install

```bash
sudo ./scripts/08-camera.sh
sudo reboot
```

That:

1. Adds `intel_iommu=off` (required for ISP DMA on this machine)
2. Extracts Apple firmware into `/lib/firmware/facetimehd/`
3. Installs patched `facetimehd` via DKMS ([thomas-shirley/macbook8.1-camera](https://github.com/thomas-shirley/macbook8.1-camera))

## Verify

```bash
ls -l /dev/video0
v4l2-ctl --list-formats-ext -d /dev/video0
ffplay /dev/video0
```

Expected size: **848×588** @ 30 fps.

Optional colour calibration file `1675_01XX.dat` improves colours if present under
`/lib/firmware/facetimehd/` (see upstream README / Boot Camp extract). Not required
for a working picture.
