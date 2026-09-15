# FaceTime HD camera on the 12-inch MacBook (MacBook8,1) under Linux

This repo gets the **internal FaceTime HD camera working on the 2015 12-inch
Retina MacBook (`MacBook8,1`)** on modern Linux — a configuration that the
upstream `bcwc_pcie`/`facetimehd` driver has **never** supported. Every other
12-inch attempt (MacBook 8,1 / 9,1 / 10,1) ends in a black/green image and a
flood of firmware `SIF errors`. This documents the root cause and the small
driver patch that fixes it.

> **TL;DR** — Two driver bugs broke the 12-inch MacBook camera:
> 1. **Geometry:** the sensor (Broadcom ID **1675**) is **848×588**, but
>    `bcwc_pcie` hardcodes **1280×720** (the MacBook*Pro* size). Commanding the
>    smaller sensor to produce 1280×720 makes the ISP's sensor interface fault on
>    every frame, so nothing streams.
> 2. **Framerate:** the driver advertised an inconsistent rate (25 fps via
>    `VIDIOC_G_PARM`, 30 fps via `enum_frameintervals`) while delivering 30 fps.
>    GStreamer/PipeWire then computes a negative frame duration and stalls after
>    one frame — so apps like GNOME Camera froze even though `ffplay` worked.
>
> The fix makes the driver **read the sensor's real geometry from the firmware**
> (so it works on both the 12-inch and MacBookPro) and report a **consistent
> 30 fps**. Result: a clean, smooth stream in every app.

---

## Result

```
set crop:      [0, 0] -> [848, 588]
output config: [848, 588]
SIF errors:    0
5 frames @ 30 fps, 997248 bytes each   # 848 * 588 * 2 (YUYV)
```

---

## Hardware

| | |
|---|---|
| Machine | Apple `MacBook8,1` (12-inch Retina, early 2015) |
| Camera | Apple FaceTime HD, Broadcom 1570 (PCIe `14e4:1570`) |
| Sensor | ID **1675** (driver reads `sensor_id1=0x9774, sensor_id0=5`) |
| Native resolution | **848 × 588** (reported by firmware, *not* 720p) |
| OS tested | Ubuntu, kernel 6.17 |

---

## Quick start

```bash
# 1. The ISP's DMA command channel needs the IOMMU off. Adds intel_iommu=off
#    to the kernel cmdline, then reboot.
sudo bash enable-iommu-off.sh
sudo reboot

# 2. Install firmware + the patched driver via DKMS (survives kernel updates).
sudo bash install.sh

# 3. Test it.
ffplay /dev/video0          # or use Cheese, a browser, OBS, etc.
```

The firmware (`facetimehd-firmware/firmware.bin`) is extracted from Apple's
macOS driver; the kernel module lives in `bcwc_pcie/` and is **patched** (see
below). After install the camera appears as `/dev/video0` and is picked up
automatically by PipeWire/WirePlumber, so GNOME apps and browsers can use it.

---

## What was actually wrong

### Symptom

The driver loaded fine — firmware uploaded, ISP booted, `/dev/video0` appeared,
PipeWire enumerated the camera. But the moment anything tried to **stream**, the
firmware logged this pair on every frame interval and delivered zero frames:

```
FWMSG: ERR: ./H4ISPCD/filters/IC/CImageCaptureH4.cpp, 777:  SIF errors: sifIrq = 0x804!
FWMSG: ERR: ./H4ISPCD/filters/IC/CImageCaptureH4.cpp, 2312: Meta data buffer unavailable!
...
facetimehd 0000:02:00.0: IO: timeout
```

`SIF` = **S**ensor **I**nter**F**ace. `sifIrq = 0x804` means the sensor was not
delivering valid pixel data into the ISP. "Meta data buffer unavailable" is the
downstream consequence (no frame → no metadata).

### Root cause

The driver was reverse-engineered against MacBook**Pro** cameras, which are true
**1280×720** sensors, and it hardcodes that resolution throughout the V4L2 layer
and the channel-start sequence.

Enabling the driver's dynamic debug and dumping the firmware's
`CISP_CMD_CH_CAMERA_CONFIG_GET` response revealed the 12-inch sensor's real
geometry:

```
CAMCONF0 00000000: 00 00 00 00 00 00 00 00 50 03 4c 02 50 03 4c 02
                   └ unknown ─┘└ channel ─┘ └848─┘└588─┘└848─┘└588─┘
                                            (0x0350) (0x024c)  little-endian u16
```

So the sensor is **848×588**. The driver was sending:

```
set crop:      [0, 0] -> [1280, 720]      # exceeds the 848×588 sensor array
output config: [1280, 720]
```

Cropping a region larger than the physical sensor makes the sensor interface
fault — hence the endless `SIF errors`. On a MacBookPro the hardcoded 1280×720
*matches* the sensor, which is the only reason it works there.

### Fix 1 — use the sensor's real geometry (dynamically)

Rather than hardcode any resolution, the driver now **reads the sensor's native
size from the firmware** and uses it everywhere, so the same driver serves the
12-inch (848×588) *and* MacBookPro (1280×720):

- **`fthd_isp.c`** (`fthd_isp_cmd_channel_camera_config`) — parse the width/height
  out of the `CISP_CMD_CH_CAMERA_CONFIG_GET` reply (`data[0]` = u16 width,
  `data[2]` = u16 height) and store them in `dev_priv->sensor_width/height`.
- **`fthd_drv.c`** (`fthd_firmware_start`) — call that query at probe, right after
  sensor detection, so the size is known before the V4L2 device registers.
- **`fthd_v4l2.c`** — the default format, `enum_framesizes`, `enum_frameintervals`
  and `adjust_format` all use `dev_priv->sensor_width/height` (falling back to a
  generic 1280×720 ceiling only if detection didn't run).
- **`fthd_isp.c`** (`fthd_start_channel`) — crop the negotiated format size
  instead of a hardcoded 1280×720 region:
  ```c
  x1 = 0;
  x2 = dev_priv->fmt.fmt.width;
  ret = fthd_isp_cmd_channel_crop_set(dev_priv, 0, x1, 0, x2,
                                      dev_priv->fmt.fmt.height);
  ```

The V4L2 format and the crop **must** agree, because `dev_priv->fmt` also drives
the output-config command and the videobuf2 buffer sizes; a mismatch just trades
the SIF error for a buffer-size error.

### Fix 2 — report a consistent framerate

The driver advertised **two different framerates** while delivering 30 fps:
`VIDIOC_G_PARM` returned `frametime/1000` = **25 fps**, but `enum_frameintervals`
returned **30 fps**. GStreamer's `pipewiresrc` used these to compute frame
durations, hit a negative value (`_gst_util_uint64_scale_int: assertion
'num >= 0' failed`), stopped recycling buffers, and — with the driver's fixed
pool of 4 buffers — starved after the first frame. `ffplay`/`v4l2-ctl` ignore the
framerate metadata, so only the GStreamer/PipeWire path (GNOME Camera, browsers)
froze.

**`fthd_v4l2.c`** (`g_parm`) now reports a fixed, honest **30 fps** matching the
sensor and `enum_frameintervals`:
```c
struct v4l2_fract timeperframe = { .numerator = 1, .denominator = 30 };
```

---

## Dead ends (things the internet blames that are **not** the problem)

We chased and definitively ruled these out — documented here so nobody else
wastes time on them:

| Suspect | Verdict |
|---|---|
| Missing `1675_01XX.dat` "set file" | **Red herring.** It's optional sensor *calibration* (affects color/exposure), applied *after* frames flow. The driver streams fine on MacBookPro with **no** set files installed. A SIF error happens before calibration is ever relevant. |
| `intel_iommu` / DMA | Needed (`intel_iommu=off`), but already handled; not the streaming fault. |
| "Failed to lock S2 PLL: 0xc902c902" | **Cosmetic logging bug.** The PLL polling loop in `fthd_hw.c` is inverted (`S2_PLL_CMU_STATUS_LOCKED = 1<<15`; the lock bit is actually set). The clock is fine — DDR memory verification passes right after. |
| Buffer allocation | Fine — `REQBUFS`/`QBUF`/`STREAMON` all succeed. |

We *did* successfully extract the `1675_01XX.dat` set file from Apple's Windows
Boot Camp driver (`AppleCamera.sys`) — the thing
[facetimehd-firmware issue #3](https://github.com/patjak/facetimehd-firmware/issues/3)
never managed — before proving it wasn't the fix. The tooling for that is left
in the repo (`get_bootcamp.py`, `carve_setfile.py`) in case the calibration is
wanted for image-quality tuning later.

---

## Repo layout

| Path | What it is |
|---|---|
| `bcwc_pcie/` | The kernel driver, **patched** for the 1675 sensor (the actual fix). |
| `facetimehd-firmware/` | Extracts `firmware.bin` from Apple's macOS camera driver. |
| `install.sh` | Installs firmware + builds/loads the driver via DKMS. |
| `enable-iommu-off.sh` | Adds `intel_iommu=off` to the GRUB cmdline. |
| `get_bootcamp.py` | Downloads Apple's Boot Camp ESD for a model and extracts the Windows camera driver (Python 3, Linux-native; needs `unar`). |
| `carve_setfile.py` | PE analysis of `AppleCamera.sys` while locating the sensor set files. |
| `trace.sh`, `trace2.sh` | Capture the firmware↔driver dialogue with dynamic debug enabled (used to find the root cause). |
| `build_test.sh` | Rebuild the patched driver in-tree and run a capture test. |

### Diagnostic scripts

`trace2.sh` is the one that cracked it — it reliably enables the module's
`pr_debug` output and does a short capture, so you can see the `CAMCONF` dump and
the `set crop` / `output config` values the driver sends:

```bash
bash trace2.sh        # writes trace2.log / trace2.raw.log
```

`build_test.sh` rebuilds `bcwc_pcie/` and swaps the patched module in (via
`modprobe`, since `insmod` can't resolve the `videobuf2` dependency chain on its
own), then verifies SIF-error count and frame delivery.

---

## How the camera pipeline works (brief)

1. **PCIe + firmware.** The camera is a Broadcom S2 ISP on PCIe. The driver
   initializes the PCIe link, DDR memory and clocks, then uploads `firmware.bin`
   (Apple's H4 ISP firmware) into the ISP's memory and boots it.
2. **IPC / command channel.** The driver and ISP talk over a ring-buffered IPC
   channel using `CISP_CMD_*` commands (get channel info, select camera config,
   set crop, set output format, start channel, …). `intel_iommu=off` is required
   so the ISP can DMA this command channel.
3. **Sensor config.** At stream start the driver queries the sensor's supported
   config (`CISP_CMD_CH_CAMERA_CONFIG_GET`) — **this is where the 848×588 lives**
   — then sends crop/output geometry and starts the channel.
4. **Frames.** The ISP DMAs YUYV frames into videobuf2 buffers; the V4L2 layer
   hands them to userspace via `/dev/video0`; PipeWire exposes it to apps.

The bug was at step 3: the driver ignored the sensor's reported config and sent
its own hardcoded 1280×720, which the 848×588 sensor can't satisfy.

---

## Credits

Built on [`patjak/bcwc_pcie`](https://github.com/patjak/bcwc_pcie) and
[`patjak/facetimehd-firmware`](https://github.com/patjak/facetimehd-firmware).
The 1675-sensor geometry fix and the diagnosis above are the new work in this
repo.
