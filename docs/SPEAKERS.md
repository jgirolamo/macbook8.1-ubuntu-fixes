# Speakers on MacBook8,1

Pin-config firmware alone is **not enough**. The CS4208 drives a **4-channel TDM class-D amp**; the stock kernel breaks the EFI clock/amp state and speakers stay silent.

## What works

Install [thomas-shirley/macbook8.1-speaker-driver](https://github.com/thomas-shirley/macbook8.1-speaker-driver) via:

```bash
sudo ./scripts/03-speakers.sh
sudo reboot
```

After reboot:

```bash
journalctl -b -k | grep -i 'attaching to running EFI'
wpctl status | grep -i MacBook
# expect: input.MacBook_Speaker (default), MacBook Speaker (Raw)
```

Play to **`input.MacBook_Speaker`**.

## Notes

- Do **not** leave `/etc/modprobe.d/macbook-cs4208.conf` (pin-only patch) enabled alongside this driver — `03-speakers.sh` disables it.
- Resume recovery is handled by `mb81-resume-recover.service` from that project.
