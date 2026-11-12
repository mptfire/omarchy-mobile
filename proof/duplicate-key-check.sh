#!/bin/bash
# NEW-2 evidence (reviewer's parser-differential question), against 4130e51:
# a device.conf with a duplicated UFS_RW line whose second value smuggles
# `persist`. Asserts: every parser takes LAST-WINS (no first-vs-last
# desync), both enforcement points (install-phone, bin/omamobile) refuse
# the hostile value, and bundle-manifest is the more permissive one (it
# lacks the every-entry-is-_b/userdata rule — install-phone's flash gate
# and plan-equality cover it). Usage: run from a checkout of this repo.
set -u
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
w=$(mktemp -d); trap 'rm -rf "$w" "$repo/device/testdev"' EXIT
mkdir -p "$repo/device/testdev" "$w/images"
cat > "$repo/device/testdev/device.conf" <<'EOF'
NAME="Test"
CODENAME=testdev
SOC_IDS=gs201
BOOT_IMAGES="boot"
UFS_RW="boot_b userdata"
UFS_RW="boot_b persist userdata"
EOF
echo testdev > "$w/images/DEVICE"
head -c 64 /dev/urandom > "$w/images/boot.img"
for t in debugfs dumpe2fs e2fsck lz4 cpio img2simg; do printf '#!/bin/sh\nexit 0\n' > "$w/$t"; chmod +x "$w/$t"; done
printf '#!/bin/sh\ntrue\n' > "$w/zstd"; chmod +x "$w/zstd"

echo "== python (bundle-manifest) sees:"
# direct replica of bundle-manifest descriptor(): read line by line,
# overwrite the key (bundle-manifest:44-56) -> last wins
python3 - "$repo/device/testdev/device.conf" <<'PY2'
import sys, re
d = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if not line or line.startswith("#"): continue
    m = re.match(r'^([A-Z][A-Z0-9_]*)="([^"$`\\]*)"$|^([A-Z][A-Z0-9_]*)=([^"$`\\\'\s]*)$', line)
    if m: d[m.group(1) or m.group(3)] = m.group(2) if m.group(2) is not None else m.group(4)
print("  ", repr(d.get("UFS_RW")), "(last wins; no duplicate-key rejection)")
PY2
echo "== install-phone (bash):"
PATH="$w:$PATH" bash "$repo/tools/install-phone" --dry-run --device testdev --images "$w/images" < /dev/null 2>&1 | tail -1 || true

echo "== bin/omamobile (bash):"
DEVICE=testdev bash "$repo/bin/omamobile" images 2>&1 | tail -1 || true

echo "expected: python shows the last value (permissive); both bash"
echo "enforcement points refuse persist (fail-closed)."
