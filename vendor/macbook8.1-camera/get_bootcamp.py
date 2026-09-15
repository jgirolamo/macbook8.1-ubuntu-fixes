#!/usr/bin/env python3
"""
Fetch the Boot Camp ESD that supports a given Mac model and extract the Apple
camera driver (AppleCamera.sys / AppleCamera64.exe + any isp/*.dat set files).

Logic is a Python-3 reimplementation of brigadier's catalog search + the Linux
7z extraction chain:  BootCamp.pkg (xar) -> Payload (gzip) -> Payload~ (cpio)
-> WindowsSupport.dmg (HFS+) -> BootCamp/Drivers/Apple/...

Usage:  python3 get_bootcamp.py MacBook8,1 [output_dir]
Needs:  7z (p7zip-full).  Network access to Apple's swscan/swcdn.
"""
import os, re, sys, ssl, tempfile, subprocess, urllib.request, plistlib

SUCATALOG = ("https://swscan.apple.com/content/catalogs/others/"
             "index-11-10.15-10.14-10.13-10.12-10.11-10.10-10.9-"
             "mountainlion-lion-snowleopard-leopard.merged-1.sucatalog")

def log(m): print("==>", m, flush=True)

def fetch(url, binary=True):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={"User-Agent": "brigadier-py3"})
    with urllib.request.urlopen(req, context=ctx, timeout=120) as r:
        data = r.read()
    return data if binary else data.decode("utf-8", "replace")

def download(url, dest):
    log("Downloading %s" % url)
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={"User-Agent": "brigadier-py3"})
    with urllib.request.urlopen(req, context=ctx, timeout=300) as r, open(dest, "wb") as f:
        total = int(r.headers.get("Content-Length", 0)); got = 0
        while True:
            chunk = r.read(1 << 20)
            if not chunk: break
            f.write(chunk); got += len(chunk)
            if total:
                sys.stdout.write("\r    %d/%d MB" % (got >> 20, total >> 20)); sys.stdout.flush()
        print()
    log("Saved -> %s (%d MB)" % (dest, os.path.getsize(dest) >> 20))

def sevenzip(arc, out_dir):
    subprocess.run(["7z", "x", "-y", arc, "-o%s" % out_dir],
                   check=False, stdout=subprocess.DEVNULL)

def main():
    if len(sys.argv) < 2:
        sys.exit("usage: get_bootcamp.py <Model,Id> [output_dir]")
    model = sys.argv[1]
    out_base = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.getcwd()

    log("Fetching software update catalog (~ may take a moment)")
    cat = plistlib.loads(fetch(SUCATALOG))
    prods = cat["Products"]

    # Boot Camp ESD products = those whose ServerMetadataURL mentions BootCamp
    bc = [(pid, p) for pid, p in prods.items()
          if "ServerMetadataURL" in p and "BootCamp" in p["ServerMetadataURL"]]
    log("Found %d Boot Camp ESD products in catalog" % len(bc))

    matches = []
    for pid, p in bc:
        dists = p.get("Distributions", {})
        disturl = dists.get("English") or dists.get("en")
        if not disturl:
            continue
        try:
            dist = fetch(disturl, binary=False)
        except Exception as e:
            log("  (skip %s: %s)" % (pid, e)); continue
        if re.search(re.escape(model), dist):
            supported = sorted(set(re.findall(r"[A-Za-z]{4,12}\d{1,2},\d{1,2}", dist)))
            post = p.get("PostDate")
            matches.append((pid, p, post))
            log("  %s supports: %s (PostDate %s)" % (pid, ", ".join(supported), post))

    if not matches:
        sys.exit("No Boot Camp ESD found supporting %s" % model)
    # newest by PostDate
    matches.sort(key=lambda t: t[2] or 0, reverse=True)
    pid, p, post = matches[0]
    log("Selected %s (newest)" % pid)
    pkg_url = p["Packages"][0]["URL"]

    landing = os.path.join(out_base, "BootCamp-" + pid)
    os.makedirs(landing, exist_ok=True)
    work = tempfile.mkdtemp(prefix="bootcamp-unpack_")
    pkg = os.path.join(work, pkg_url.split("/")[-1])
    download(pkg_url, pkg)

    log("Extracting pkg -> Payload -> cpio -> WindowsSupport.dmg")
    for arc in [pkg, os.path.join(work, "Payload"), os.path.join(work, "Payload~")]:
        if os.path.exists(arc):
            sevenzip(arc, work)
    dmg = None
    for root, _, files in os.walk(work):
        for fn in files:
            if fn == "WindowsSupport.dmg":
                dmg = os.path.join(root, fn)
    if not dmg:
        sys.exit("WindowsSupport.dmg not found after extraction; inspect %s" % work)
    log("Extracting %s" % dmg)
    sevenzip(dmg, landing)

    log("Searching for AppleCamera / isp .dat files under %s" % landing)
    hits = []
    for root, _, files in os.walk(landing):
        for fn in files:
            if re.search(r"AppleCamera|_01XX\.dat|\.dat$|isp", fn, re.I):
                hits.append(os.path.join(root, fn))
    if hits:
        log("FOUND:")
        for h in sorted(hits):
            print("   ", h)
    else:
        log("No obvious camera files; full tree extracted under %s" % landing)
    print("\nLanding dir:", landing)

if __name__ == "__main__":
    main()
