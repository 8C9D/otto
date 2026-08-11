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
| 2 | **R0-9** | The migration guard cannot detect a missing stage | **RESOLVED** - stage 1 |
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
| 0 | - (baseline only, `8f86c1f`) | - | no review |
| 1 - R0-9 | `8806853..` | pending | pending |

Stage 0's commit is deliberately inside stage 1's range rather than being treated as a reviewed parent, so no commit in this run is a range boundary that nobody read.
That is round 2's arrangement, kept.

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

## ITEM 2 - R0-9, the migration guard cannot detect a missing stage

**RESOLVED**, stage 1.

**Reconfirmed at HEAD by executing the defect, not by reading the citation.**
`reviews/REVIEW-0.md:276` claims that appending `OttoSchemaV4` to `schemas` and pointing `mainSchema` at it, with no stage, leaves the suite green.
Done exactly that: a throwaway `OttoSchemaV4` carrying V3's models, `OttoMigrationPlan.schemas` extended to four entries, `OttoContainerFactory.mainSchema` repointed, `stages` untouched at two.

```
✔ Test run with 118 tests in 24 suites passed after 22.407 seconds.
```

Green, with a four-version plan carrying two stages.
The probe was then removed and the two sources restored from the index before the fix was written.

**What changed.**
One test, `stagesChainTheSchemas`, in the file that already owns this contract.
No production change: the plan is correct today, and what was missing was anything that would notice when it stopped being.

**It asserts the chain, not the count.**
`reviews/REVIEW-0.md` proposes `stages.count == schemas.count - 1`.
That catches the forgotten stage and nothing else - a stage added and wired wrong (`V2 → V4`, a duplicate, a reordering) satisfies the arithmetic while leaving a version no stage reaches.
`MigrationStage` publishes no accessor for its endpoints, but its payload reflects as `(fromVersion, toVersion)` for both `.lightweight` and `.custom`, so the guard walks the stages against the schema list and asserts each hop connects version *n* to version *n+1*.

**The reflection fails closed, which is the whole design.**
Reading a framework enum's payload by `Mirror` is exactly the kind of guard that can stop guarding without failing - this file's own header records that happening once, to a version-pinned reference that stayed green through Wave 6A.
So an extraction that finds nothing returns nil and the caller records an issue naming that cause, rather than skipping the stage.

**Falsified in three directions**, because the count half and the chain half and the extraction each have to be load-bearing on their own:

| what was changed | result |
|---|---|
| V4 appended, `mainSchema` repointed, **no stage** (the R0-9 reproduction verbatim) | `Expectation failed: (stages.count → 2) == (versions.count - 1 → 3)` |
| V4 appended **with a wrong stage**, `V2 → V4`, so the count is now right | `Expectation failed: (hop.fromVersion → 2.0.0) == (versions[index] → 3.0.0)` - the case a count assertion passes |
| the payload labels renamed `fromVersion`/`toVersion` → `fromV`/`toV`, simulating an SDK rename | `Expectation failed: … .versions(of: stage → .custom(fromVersion: OttoPersistence.OttoSchemaV1, …)) → nil` |

The second row is the one that justifies the extra machinery: it is a real mistake, it is invisible to the assertion the finding proposed, and it ships a migration that skips a version.

**Cost.** One test, ~0.001 s.
The OttoPersistence suite goes from 118 to 119 tests.

**What this does NOT do.**
It relates `stages` to `schemas` and nothing further: a stage that connects the right two versions but carries a `willMigrate`/`didMigrate` that does the wrong thing, or nothing, still passes.
Proving a stage's *body* correct is what `MigrationTests` and `WatermarkRelocationMigrationTests` are for, and adding a version means adding a case there too.

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
