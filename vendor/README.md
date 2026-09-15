# Vendored upstream sources

Bundled so `scripts/install-all.sh` can run without cloning GitHub or downloading
the applesmc-next release (still needs `apt` packages / kernel headers).

| Path | Upstream |
|------|----------|
| `macbook8.1-speaker-driver/` | https://github.com/thomas-shirley/macbook8.1-speaker-driver |
| `macbook12-bluetooth-driver/` | https://github.com/leifliddy/macbook12-bluetooth-driver |
| `macbook8.1-camera/` | https://github.com/thomas-shirley/macbook8.1-camera |
| `applesmc-next/*.deb` | https://github.com/netlinux-ai/applesmc-next |

Refresh (online):

```bash
./scripts/vendor-refresh.sh
```
