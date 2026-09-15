# Shared helpers for install scripts. Source with: . "$(dirname "$0")/_lib.sh"
# shellcheck disable=SC2034

# Prefer vendored tree; optionally fall back to git clone if ALLOW_NETWORK_FALLBACK=1.
# Usage: install_vendor_src <vendor-subdir-name> <dest> <git-url>
install_vendor_src() {
  local name="$1" dest="$2" url="$3"
  local vendor="$ROOT/vendor/$name"
  mkdir -p "$(dirname "$dest")"
  if [[ -d "$vendor" && -n "$(ls -A "$vendor" 2>/dev/null || true)" ]]; then
    rm -rf "$dest"
    cp -a "$vendor" "$dest"
    echo "using vendored $name → $dest"
    return 0
  fi
  if [[ "${ALLOW_NETWORK_FALLBACK:-0}" == 1 ]]; then
    echo "WARN: vendor/$name missing — cloning $url"
    rm -rf "$dest"
    git clone --depth 1 "$url" "$dest"
    return 0
  fi
  echo "ERROR: vendor/$name missing. Re-run scripts/vendor-refresh.sh online, or set ALLOW_NETWORK_FALLBACK=1." >&2
  return 1
}

# apt-get install that soft-fails when packages are already present offline.
# Usage: apt_install pkg1 pkg2 ...
apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  if apt-get install -y "$@" 2>/tmp/macbook-apt-install.err; then
    return 0
  fi
  local missing=0 pkg
  for pkg in "$@"; do
    # Skip virtual/meta patterns like linux-headers-$(uname -r) — dpkg -s needs exact name
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      # headers package name is concrete when expanded by caller
      echo "missing package: $pkg" >&2
      missing=1
    fi
  done
  if [[ $missing -eq 0 ]]; then
    echo "apt offline/failed but required packages already installed — continuing"
    return 0
  fi
  cat /tmp/macbook-apt-install.err >&2 || true
  return 1
}
