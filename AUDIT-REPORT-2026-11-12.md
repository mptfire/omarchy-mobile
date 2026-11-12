# Adversarial audit — derekross/omarchy-mobile @ 4130e5166a14a0e1d33f0832aee0d705ed8d7464

Auditor: mptfire (independent security review). Date: 2026-11-12.
No phone was attached at any time; all flash-path evidence is from
`--dry-run`/`--verify-only` runs against a mocked fastboot (proofs below).

## Verdict

The flash-safety guarantees are real and layered. I could not construct a
path that writes bootloader/radio/devinfo/persist/calibration or slot A
from `tools/install-phone`, `bin/omamobile flash|push|fastboot`, or the
on-phone initramfs guard. Findings are hardening-grade; none block a
release on their own.

## Findings

### S-1. CI: actions not SHA-pinned; container unpinned — Low
- File: `.github/workflows/checks.yml:27,61` (`actions/checkout@v5`, tag
  = mutable), `checks.yml:46` (`container: archlinux:latest`),
  `checks.yml:38-41` (conditional `pacman -U` of an unpinned archive URL).
- Scenario: a compromised checkout action tag runs attacker code in CI for
  every PR/push. Permissions are already `contents: read` and no secrets
  are used, so blast radius is small — this is hygiene, not a break-in.
- Proof: `grep -n "uses: actions/checkout" .github/workflows/checks.yml`
  → two tag pins (v5).
- Fix: SHA-pin (prepared as branch `audit/pin-ci-checkout`,
  08c6903cd8c0fde910a37f88322edcfb5dd907a8 = v5.0.0); digest-pin the
  container; move the simdjson downgrade behind a pinned URL comment.

### S-2. Factory-image integrity optional — Medium-Low
- File: `tools/phone-provision` (extraction call sites ~347-353). The
  factory zip's only built-in check is the `require board=` line inside
  the image zip (`tools/extract-vendor-firmware:319`); the SHA of the zip
  itself is never compared to what Google publishes. Backup tars accept a
  missing `.sha256` with a note (`tools/phone-provision:268`).
- Scenario: a corrupted or tampered factory download passes the board
  check; its firmware/modem blobs are extracted and pushed to the phone.
- Fix: prepared as branch `audit/factory-zip-verify` —
  `--expect-sha256 <google-published-digest>` refuses to extract on
  mismatch; docs tell users where Google prints the digest.

### S-3. SSH to the phone does not pin its host key by default — Low
- File: `tools/phone-ssh:41` (`known=${OMAMOBILE_SSH_KNOWN_HOSTS:-}`) and
  `:140` (`StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null` when
  unset). Default connections authenticate the client (key) but never the
  server.
- Scenario: an active attacker on the USB link (172.16.42.1 NCM) could
  impersonate the phone. `bin/omamobile push` streams slot-B images over
  this channel; a MITM with the phone's authorized key could alter them.
  Requires bus-level access; keys still gate everything.
- Fix: persist a per-user known_hosts (TOFU once, strict after), keep
  opt-out for native-Linux/recovery key-change cases.

### S-4. AOSP AVB test key signs boot-update images — Info
- File: `packages/omamobile-boot-update/avb/SOURCE:6-7`
  (`testkey_rsa4096.pem`, upstream AOSP test data).
- Bootloader is unlocked (required), vbmeta is never touched, and AVB
  enforcement is off; anyone with fastboot can write anyway. Deliberate
  and defensible; document in SECURITY-PLAN that the footer key asserts
  nothing.

### S-5. In-bundle trust is self-referential — Info (accepted)
- `tools/install-phone` verifies the bundle that contains itself; a
  malicious bundle could patch its own copy and lie. Mitigated by the
  download channel (HTTPS + Google-Drive style publishing), the signed
  checksums covering `manifest.json` and every file, and the hardcoded
  `SIGNING_KEYS` fingerprints (`install-phone:51`). Standard for
  self-contained installers; no change requested.

## Verified claims (README/CONTRIBUTING vs code)

| Claim | Evidence | Status |
| --- | --- | --- |
| Only boot images + userdata written | `install-phone` flash() gate (line ~640): partition must be `${p}_b` from BOOT_IMAGES **and** on descriptor UFS_RW; `UFS_RW_ALLOWED="boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b userdata"` (`bin/omamobile:133`); no `-w`, `--slot`, `flashing` anywhere | holds |
| Stock Android stays on slot A | slot-b current requires `--reinstall` (`install-phone` ~line 500); `--set-active=b` is the only slot write | holds |
| Dry-run shows every command | mocked dry-run printed exactly 5 commands: flash boot_b, flash dtbo_b, flash userdata, --set-active=b, reboot | holds |
| Read-only storage guard | `initramfs/init:47-170`: whole-disk node removed for sda+LUNs, per-partition allowlist from `/etc/omamobile-ufs-rw`, `blockdev --setro` everything else, retry with `.failed` marker, `ufs_unguarded` reporter | holds (on-phone behavior UNVERIFIED — needs hardware) |
| Dead-man switches | initramfs USB-host watchdog (SECURITY-PLAN:309,385), `panic=10`, `tools/usbc-deadman`, systemd-run deadman pattern (CONTRIBUTING:110) | present in code/docs; on-phone timing UNVERIFIED |
| Descriptor is data, never sourced | `bin/omamobile:132-145`, `install-phone:117-135`, `omamobile-firstboot:91-113` — all three parse `KEY=value` with char-class regex, reject `$`, backticks, control chars | holds |
| firstboot.conf is data on the phone | parser treats values literally; password via `chpasswd -e` on stdin; Wi-Fi PSK escaped (`kf_escape`) into NM keyfile; git config argv-quoted. `useradd` GECOS expansion is argv-safe (bash inner-quote semantics verified by repro) | holds |
| No secrets in repo or history | history scan: only public omamobile.gpg (0 secret packets), AOSP public testkey, `themetokens.h` (color constants) | holds |
| Bootloader slot match enforced | per-slot getvar compare; explicit `--bootloader-slots-match` consent path with the OTA-twice guidance | holds |
| Image fits partition, AVB footer exact | per-image `partition-size:` compare + AVB_FOOTERS equality (`install-phone` ~line 510) | holds |

## Proof battery (all with mocked fastboot, zero writes executed)

1. `--verify-only` on a constructed bundle → "The files check out (the
   phone was not contacted)".
2. Tampered image → "a bundle file doesn't match SHA256SUMS".
3. manifest.json smuggling `persist` into writes/allowlist (fresh
   checksums) → refused by the descriptor-equality rule.
4. Full `--dry-run` (bundle, answers piped) → prints exactly the five
   allowlisted commands; `fastboot-commands.log` empty (no writes).
5. `--serial WRONGSERIAL` → refused before questions.
6. Wrong confirmation word → "not confirmed; nothing was written".
7. current-slot=b without `--reinstall` → refused.

Harness delta from stock: one sed — `/usr/share/zoneinfo/` → a Termux
path (this audit host has no /usr); `zstd`/`debugfs`/`dumpe2fs`/`fastboot`
are recording shims, so the debugfs image-injection step is UNVERIFIED
(needs real e2fsprogs) — dev hand-off below.

## UNVERIFIED (needs hardware — dev hand-off)

- On-phone behavior of the initramfs storage guard and its `ro` sysfs
  enforcement across LUNs.
- First boot: firstboot.conf consumption end-to-end, keyring init, ufw
  USB-only rule, SDDM autologin+lock ordering.
- `omamobile-boot-update` pacman hook parity with install-phone's ramdisk
  append (`tests/install-phone-initramfs` asserts byte parity — not run
  here).
- Factory-image extraction on real Google zips (board check, EROFS/
  super.img paths) — mocked only.
- Modem NV flow: `--nv-backup` six-partition sums vs `phone-provision`
  expectations (code-reviewed only).

## PR reviews (30 open at audit time)

Verdicts on the safety-relevant set; the rest are docs/device-notes or
self-contained package bumps covered by tests/all + pr-check policy:

- **#651** mark-slot-b + push over UFS_RW_LUNS — **merge (inert-by-default)**.
  Writes 4 GPT sectors on a second LUN only when a descriptor names
  SLOT_B_MARK (none do); COMPATIBLE + booted-slot + RO + last-LBA checks;
  journal with typed `mark`/`restore` confirm; push path adds
  multi-match refusal + path-shape regex (fixes the old silent
  multi-match case). 234-line test added.
- **#639** bootloader slot probe — **keep draft**; EXIT trap restores the
  original slot, lost-phone path prints manual recovery, off by default,
  no descriptor sets BOOTLOADER_SLOT_PROBE. Needs: maintainer decision on
  the round-trip policy + on-phone UNVERIFIED.
- **#682/#681** install-phone work/verify-dir cleanups — small, correct;
  merge after rebase on current main.
- **#645/#633** guided installer + firstboot asks-for-nothing — largest
  new install surface; requires the same dry-run/verify-only contract and
  manifest-as-data parsing; recommend keeping the maintainer's own review
  bar (they are the author).
- Fork PRs by new contributors shipping shell/settings features are gated
  by pr-check (identifiers, blobs, AI sign-offs) + tests; no new external
  deps or binaries observed in the sampled diffs.

## Ranked improvements

1. (S-2) Factory-zip `--expect-sha256` — small effort, closes the only
   unverified-input path into the flash pipeline.
2. (S-1) SHA-pin checkout, digest-pin CI container — trivial.
3. (S-3) Default known_hosts TOFU for phone-ssh — small; document the
   key-change flow.
4. Add `install-phone --verify-only` to the release CI matrix (it is
   currently exercised by tests only on dev machines).
5. SECURITY-PLAN: one paragraph on the AVB test key (S-4) and the
   in-bundle trust model (S-5).

---

## Continuation pass (same SHA, same session)

### Shellcheck sweep (72 shell files, 0.11.0, warning+)
Only actionable hit: `bin/omamobile:876` SC2115 `rm -rf "$img"/*` — safe by
construction (`$img` always ends in `/images` via `${KERNEL_OUT:-...}`), but
worth `rm -rf -- "${img:?}"/*` for defense. The SC1007/SC2010 hits in
bring-up probes are style; the `tools/systemd/*.service` "errors" are
shellcheck fed non-shell unit files (harness artifact); SC1071 files are
extensionless python (bundle-manifest, phone-ssh-proxy, sit-sim, …).

### Supply-chain deep-dive (all clean)
- `tools/release-key-init`: offline cert-only ed25519 primary + online
  signing subkey; tmpfs gen, passphrase via fd, ≥12 chars, removable-media
  warning, offline revocation cert; rotation story coherent (subkey
  revoke/re-certify, phones keep trusting primary).
- `tools/make-bundle`: deterministic uncompressed tar; SHA256SUMS +
  `.sig` (+ tar.sha256.sig); version-by-calendar enforced for signed
  releases (install-phone re-checks).
- `tools/repo-publish`/`repo-push`: signs with `keys/gnupg.release`
  (signing.sh), publishes to pkgs.omamobile.org over ssh; promote path
  keeps per-version rollback; worktree detached at origin/main.
- Phone `rootfs/pacman.conf`: `SigLevel = Required DatabaseOptional` —
  package signatures required; [omamobile] via https mirrorlist.
- `tools/fetch-toolchain`: tree-digest verification of the pinned AOSP
  clang (`toolchain.lock`), `--verify` re-hashes.
- `tools/server/releases-nginx.sh`: maintainer-only, DRY_RUN, backup +
  nginx -t + revert-on-fail.
- `omamobile-remote`: opt-in, no units/listeners/ports; `omamobile-mirror`:
  USB wayvnc with password.

### Dead-man switches (code-level verification)
`initramfs/init:397-415`: 45 s loop on `udc/*/state == configured`;
failure → on-screen dmesg tail + 20 s grace (held while
`/run/omamobile-resizing` exists) + `panic=10` → ABL exhausts slot B
retries → boots slot A (stock Android). `packages/omamobile-boot-update`:
write-verify-rollback (leading-bytes sha256 read-back per partition,
previous images kept, battery + stat-idle checks, AVB key pinned to
AOSP testkey by SHA256, refuses substitutes). Design consistent;
runtime behavior UNVERIFIED (no hardware).

### Per-PR verdicts (all 30 open at audit time)
- #651 mark-slot-b+LUN push — **merge** (inert; journal/confirm; fixes
  push multi-match).
- #639 slot probe — **draft, keep** (EXIT-trap restore, off by default).
- #682/#681 install-phone dir handling — **merge** after rebase.
- #630 Change PIN page (draft) — **good design**: passwd in pty, stdin
  only, digits 4-8, LC_ALL=C, 12 s kill, fixed-arg runner, no shell
  strings. Merge when finished.
- #669/#677/#626/#595 modem-sit (radio power, call audio, suspend
  deadlines, tests) — opt-in daemon; review focus = AT-command surface;
  tests substantial (507-line startup-profile test). **merge with
  normal review**; no flash-path exposure.
- #645/#633 guided installer + first-boot — maintainer-authored, largest
  surface; hold to the install-phone contract (verify-only/dry-run/
  manifest-as-data). **review in series**.
- #690 pkg-version-from-git, #687 docs lessons, #687-series docs PRs
  (#685 merged), #679/#659/#655/#675/#676 device docs/tools — **merge
  after CI**.
- #658/#636/#635/#612/#614/#610/#600/#652 shell/settings/features —
  **merge after CI**; no new external deps observed in sampled diffs.
- #644 build index (factory build metadata) — check for serials/IMEIs in
  the index before merge (policy: no per-phone data in repo).
- #666 NCM transfer profile — check the udev/systemd bits stay opt-in.

### New finding from continuation
- **S-6 (Info)**: `bin/omamobile:876` `rm -rf "$img"/*` — suggest
  `"${img:?}"`; currently safe by construction.

---

## Continuation pass 2 (same SHA)

### S-7 (Low): kernel allows unrestricted /dev/mem
`kernel/configs/omamobile.config`: `CONFIG_DEVMEM=y`,
`# CONFIG_STRICT_DEVMEM is not set` (449-line fragment on arm64 defconfig).
Root on the phone can map arbitrary physical memory (kernel text, MMIO),
which bypasses every userspace-level guarantee; the bring-up probes
(`tools/devmem.c`, aoc/cs35l41 tooling) explain the choice. Fix: `STRICT_DEVMEM=y`
for release kernels (or an omamobile-dev kernel variant), or document the
trade-off in SECURITY-PLAN.

### S-8 (Low, UX/path confusion): phone-provision cds to the repo root
`tools/phone-provision:107` (`cd "$(dirname ...)/.."`) runs before arg
checks, so a *relative* FACTORY.zip resolves against the repository root,
not the caller's cwd — "no factory.zip" in the common case, and a silently
different file if a same-named file happens to sit there. Fix: resolve
factory/backup/nv-backup paths against `$PWD` captured before the `cd`.
Same pattern exists in `tools/build-rootfs` (repo-root cwd is intended
there; only phone-provision takes user file paths).

### Verified this pass
- S-2 fix works end-to-end: wrong digest → `refusing to extract`; right
  digest → proceeds (then correctly demands run type; nothing staged);
  malformed → refuses.
- Rootfs default-credential claim (README/RELEASES): `rootfs/build-inside:201-208`
  — dies on an `alarm` account or any uid ≥ 1000, forces `root:!*:`,
  removes the pacman keyring, resets machine-id/random-seed. Holds.
- `omamobile-boot-update` write gates: refuses unless slot B is the
  booting slot (`androidboot.slot_suffix` in bootconfig AND cmdline),
  initramfs allowlist must equal descriptor UFS_RW, partition found by
  GPT name, `ro 0`, leading-bytes sha256 read-back, previous kept for
  rollback. CONTRIBUTING:58's claims match the code.
- CONTRIBUTING §3.1 documents the GPT-sector exception *before* any
  device uses it — #651 is consistent with the rule (no entry yet ⇒ inert).
- `tools/nv-backup`: partitions come from the descriptor (NV_PARTS +
  NV_BACKUP_EXTRA), COMPATIBLE-checked, read-only + unmounted or abort.
- `manifests/omamobile.xml`: lineage-ref pulls TheMuppets' proprietary
  cheetah vendor tree — third-party blob source for the reference build
  only; nothing proprietary lands in this repo (license model intact,
  provenance = that repo's git history).

### device.conf parser count
10+ consumers (`install-phone`, `omamobile`, `nv-backup`, `factory-index`,
`bundle-manifest`, `release`, `build-packages`, `build-rootfs`,
`make-bundle`, `phone-smoke`, `local-key-init`). Regexes agree on the
important invariant (no `$`, backtick, backslash, quotes, control chars in
values) but are spelled independently — one shared
`tools/lib/parse-descriptor.sh` would remove the drift risk.
