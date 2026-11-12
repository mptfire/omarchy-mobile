#!/bin/bash
# S-2 fix proof: tools/phone-provision --expect-sha256 on the
# audit/factory-zip-verify branch. Wrong digest refuses; malformed refuses;
# correct digest proceeds (then stops at the run-type question — nothing
# staged, no phone contacted). Usage: run from this repository.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
P="$here/../tools/phone-provision"
[[ -x $P ]] || { echo "run from a checkout with the audit/factory-zip-verify branch applied" >&2; exit 2; }
w=$(mktemp -d)
head -c 1024 /dev/urandom > "$w/fake-factory.zip"
GOOD=$(sha256sum < "$w/fake-factory.zip" | cut -d' ' -f1)

echo "--- wrong digest (expect refusal) ---"
bash "$P" --dry-run --skip-extract --expect-sha256 \
  0000000000000000000000000000000000000000000000000000000000000000 \
  "$w/fake-factory.zip" 2>&1 | tail -1 || true
echo "--- malformed digest (expect refusal) ---"
bash "$P" --dry-run --skip-extract --expect-sha256 zzz \
  "$w/fake-factory.zip" 2>&1 | tail -1 || true
echo "--- correct digest (expect match, then run-type question) ---"
bash "$P" --dry-run --skip-extract --expect-sha256 "$GOOD" \
  "$w/fake-factory.zip" 2>&1 | tail -2 || true
rm -rf "$w"
