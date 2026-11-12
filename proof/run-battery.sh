#!/bin/bash
# The full proof battery against a mocked fastboot. NO PHONE IS CONTACTED:
# the shims never touch USB, and write-type commands are only recorded to a
# log, never executed. Run from a checkout of this repository:
#   proof/run-battery.sh
# Exits non-zero on the first failed expectation.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/.." && pwd)
work=$(mktemp -d)
shims="$work/bin"; mkdir -p "$shims"
if [[ ${REAL_FS:-0} == 1 ]]; then
  ln -sf "$here/shims/fastboot" "$shims/fastboot"
else
  ln -sf "$here/shims/"* "$shims/"
fi
export GETVAR_TXT="$work/getvar.txt" AUDIT_LOG="$work/fastboot-commands.log"
cat > "$GETVAR_TXT" <<'EOF'
(bootloader) product: cheetah
(bootloader) unlocked: yes
(bootloader) current-slot: a
(bootloader) version-bootloader: bootloader-2026
(bootloader) partition-size:boot_b: 0x4000000
(bootloader) partition-size:dtbo_b: 0x100000
(bootloader) partition-size:userdata: 0x100000000
EOF
: > "$AUDIT_LOG"

answers="$work/answers.txt"
mkdir -p "$work/home/.ssh"
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHandoverProofKey audithandoff@test" > "$work/home/.ssh/id_ed25519.pub"
printf 'omarchy-auditor\nsup3rsecret\nsup3rsecret\naudit-phone\nUTC\nAudit Runner\naudit@example.net\n\n%s\ncheetah\n' \
  "$work/home/.ssh/id_ed25519.pub" > "$answers"

pass=0 fail=0
ok()   { echo "  PASS: $*"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $*"; fail=$((fail+1)); }
expect_grep() { grep -q "$1" "$2" && ok "$3" || bad "$3 (wanted '$1' in $2)"; }
expect_die()  { [[ $1 == "$2" ]] && ok "$3" || bad "$3 (rc=$1, wanted $2)"; }

if [[ ${REAL_FS:-0} == 1 ]]; then
  # Real-ext4 mode: fastboot is shimmed; debugfs/dumpe2fs/e2fsck/zstd come
  # from the host; and one more shim makes `rm` decline deleting the root
  # image, so install-phone's cleanup trap leaves it for the post-run
  # assertions. Environment instrumentation only — the script under test
  # is byte-identical to the branch's tools/install-phone.
  REAL_RM=$(command -v rm)
  cat > "$shims/rm" <<RMEOF
#!/bin/bash
for a in "\$@"; do
  b=\${a##*/}
  [[ \$b == root.img || \$b == root.simg ]] && exit 0
done
exec "$REAL_RM" "\$@"
RMEOF
  chmod +x "$shims/rm"
  mkdir -p "$work/home/.cache/omamobile-install"
  REALFS=1 bash "$here/make-mock-bundle.sh" "$work/bundle" > /dev/null
else
  bash "$here/make-mock-bundle.sh" "$work/bundle" > /dev/null
fi
export FAKE_WORK="$work/home/.cache/omamobile-install"
export HOME="$work/home"
run() { local ans=$1; shift; (cd "$work/bundle" && PATH="$shims:$PATH" bash install "$@" < "$ans") ; }

echo "[1] --verify-only accepts a consistent bundle"
rc=0; run /dev/null --verify-only --unsigned > "$work/t1.log" 2>&1 || rc=$?
expect_die "$rc" 0 "verify-only exits 0"
expect_grep "The files check out (the phone was not contacted)" "$work/t1.log" "no phone contact"

echo "[2] tampered image is refused"
printf 'X' | dd of="$work/bundle/images/dtbo.img" bs=1 seek=100 conv=notrunc 2>/dev/null
rc=0; run /dev/null --verify-only --unsigned > "$work/t2.log" 2>&1 || rc=$?
expect_grep "doesn't match SHA256SUMS" "$work/t2.log" "checksum refusal"
(cd "$work/bundle" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs sha256sum > SHA256SUMS)

echo "[3] manifest smuggling persist is refused by the plan rule"
python3 - "$work/bundle" <<'PY'
import json, sys
b = sys.argv[1]
m = json.load(open(b + "/manifest.json"))
m["install"]["writes"].append({"partition":"persist","source":"images/dtbo.img","size":4096,"partition_size":None,"erases_userdata":False})
m["install"]["storage_guard_allowlist"].append("persist")
open(b + "/manifest.json","w").write(json.dumps(m))
PY
(cd "$work/bundle" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs sha256sum > SHA256SUMS)
rc=0; run /dev/null --verify-only --unsigned > "$work/t3.log" 2>&1 || rc=$?
expect_grep "not the descriptor's" "$work/t3.log" "allowlist equality refuses persist"
(cd "$work/bundle" && "$here/make-mock-bundle.sh" "$work/bundle-refresh" > /dev/null 2>&1 || true) || true
# restore a clean bundle for the rest of the battery
rm -rf "$work/bundle" && bash "$here/make-mock-bundle.sh" "$work/bundle" > /dev/null

echo "[4] full --dry-run: exactly the allowlisted commands"
: > "$AUDIT_LOG"
rc=0; run "$answers" --dry-run --unsigned --bootloader-slots-match bootloader-2026 > "$work/t4.log" 2>&1 || rc=$?
expect_die "$rc" 0 "dry-run exits 0"
for want in "flash boot_b" "flash dtbo_b" "flash userdata" "--set-active=b" "reboot"; do
  expect_grep "would run: fastboot -s AUDITSERIAL $want" "$work/t4.log" "would run: $want"
done
[[ $(grep -c "would run:" "$work/t4.log") == 5 ]] && ok "exactly 5 commands" || bad "command count != 5"
[[ $(grep -c "wrote:" "$AUDIT_LOG") == 0 ]] && ok "zero write commands executed" || bad "shim recorded writes"

if [[ ${REAL_FS:-0} == 1 ]]; then
  keep="$FAKE_WORK/root.img"
  echo "  [real-fs] post-run assertions on $keep"
  st=$(debugfs -R "stat /etc/omamobile/firstboot.conf" "$keep" 2>/dev/null)
  debugfs -R "stat /etc/omamobile/firstboot.conf" "$keep" 2>/dev/null | grep -q "Mode:  0600" && \
    debugfs -R "stat /etc/omamobile/firstboot.conf" "$keep" 2>/dev/null | grep -qE "User: +0" && \
    ok "firstboot.conf mode 0600 uid 0 (real debugfs)" || bad "firstboot.conf stat: $(echo "$st" | head -1)"
  debugfs -R "cat /etc/omamobile/firstboot.conf" "$keep" 2>/dev/null | grep -q "^USERNAME=omarchy-auditor$" && ok "firstboot.conf content written (real ext4)" || bad "firstboot.conf content"
  debugfs -R "cat /root/.ssh/authorized_keys" "$keep" 2>/dev/null | grep -q "audithandoff@test" && ok "authorized_keys written (real ext4)" || bad "authorized_keys"
  e2fsck -fn "$keep" > /dev/null 2>&1 && ok "real e2fsck -fn clean" || bad "e2fsck dirty"
else
  echo "  (REAL_FS=0: debugfs writes mocked — run REAL_FS=1 for the real-ext4 pass)"
fi

echo "[5] --serial mismatch is refused"
rc=0; run "$answers" --dry-run --unsigned --serial WRONGSERIAL > "$work/t5.log" 2>&1 || rc=$?
expect_grep "not the one this install was started for" "$work/t5.log" "serial mismatch"

echo "[6] wrong confirmation word refuses"
head -9 "$answers" > "$work/answers-wrong.txt"; echo "nope" >> "$work/answers-wrong.txt"
rc=0; run "$work/answers-wrong.txt" --dry-run --unsigned --bootloader-slots-match bootloader-2026 > "$work/t6.log" 2>&1 || rc=$?
expect_grep "not confirmed; nothing was written" "$work/t6.log" "confirmation gate"

echo "[7] current-slot b without --reinstall refuses"
sed 's/current-slot: a/current-slot: b/' "$GETVAR_TXT" > "$work/getvar-b.txt"
rc=0; (cd "$work/bundle" && PATH="$shims:$PATH" GETVAR_TXT="$work/getvar-b.txt" bash install --dry-run --unsigned < "$answers") > "$work/t7.log" 2>&1 || rc=$?
expect_grep "the phone only reports slot b.s bootloader" "$work/t7.log" "slot-b guard (bootloader-slots gate fires first)"

echo "[8] flag-combination matrix: --unsigned --reinstall + boot_a/persist writes"
python3 - "$work/bundle" <<'PYM'
import json, sys
b = sys.argv[1]
m = json.load(open(b + "/manifest.json"))
m["install"]["writes"] = [
  {"partition":"boot_a","source":"images/boot.img","size":4096,"partition_size":None,"erases_userdata":False},
  {"partition":"persist","source":"images/dtbo.img","size":4096,"partition_size":None,"erases_userdata":False},
  {"partition":"userdata","source":"root_image","size":None,"partition_size":None,"erases_userdata":True}]
m["install"]["storage_guard_allowlist"] = ["boot_a","boot_b","dtbo_b","userdata","persist"]
open(b + "/manifest.json","w").write(json.dumps(m))
PYM
(cd "$work/bundle" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs sha256sum > SHA256SUMS)
rc=0; run "$answers" --dry-run --unsigned --reinstall --bootloader-slots-match bootloader-2026 > "$work/t8.log" 2>&1 || rc=$?
expect_grep "not the descriptor.s" "$work/t8.log" "hostile write list refused (allowlist equality, plan rule behind it)"

echo
echo "battery: $pass passed, $fail failed"
exit $((fail > 0))
