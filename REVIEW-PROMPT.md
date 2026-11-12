# Review prompt — paste this to the senior developer (or their agent)

ROLE
You are a senior security/firmware engineer performing an ADVERSARIAL
REVIEW of a completed security audit, not of the codebase alone. Your job
is to find what the auditor got wrong, missed, or overstated. Treat the
audit as an untrusted artifact: every claim you intend to accept must be
one you reproduced or traced yourself.

SUBJECT
Repo: github.com/derekross/omarchy-mobile (Pixel 7 Pro "cheetah" bring-up;
Arch Linux ARM + Hyprland, mainline kernel; laptop-built installer).
Audited commit: 4130e5166a14a0e1d33f0832aee0d705ed8d7464 (main, 2026-11-12).
Audit artifacts: fork github.com/mptfire/omarchy-mobile —
  branch audit/report            → HANDOFF-2026-11-12.md + proof/ harness
  branch audit/pin-ci-checkout   → draft PR #1 (S-1 fix)
  branch audit/factory-zip-verify→ draft PR #2 (S-2 fix)
The audit claims 8 findings (0 High/Critical), all flash-safety guarantees
hold, and 30 open PRs reviewed.

HARD RULES
- No phone attached, ever. Never run fastboot/flash/dd against a device.
  The harness (proof/) mocks fastboot/debugfs/zstd; keep it that way.
- Clone fresh yourself; verify HEAD is 4130e51 before trusting anything.
- Work in a throwaway directory/container; no builds outside it.
- Do not modify upstream derekross/omarchy-mobile in any way. If you push,
  push only to the mptfire fork, as new audit/review-* branches.

MANDATORY VERIFICATION (do not skip; the report claims each)
1. Re-run the battery: `proof/run-battery.sh` from the audit/report branch.
   Expect 15/15. Then break it: mutate the harness shims (make the fake
   fastboot "forget" a partition-size line; make debugfs lie on `cat`) and
   confirm the battery still catches real refusals — i.e. the mocks are
   not what makes the checks pass. Report which checks are shim-sensitive.
2. Re-derive, without the report: (a) that no writer can reach a
   non-allowlist partition — trace every write call in tools/install-phone,
   bin/omamobile (flash/push), packages/omamobile-boot-update, and
   initramfs/init's guard; (b) that no descriptor or firstboot.conf value
   reaches a shell as anything but data (find one parser that differs from
   the others and try to exploit the difference).
3. Attack the guarantee directly: with the repo checked out, search for
   ANY path — argument injection, env override (FASTBOOT, OMAMOBILE_*,
   PATH), symlink swap in images/ or the bundle, manifest edge case,
   --unsigned, --reinstall, --bootloader-slots-match misuse, or the
   pacman hook — that writes slot A, bootloader, radio, devinfo, persist,
   or calibration. The audit claims none exists; you must show your
   nearest attempt and why it fails.
4. Adversarially re-review the three most consequential PRs the audit
   passed: #651 (mark-slot-b — try to get the four-sector write onto sda
   or outside the §3.1 constraints), #639 (slot probe — try to strand the
   phone on slot B), #630 (PIN page — try to leak or brute the old PIN).
   State agree/disagree with the audit verdicts and why.
5. Check the auditor's rejected finding (useradd GECOS, §4 end +
   proof/useradd-argv-repro.sh): is the bash-semantics reasoning sound?
   Try to defeat it with IFS, PATH, or shell-version differences.
6. Fact-check five random rows of the claims-vs-code table (§5) and two
   random PR verdicts (§7) by reading the code yourself.
7. Judge severities: dispute any S-1..S-8 rating you disagree with, using
   access/effect rationale. Specifically rule on S-2 (is Medium-Low right
   for an optional-integrity fix on a user-supplied file?) and S-3 (is
   TOFU-by-default acceptable for a USB link?).
8. Assess the harness itself: what does it NOT cover that a senior dev
   would demand before signing off (e.g. real ext4 writes via debugfs,
   img2simg sparse path, the e2fsck contract, multi-relay bundles,
   non-cheetah descriptors)?

DELIVERABLE
A review verdict document, `REVIEW-<date>.md`, with:
- VERDICT: sign-off / sign-off-with-conditions / reject, one paragraph.
- Per finding S-1..S-8: AGREE (severity) / DISAGREE (proposed severity +
  evidence), plus anything NEW you found (file:line, scenario, proof,
  fix), clearly split "in-audit-scope" vs "outside".
- PR verdict changes, if any, with diffs you actually read.
- Harness gaps found in task 8, each with a proposed check.
- The hardware hand-off plan (§8 of the hand-off) edited to your
  satisfaction: add steps you require, delete steps you consider noise,
  mark which require a sacrificial device vs the owner's daily phone.
- Evidence appendix: every command you ran and its output (trimmed to the
  decisive lines), including your clone SHA and the battery's final line.
RULES OF EVIDENCE: "I checked and it holds" is not evidence; quote the
command and the output. If you cannot verify something without hardware,
mark UNVERIFIED and add it to the hand-off — do not soften it to PASS.

TONE
Terse, adversarial, no filler. Your value is the delta between your review
and the audit, not a summary of it.
