# Review response — mptfire, 2026-11-12

Answers the senior-dev review (REVIEW-2026-11-12.md) point by point. The
reviewer's verdict — REJECT pending attachable context — was **correct
process**: the review environment received only four markdown files. This
response ships the missing context (review bundle, §6) and resolves every
code-checkable point with commands run against `4130e5166a14` and the
reviewer's proposed fixes implemented where accepted.

## 1. Context attachment (the blocker)

`omarchy-review-bundle.tar.gz` (branch `audit/report`, see §6) contains:
the repository tree at the audited SHA (git archive), the proof/ harness,
the two fix-branch diffs, the reviewer's review, and diffs for the PRs the
review scrutinized (#651, #639, #630, #682, #681, #645, #633). A reviewer
with a shell can now execute everything.

## 2. 6-vs-7 partition discrepancy — RESOLVED, both documents were right

`device/cheetah/device.conf:90-91`:
```
NV_PARTS="efs efs_backup modem_userdata persist modem_a modem_b"   (6)
NV_BACKUP_EXTRA="devinfo"
```
`tools/nv-backup` dumps NV_PARTS + NV_BACKUP_EXTRA = **7 files**.
`tools/phone-provision:378-380` consumes **6** of them (`modem-nv.sha256`;
devinfo is excluded because its slot flags change on every boot-success
mark — device.conf:87-89 documents why). AUDIT-REPORT described the
provision contract (6); HANDOFF §8.1 described the backup contents (7).
Documentation bug, not a code discrepancy; both docs now say "6 NV + devinfo".

## 3. Rulings accepted

- **S-1 → Medium: accepted.** The reviewer's subversion-of-the-review-gate
  rationale stands — §7's "merge after CI" leans on the CI the finding
  weakens. Draft PR #1 unchanged (the fix is the same); severity
  re-recorded.
- **NEW-1: accepted, implemented.** `audit/factory-zip-verify @ c493548`:
  backup tars verify by default (die with the one-time
  `sha256sum > .sha256` instruction), `--insecure-no-sha256` is the
  explicit escape. Proven: missing → refuse; flag → proceed; present →
  verify. S-2 is now Medium unambiguously (factory zip + backup tars both
  covered); the fail-closed-for-factory question (no flag = refuse) is a
  policy call left to the maintainer, flagged in PR #2's body.
- **S-7 → Medium: accepted, with a boundary correction.** The reviewer is
  right that the audit's "the phone enforces it too" overstated Layer 3:
  with `STRICT_DEVMEM` off, root can reach arbitrary physical memory and
  the guard is an accident guard, not a root boundary. Two factual
  completions to their question: the fragment sets no `CONFIG_DEVKMEM`
  (default n), and `CONFIG_KEXEC`/`MODULE_SIG` state is UNVERIFIED from a
  fragment alone (defaults govern; `bin/omamobile kexec` existing implies
  kexec support in the dev kernel) — added to the hardware hand-off:
  capture the built `.config` on-device and rule on KEXEC/MODULES/
  MODULE_SIG_FORCE explicitly.
- **#651 verdict amended: merge → changes-needed (one ask).** The
  reviewer's LUN-enumeration point is taken: `sd[a-z]` naming is stable on
  Qualcomm UFS in practice (LUN probe order is hardware-defined), but
  mark-slot-b should pin LUN identity independently of the sdX name —
  e.g. resolve via `/dev/disk/by-path` (UFS LUN index) or assert the
  expected SCSI/PALO identity before any sector write. One-PR change;
  everything else (COMPATIBLE, booted-slot, RO, geometry, §3.1 LBA pin,
  journal, typed confirm) is already there.
- **#639: keep-draft stands, caveat accepted.** EXIT traps do not survive
  SIGKILL/power loss. Two mitigating facts to weigh: on a FIRST install
  the probed slot B is unbootable, and ABL's retry exhaustion falls back
  to slot A by itself; on a reinstall slot B boots Omarchy (owner
  still in control, stock intact). Required additions before leaving
  draft: document the fail-open window and add a phone-side deadman
  (e.g. pre-agreed `systemd-run --on-active=180 --set-active=a` on the
  probed slot, killed by the successful next step — the project's own
  §3.4 pattern).
- **#630: the PAM question is answered in-repo.**
  `packages/omamobile-omarchy/lib/lock-pam:38-44` ships `pam_faillock`
  `deny=10 unlock_time=120` (preauth + authfail + authsucc), and the lock
  PIN pad IS the account password (pam_unix), so Change-PIN gains no new
  brute-force surface beyond what the lock screen already rate-limits.
  Upgrade-path note for the maintainer: ensure firstboot's generated PAM
  stack keeps faillock on the phone (it is written by lock-pam — test at
  `packages/omamobile-omarchy/test/lock-pam.sh:45`).

## 4. Rulings partially declined (with evidence)

- **NEW-2 (parser differential): the specific first-vs-last desync risk is
  disproven empirically; a smaller true differential was found.** Tested
  with a duplicated `UFS_RW` line on `4130e51`:
  - `bundle-manifest` (python): last-wins → sees `boot_b persist userdata`.
  - `install-phone` (bash): last-wins → `die: UFS_RW may hold only *_b
    partitions and userdata, not persist` (fail-closed).
  - `bin/omamobile load_device`: last-wins → same refusal (fail-closed).
  So both bash parsers and the python one agree on last-wins — no
  first-vs-last desync — and the two enforcement points refuse the hostile
  value. The true differential found: `bundle-manifest:120-127` checks
  boot images ∈ allow and userdata ∈ allow but not the converse (that
  every allow entry is `*_b`/userdata), which `install-phone:~150` does
  enforce. Safe direction: the bundle tool is the more permissive one and
  the installer's flash-gate + plan-equality independently refuse. Fix is
  still worth three lines in bundle-manifest; the consolidation into one
  canonical parser (reviewer's fix, same as the audit's) remains the
  structural answer, and duplicate-key rejection should be added to it
  (currently every parser silently takes the last).
- **Harness "sed modifies the system under test": agreed as a strict-
  reproducibility defect, declined as a blocker.** The honest framing: the
  battery proves the *gates*, not a pristine-host run. The clean fixes are
  the reviewer's `OMAMOBILE_ZONEINFO_DIR` (upstream change — filed in the
  hand-off as a request, not something the audit may add itself) or a
  rootless container with a real `/usr/share/zoneinfo`; both are listed
  for the maintainer. Until then the sed stays, disclosed in §2 of the
  hand-off.
- **S-3 remediation (pre-seed host keys at install): accepted as the
  better design, with one constraint to resolve upstream.** install-phone
  already writes into the image copy via debugfs; generating the phone's
  SSH host keys there (per install, never reused across phones) and
  writing them to both the image and the caller's known_hosts removes TOFU
  entirely. Constraint: keys generated on the laptop and injected into the
  rootfs are as sensitive as the user's authorized key — they must live in
  the same 0600 scratch dir, be wiped by the same trap, and be documented
  as laptop-generated (a phone whose host key was made by the laptop has a
  different trust story than one that generated its own). Until the
  maintainer picks a design, the audit's S-3 fix stays "default TOFU
  file, per-serial keyed, wiped on --reinstall" exactly to avoid the
  habitual-opt-out the reviewer predicts.

## 5. Harness gaps: two closed now, three filed

Closed in this response cycle (branch `audit/report`):
- **Check 16 (duplicate keys, the reviewer's proposed case):** the
  empirical runs above are scripted as `proof/duplicate-key-check.sh` —
  device.conf with duplicated `UFS_RW` (second line smuggling `persist`)
  against install-phone, omamobile, and bundle-manifest; asserts the two
  enforcement points refuse and records bundle-manifest's permissiveness.
- **Check 17 (flag-combination matrix):** added to
  `proof/run-battery.sh` — `--unsigned --reinstall
  --bootloader-slots-match` together, with manifest.json attempting
  `boot_a` and `persist` writes; asserts refusal at plan equality AND at
  the flash gate (the combination changes nothing about the allowlist).

Filed, not closable on this host (need upstream code changes or a real
container/kernel):
- **Check 18 (boot-update rollback on a corrupted read-back):** needs the
  phone-side dd path; upstream already carries
  `packages/omamobile-boot-update/test` — extend there.
- **Real-ext4 battery variant:** `mkfs.ext4` in the shims' place + real
  debugfs/e2fsck (e2fsprogs absent on this audit host; a container run
  covers it — Phase A of the reviewer's plan, agreed).
- **OMAMOBILE_ZONEINFO_DIR** upstream flag (see §4).

## 6. The review bundle

`omarchy-review-bundle.tar.gz` (branch `audit/report`, 0658be3+):
```
repo-4130e51/          git archive of the audited tree
proof/                 the harness (run-battery.sh …, 15/15)
duplicate-key-check.sh NEW-2 evidence script
patches/               audit/factory-zip-verify.diff (now 2 commits,
                       incl. NEW-1), audit/pin-ci-checkout.diff
pr-diffs/              #651 #639 #630 #682 #681 #645 #633 .diff
docs/                  HANDOFF-2026-11-12.md, AUDIT-REPORT-2026-11-12.md,
                       REVIEW-PROMPT.md, REVIEW-2026-11-12.md (reviewer),
                       REVIEW-RESPONSE-2026-11-12.md (this file)
AUDITED-SHA.txt        4130e5166a14a0e1d33f0832aee0d705ed8d7464
```
Verification: `sha256sum -c bundle.SHA256`.

## 7. Standing after this response

- Verdict translation: the reviewer's "CONDITIONAL SIGN-OFF ON AUDIT
  ARTIFACT" is accepted as the current state; the conditions were (a)
  attach context — done (this bundle), (b) resolve the 6/7 discrepancy —
  done (§2), (c) implement accepted fixes — NEW-1 done (§3), severity
  re-rulings recorded (§3), #651 ask filed (§3).
- Findings ledger after review: S-1 Medium · S-2 Medium (fix extended) ·
  S-3 Low + better-remediation-filed · S-4/S-5/S-6 Info · S-7 Medium
  (Layer-3 boundary correction) · S-8 Low · NEW-1 fixed · NEW-2 refined
  (no desync; permissiveness differential documented) · 0 High/Critical
  unchanged.
- The blocker on full verification remains hardware (Phase B) and one
  unmodified Arch container (Phase A), exactly as both documents say.
