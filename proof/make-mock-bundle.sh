#!/bin/bash
# Build a minimal omarchy-mobile release bundle for the proof battery.
# Usage: make-mock-bundle.sh BUNDLEDIR
# Produces device.conf (cheetah, BOOT_IMAGES="boot dtbo"), two image files,
# a stub rootfs + .sha256 + .MANIFEST, manifest.json whose install plan
# matches the descriptor exactly, and SHA256SUMS covering every file.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bundle=${1:?usage: make-mock-bundle.sh BUNDLEDIR}
mkdir -p "$bundle/images"
cd "$bundle"

cp "$here/../tools/install-phone" install
# One harness delta, documented: this audit host has no /usr/share/zoneinfo;
# point the installer's tzdata existence check at a stub tree.
mkdir -p "$bundle/../zoneinfo" && touch "$bundle/../zoneinfo/UTC"
sed -i "s#/usr/share/zoneinfo/#${bundle%/bundle}/zoneinfo/#g" install

cat > device.conf <<'EOF'
NAME="Pixel 7 Pro"
CODENAME=cheetah
SOC_IDS=gs201
BOOT_IMAGES="boot dtbo"
UFS_RW="boot_b dtbo_b userdata"
EOF
head -c 4096 /dev/urandom > images/boot.img
head -c 4096 /dev/urandom > images/dtbo.img
head -c 2048 /dev/urandom > omamobile-rootfs-cheetah-test-aarch64.img.zst
R=$(sha256sum omamobile-rootfs-cheetah-test-aarch64.img.zst | cut -d' ' -f1)
echo "$R  omamobile-rootfs-cheetah-test-aarch64.img.zst" > omamobile-rootfs-cheetah-test-aarch64.img.zst.sha256
printf 'device: cheetah test\nkernel modules: 6.12.0-test\n' > omamobile-rootfs-cheetah-test-aarch64.MANIFEST

SZB=$(stat -c %s images/boot.img); SZD=$(stat -c %s images/dtbo.img)
python3 - "$R" "$SZB" "$SZD" <<'PY'
import json, sys, hashlib, os
r, szb, szd = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
def sha(p): return hashlib.sha256(open(p,'rb').read()).hexdigest()
m = {"format":1,"version":"2026.11.12","label":"audit proof",
 "device":{"codename":"cheetah"},"kernel":{"release":"6.12.0-test"},
 "root_image":{"name":"omamobile-rootfs-cheetah-test-aarch64.img.zst","sha256":r},
 "install":{"product":"cheetah","require_unlocked_bootloader":True,
   "require_matching_bootloader_slots":True,
   "storage_guard_allowlist":["boot_b","dtbo_b","userdata"],
   "after":["set-active b","reboot"],
   "writes":[{"partition":"boot_b","source":"images/boot.img","size":szb,"partition_size":None,"erases_userdata":False},
             {"partition":"dtbo_b","source":"images/dtbo.img","size":szd,"partition_size":None,"erases_userdata":False},
             {"partition":"userdata","source":"root_image","size":None,"partition_size":None,"erases_userdata":True}]},
 "files":[]}
for root, _, names in os.walk('.'):
    for n in names:
        p = os.path.relpath(os.path.join(root, n))
        if p in ("SHA256SUMS", "SHA256SUMS.sig", "manifest.json"): continue
        m["files"].append({"path":p,"size":os.path.getsize(p),"sha256":sha(p)})
open("manifest.json","w").write(json.dumps(m))
PY
find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs sha256sum > SHA256SUMS
echo "bundle ready: $bundle"
