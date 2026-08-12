# PROD-READINESS-4 - Otto, round 4

Bounded remediation of a frozen list, 2026-08-12, branch `prod-readiness-4/2026-08-12`, from commit `2d8913c` on `prod-readiness-3/2026-08-11`.

Baseline artifact: `reviews-4/BASELINE-4.md`.
Review trail: `reviews-4/`.

**This is not a discovery sweep.**
Every item below was found, evidenced and adversarially reviewed in the three runs that produced `PROD-READINESS.md` / `reviews/`, `PROD-READINESS-2.md` / `reviews-2/`, and `PROD-READINESS-3.md` / `reviews-3/`.
Round 4's only job is to close a named subset honestly and to say plainly what it could not close.
No prior record is edited by this run.

Rounds 1, 2 and 3's terminal states and scope constraints still bind, except where the round-4 prompt overrules them explicitly - it does so twice, and both are recorded under ASSUMPTIONS.

---

## Baseline

`scripts/verify.sh` at `2d8913c`, from a clean clone: **exit 0 - OttoDomain 258, OttoPersistence 124, OttoUI 207, total 589**, `swiftlint --strict` clean over 220 files.
Simulator suite from `Packages/OttoUI/`: exit 0, `** TEST SUCCEEDED **`, **117 / 72 / 36 tests, 7 known issues**.
Non-Gregorian harness: **1 / 1 / 5** issues under `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura`.
**Flake rate, new this round: 12 of 12 clean full `swift test --package-path Packages/OttoUI` runs.**

All five reproduce the round-4 prompt's prediction exactly, and the fifth is established here for the first time.
Full output, provenance and the environment table are in `reviews-4/BASELINE-4.md`.

**The standing risk was checked before any edit.**
Every `OSLogStore(scope: .currentProcessIdentifier)` test passes at HEAD, inside `verify.sh` and inside all twelve flake runs, with no canary assertion and no target-line `#require` firing - so the log daemon is delivering here and the production log statements are intact.
It stays in CANNOT ASSESS for CI runners only.

**The reader count in the prompt is wrong, and the corrected figure is in the baseline.**
The prompt says "There are six"; `reviews-3/REVIEW-5.md` says six in OttoUI and one in OttoPersistence.
Measured by enumerating the call sites of every store-opening helper: **seven in OttoUI and two in OttoPersistence, nine in the tree.**
`NotificationActionLogTests` performs four reads, not one, and `NotificationActionTests` matches a `grep` for `OSLogStore` while performing none - the string is in a doc comment.
The "do not add a seventh" rule is applied to nine in this run.

---

## THE WORK LIST - frozen by the round-4 prompt

Seven items, in the order given.
Everything else in rounds 1, 2 and 3's NEXT ROUND stays in NEXT ROUND.

| # | id | what | terminal state |
|---|---|---|---|
| 1 | **F8 + R0-10(b)** | Both exports written to `tmp` on every appearance of Settings, unrequested; `ShareLink` hands out the pre-import file after an import | pending |
| 2 | **F9** | `csvField` does not neutralize a leading `=`, `+`, `-` or `@` | pending |
| 3 | **N3-1 / N3-2** | Ethiopic (+8y) and Indian/Saka (-78y) defeat round 3's plausibility rule | pending |
| 4 | **F10** | `rescheduleSoon` spawns an unstructured `Task` per trigger with no coalescing | pending |
| 5 | **R0-11** | `invalidateOutdatedUpcomingEvents` can leave uncommitted soft-deletes while reporting "nothing invalidated" | pending |
| 6 | **N3-3 + N3-4** | `MappingLogPrivacyTests` reads `OSLogStore` with no canary; `aa92ca7` has never been inside any review range | pending |
| 7 | **R4-3** | `ScheduleOutcome.truncatedAfter` has no consumer anywhere | pending |

Terminal states are **RESOLVED** (with artifact evidence), **DEFERRED** (with reason), or **REJECTED TWICE** (reverted, objection recorded).
There are no others.

## REVIEW RANGES

**This run's FIRST range starts at the branch point, `2d8913c`**, which is the wording round 3's rule was missing and the reason `aa92ca7` escaped three rounds.
Each later stage's range starts at the previous stage's **reviewed head**, and every start is recorded **when the stage opens**, not when its verdict lands.

| stage | range passed to the reviewer | reviewed head | verdict |
|---|---|---|---|
| 0 | - (baseline only) | - | no review; its commit is inside stage 1's range |
| 1 - items 1 + 2 | `2d8913c..` | | |
| 2 - item 3 | | | |
| 3 - item 4 | | | |
| 4 - item 5 | | | |
| 5 - items 6 + 7 | | | |
| aa92ca7 | `aa92ca7^..aa92ca7` | `aa92ca7` | |

**Two stages group two items each, disclosed rather than left to be noticed** (process rule 7).
Stage 1 groups items 1 and 2: both are the export path, and the two questions are the same question asked twice - *what* a complete financial record contains, and *when* one gets written.
Stage 5 groups items 6 and 7: both are a claim with no observer - a log read with no canary, an outcome field with no reader, and a diff no reviewer has read - and all three are closed by making an existing observer observe something it currently does not, at no new query cost.
**One commit per item still holds** in both, and the ranges chain, so no commit falls outside a review.

**`aa92ca7` gets its own reviewer and its own range**, because closing N3-4 means issuing a review of a commit that is not in any of this run's stage ranges. Mixing it into a stage range would hand a reviewer two unrelated diffs and let either hide in the other.

Stage 0's commit is deliberately inside stage 1's range rather than treated as a reviewed parent, so no commit in this run is a range boundary that nobody read - rounds 2 and 3's arrangement, kept.
Each stage's remediation commits land after its reviewed head and are therefore inside the next stage's range - also kept.

---

## ASSUMPTIONS

Recorded as they are made; this list is complete at the end of the run.

1. **The device calendar is Gregorian for both real users.**
   Undeterminable without touching the device, which is prohibited.
   Carried forward unchanged from rounds 1, 2 and 3.
2. **Round 2's ASSUMPTION 2 stays overruled**, as round 3 recorded: `.swiftlint.yml` may gain `custom_rules` entries; no existing rule may be relaxed, disabled, or re-thresholded, and no `excluded:` path may be added to make an existing violation go away.
3. **Release configuration behaves as Debug** except where a finding says otherwise.
   No Release build was produced this run.
4. **`2d8913c` is the intended starting point** and no prior branch is to be merged, rebased or pushed by this run.
