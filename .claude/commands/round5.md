---
description: Drive Otto's prod-readiness round 5 to termination - close the frozen P2 list honestly, every item reviewed
---

# Goal

Drive round 5 of Otto's production-readiness effort to termination on branch `prod-readiness-5/2026-08-15`: every one of the ten frozen work-list items in `PROD-READINESS-5.md` reaches a terminal state - **RESOLVED** (artifact evidence, adversarially reviewed), **DEFERRED** (reason recorded), or **REJECTED TWICE** (reverted, objection recorded) - and the run ends with a terminal five-dimension verification stamped in the ledger.
There are no other terminal states.

# Source of truth - read before acting

State lives in the repo, not in this prompt; this prompt may be stale the moment it is run.
1. `git log` on `prod-readiness-5/2026-08-15` and the working tree - reconcile actual state first.
2. `PROD-READINESS-5.md` - the frozen list, per-item terminal states, REVIEW RANGES table, NEXT ROUND carries.
3. `reviews-5/` - baseline and review artifacts; `PROD-READINESS-4.md` NEXT ROUND - the defect definitions (N4-x, N3-x, N2-x).
4. Never trust a summary (including this file) over those artifacts; verify by measurement.

# The contract (binding, from rounds 1-4)

- The work list is frozen: the ten items, nothing else; all P3s go to NEXT ROUND with their measurements.
- Per stage: reproduce the defect by executing it BEFORE any edit, with recorded numbers; fix at the right seam; measure after; full five-dimension verification at the stage head; ledger section marked "RESOLVED pending review"; then an independent adversarial review of the stage range (fresh agent, refute-not-confirm posture, format of `reviews-4/REVIEW-3.md`) writing `reviews-5/REVIEW-N.md` with PASS / PASS-WITH-FINDINGS / REJECT.
- REJECT → remediate → re-review, once; a second REJECT on the same range hits the cap: revert the stage, DEFER with the objection recorded - ask the user before executing a revert.
- Five dimensions, every stage head: `scripts/verify.sh` exit 0 (608+ at stage-2 open); `swiftlint --strict` clean; full simulator suite from `Packages/OttoUI/` TEST SUCCEEDED with no new known issues; non-Gregorian harness 1/1/5 under `th_TH@calendar=buddhist` / `ja_JP@calendar=japanese` / `ar_SA@calendar=islamic-umalqura` with the same five citations; twelve clean `swift test --package-path Packages/OttoUI` runs.
- Standing rules: no eleventh `OSLogStore` reader; never weaken/skip a test; no new dependency, package, or target without an explicit user decision; every commit sits inside a declared review range; stochastic claims need repeated runs, never one sample; quote mutant batteries by failing-test sets, not issue counts; commits are one short sentence, no AI attribution.

# Decisions already taken by the user (do not re-litigate)

- Item 2 (N4-2): a detected-implausible stored day stops scheduling entirely (option 2), paired with item 4 (N4-16) making the repair reachable off the `.active` state.
- The round runs from merged `main` (`1b352f4`); the stack merge and pushes are done.

# Decisions that are the user's - stop and ask

- Item 5 (N4-1): whether a UI-test target may be added (rounds 4-5 were not permitted to).
- Items 8-9 (N2-1, N3-5): user-facing copy changes - show the copy before shipping it.
- Any stage-cap revert; any push.

# Process lessons (hard-won this session)

- Subagents cannot `git checkout` / switch branches under the permission classifier - the main session does branch operations; subagents can edit, test, and commit.
- A subagent's foreground long-run dies when its turn ends: chain all long measurements (batteries, 18-run evidence, five-dimension verification) into ONE `run_in_background` Bash command so completion re-invokes it; commit finished work BEFORE starting long measurements; never end a turn without live background work or the final report done.
- Watch for stalled subagents: if no process is running and no commit has landed, resume them with a concrete next step; `pgrep -f swift` false-positives on Wispr Flow - check `ps` output, not just the exit code.
- GitHub Actions is dead (billing/spending limit) - CI runs fail in seconds without starting; the CI-runner `OSLogStore` question stays CANNOT ASSESS until the user fixes billing.

# Termination

When all ten items are terminal: run the five-dimension verification at HEAD, stamp the terminal table and the run's honest caveats in `PROD-READINESS-5.md` (round 4's TERMINATION section is the model), reconcile every review finding into fixed/carried/answered, and report - do not push unless asked.
