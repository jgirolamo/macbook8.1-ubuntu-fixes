#!/bin/bash
# Re-fetch vendored upstream sources (requires network). Run from repo root or anywhere.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
mkdir -p "$VENDOR"
cd "$VENDOR"

refresh_repo() {
  local name="$1" url="$2"
  local tmp
  tmp=$(mktemp -d)
  git clone --depth 1 "$url" "$tmp/$name"
  rm -rf "$VENDOR/$name"
  mv "$tmp/$name" "$VENDOR/$name"
  rm -rf "$VENDOR/$name/.git" "$tmp"
  echo "refreshed $name"
}

refresh_repo macbook8.1-speaker-driver https://github.com/thomas-shirley/macbook8.1-speaker-driver.git
refresh_repo macbook12-bluetooth-driver https://github.com/leifliddy/macbook12-bluetooth-driver.git
refresh_repo macbook8.1-camera https://github.com/thomas-shirley/macbook8.1-camera.git

mkdir -p "$VENDOR/applesmc-next"
curl -fsSL -o "$VENDOR/applesmc-next/applesmc-next-dkms_0.1.6-9netlinux1.resolute1_all.deb" \
  https://github.com/netlinux-ai/applesmc-next/releases/download/v9-dualsuite/applesmc-next-dkms_0.1.6-9netlinux1.resolute1_all.deb
echo "refreshed applesmc-next deb"
echo "vendor-refresh done — commit vendor/ if versions changed."
