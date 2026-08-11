# PROD-READINESS-3 - Otto, round 3

Bounded remediation of a frozen list, 2026-08-11, branch `prod-readiness-3/2026-08-11`, from commit `8806853` on `prod-readiness-2/2026-08-10`.

Baseline artifact: `reviews-3/BASELINE-3.md`.
Review trail: `reviews-3/`.

**This is not a discovery sweep.**
Every item below was found, evidenced and adversarially reviewed in the two runs that produced `PROD-READINESS.md` / `reviews/` and `PROD-READINESS-2.md` / `reviews-2/`.
Round 3's only job is to close a named subset honestly and to say plainly what it could not close.
Neither prior record is edited by this run.

Round 1's and round 2's terminal states and scope constraints still bind, except where the round-3 prompt overrules them explicitly - it does so twice, and both are recorded under ASSUMPTIONS.

---

## Baseline

`scripts/verify.sh` at `8806853`, from a clean clone: **exit 0 - OttoDomain 251, OttoPersistence 118, OttoUI 196, total 565**, `swiftlint --strict` clean.
Simulator suite from `Packages/OttoUI/`: exit 0, `** TEST SUCCEEDED **`, **108 / 70 / 31 tests, 7 known issues**.
Non-Gregorian harness: **1 / 1 / 5** issues under `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura`.

All four reproduce the round-3 prompt's prediction exactly.
Full output, provenance and the environment table are in `reviews-3/BASELINE-3.md`.

**The standing risk was checked before any edit.**
All four `OSLogStore(scope: .currentProcessIdentifier)` tests pass at HEAD, with neither the canary assertion nor the target-line `#require` firing - so the log daemon is delivering here and the production log statements are intact.
It stays in CANNOT ASSESS for CI runners only.

---

## THE WORK LIST - frozen by the round-3 prompt

Seven items, in the order given.
Everything else in round 1's and round 2's NEXT ROUND stays in NEXT ROUND.

| # | id | what | terminal state |
|---|---|---|---|
| 1 | **R0-7 / N2-2** | Calendar days already stored under a non-Gregorian device calendar are never repaired | pending |
| 2 | **R0-9** | The migration guard cannot detect a missing stage | pending |
| 3 | **F1's CI guard** | F1's four reading sites have no guard that runs on a Gregorian machine | pending |
| 4 | **R4-2** | `NotificationCoordinator` compiles to nothing under host `swift test`; `handleBackgroundRefresh` never calls `onOutcome` | pending |
| 5 | **R0-5** | A corrupt stored watermark becomes "no watermark", unlogged | pending |
| 6 | **F11 remainder + R0-10(a)** | Import/export and cancellation/verification unlogged; `.fileImporter`'s `.failure` half dropped | pending |
| 7 | **R5-1** | A snooze that scheduled nothing logs `handled` identically to one that worked | pending |

Terminal states are **RESOLVED** (with artifact evidence), **DEFERRED** (with reason), or **REJECTED TWICE** (reverted, objection recorded).
There are no others.

**Items 1 and 2 are executed in the opposite order to their numbering, by the prompt's own instruction.**
Item 1's authorization to lift the schema freeze is conditional on item 2 landing first, because `OttoMigrationPlan.schemas` and `stages` are two independent literals and no test relates them.
So stage 1 is item 2 and stage 2 is item 1.

## REVIEW RANGES

Each stage's range starts at the **previous stage's reviewed head**, and the start is recorded **when the stage opens**, not when its verdict lands.
Round 2's reviewers raised the missing row four consecutive times; the start is knowable from the stage's first commit and only the head and the verdict have to wait.

| stage | range passed to the reviewer | reviewed head | verdict |
|---|---|---|---|
| 0 | - (baseline only) | - | no review |
| 1 - R0-9 | `8806853..` | pending | pending |

---

## ASSUMPTIONS

Recorded as they are made; this list is complete at the end of the run.

1. **The device calendar is Gregorian for both real users.**
   Undeterminable without touching the device, which is prohibited.
   Carried forward unchanged from rounds 1 and 2.
2. **Round 2's ASSUMPTION 2 is overruled by the round-3 prompt.**
   `.swiftlint.yml` may gain `custom_rules` entries; no existing rule may be relaxed, disabled, or have its threshold raised, and no `excluded:` path may be added to make an existing violation go away.
3. **Release configuration behaves as Debug** except where a finding says otherwise.
   No Release build was produced this run.
4. **`8806853` is the intended starting point** and neither prior branch is to be merged, rebased or pushed by this run.

## CANNOT ASSESS

Carried forward from round 2, unchanged unless an item says otherwise:

- Whether the real `UNUserNotificationCenter` daemon preserves an explicitly attached Gregorian calendar across the archive/restore round trip on a **device**.
- Real notification delivery, Focus breakthrough, interruption levels.
  Requires hardware.
- Release-configuration behavior of any kind.
- Accessibility-label rendering.
  No AX client on this host.
- Whether `OSLogStore(scope: .currentProcessIdentifier)` is readable, and delivering, on the GitHub-hosted CI runners.
  Confirmed working on this host at HEAD; CI cannot be exercised from here because network calls are prohibited.
