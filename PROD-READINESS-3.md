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
| 1 - R0-9 | `8806853..87d6508` | `87d6508` | **PASS-WITH-FINDINGS** (`reviews-3/REVIEW-1.md`) |
| 2 - R0-7 / N2-2 | `87d6508..` | pending | pending |

Stage 0's commit is deliberately inside stage 1's range rather than being treated as a reviewed parent, so no commit in this run is a range boundary that nobody read.
That is round 2's arrangement, kept.
Stage 1's remediation commits land **after** the reviewed head `87d6508` and are therefore inside stage 2's range, not orphaned between them - also round 2's arrangement.

**One commit outside every review range that has ever been issued, inherited rather than created here.**
`reviews-3/REVIEW-1.md` finding 4 measured it: round 2's last review covered `5d8ed6a..3ce3e01`, and `aa92ca7` - a code commit - landed after it, with only `70f3f19` and `8806853` (both documents) between.
Round 3's first range starts at `8806853` because the prompt fixes that as the starting point, so `aa92ca7`'s diff has never been read by any reviewer in either round.
Nothing untested is carried: `reviews-3/BASELINE-3.md` re-ran all four measurements against the state at `8806853`, which includes `aa92ca7`'s effect.
Carried to NEXT ROUND rather than closed, because closing it means issuing a review of a range this run is not scoped to.
The range rule at the head of this section is written for stage-to-stage chaining inside a run and therefore says nothing about a run's *first* start, which is exactly where the gap is; that is the wording to fix, not just the incident.

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
`PROD-READINESS.md:76` proposes `stages.count == schemas.count - 1`.
That catches the forgotten stage and nothing else - a stage added and wired wrong (`V2 → V4`, a duplicate, a reordering) satisfies the arithmetic while leaving a version no stage reaches.
`MigrationStage` exposes no `fromVersion` property, but its cases are public and carry the endpoints, so the guard destructures each stage and asserts hop *n* connects version *n* to version *n+1*.

**And it asserts the versions strictly increase**, which is a separate claim from the hops and was missing until remediation - see below.

**The extraction is a `switch`, not `Mirror`, and it fails closed either way.**
The first version of this guard read the payload by reflection. Both forms read the same thing, but only the switch turns a future SDK that renames or reorders the payload into a **compile error at the Xcode upgrade** rather than a runtime nil that reddens the suite later for a reason nobody connects to the toolchain.
A SwiftData release that adds a third case still reaches `@unknown default`, returns nil, and the caller records an issue naming that cause - a guard that quietly stops guarding is the failure this file was rebuilt to prevent.

**Falsified in four directions**, because the count, the ordering, the chain and the extraction each have to be load-bearing on their own:

| what was changed | result |
|---|---|
| V4 appended, `mainSchema` repointed, **no stage** (the R0-9 reproduction verbatim) | `Expectation failed: (stages.count → 2) == (versions.count - 1 → 3)` |
| V4 appended **with a wrong stage**, `V2 → V4`, so the count is now right | `Expectation failed: (hop.fromVersion → 2.0.0) == (versions[index] → 3.0.0)` - the case a count assertion passes |
| V4 appended **with its identifier left at `3.0.0`** and a correct-looking `V3 → V4` stage | `Expectation failed: (versions[index - 1] → 3.0.0) < (versions[index] → 3.0.0)` |
| `case .lightweight` renamed `.lightweightXX`, simulating an SDK rename | `error: expression pattern of type 'SwiftDataError' cannot match values of type 'MigrationStage'` - it does not compile, which is the point |

The second row justifies the chain over a count: a real mistake, invisible to the assertion the finding proposed, shipping a migration that skips a version.
The third row is the reviewer's, and is the reason for the remediation below.

**Cost.** One test, ~0.001 s.
The OttoPersistence suite goes from 118 to 119 tests.

**What this does NOT do.**
It relates `stages` to `schemas` and nothing further: a stage that connects the right two versions but carries a `willMigrate`/`didMigrate` that does the wrong thing, or nothing, still passes.
Proving a stage's *body* correct is what `MigrationTests` and `WatermarkRelocationMigrationTests` are for, and adding a version means adding a case there too.

### Remediation after `reviews-3/REVIEW-1.md`

The verdict is PASS-WITH-FINDINGS.
Three of its four findings are defects in this stage's own change and are fixed inside the stage; the fourth is inherited and is recorded under REVIEW RANGES and NEXT ROUND.

- **Finding 1 (P2) - the guard went green on a version identifier that was never bumped, and that is the mistake this gate exists to catch.**
  Reproduced here before fixing it: a fourth schema carrying V3's models with `Schema.Version(3, 0, 0)`, plus a correct-looking `.lightweight(V3 → V4)` stage, left **all five tests in the file green** on a chain of `1.0.0 → 2.0.0 → 3.0.0 → 3.0.0`.
  The hop assertions compare `3.0.0` to `3.0.0` and agree; `guardTargetsTheLiveSchema` cannot see it either, because `live.version == terminal.versionIdentifier` holds trivially and the entity sets are identical whenever the new version keeps the same models - which is exactly what a value-repair migration does.
  The test was titled "in order" and asserted no ordering.
  Now it asserts `versions[index - 1] < versions[index]` across the whole list, separately from the hops, and the reproduction fails at that line.
  This one mattered beyond tidiness: the run reorders items 1 and 2 **so that this test gates the schema-freeze lift**, and copying the previous version and forgetting to bump it is the single likeliest way to get V4 wrong.
- **Finding 2 (P3) - the reflection was unnecessary and the justification for it was overstated.**
  The ledger and the code both said `MigrationStage` "publishes no accessor … so this reads the enum's own payload by reflection".
  Literally true of properties, and false as a claim about the API: the cases are public and pattern-matchable.
  Verified independently rather than taken on the reviewer's word - the `switch` form typechecks against this SDK, and renaming the case to `.lightweightXX` is a compile error, so the probe resolves the real type.
  Replaced.
- **Finding 3 (P3) - a citation pointing at the wrong file.**
  This section attributed `stages.count == schemas.count - 1` to `reviews/REVIEW-0.md`.
  Verified: `grep -n "stages.count" reviews/REVIEW-0.md PROD-READINESS.md` returns exactly one line, `PROD-READINESS.md:76`, and nothing in `reviews/REVIEW-0.md`.
  The round-1 ledger row credits REVIEW 0 in its *source* column, which is what made the conflation a single step.
  Corrected above.
  This is the fourth recurrence across three rounds of a citation measured once and never re-derived.
- **Finding 4 (P3) - `aa92ca7` is outside every review range ever issued.**
  Inherited, not created here.
  Recorded under REVIEW RANGES and carried to NEXT ROUND.

The reviewer also settled a claim this repository cannot settle on its own: the plan contains no `.lightweight` stage, so the extraction's lightweight half is unexercised in-repo.
It was exercised with a real `.lightweight` stage during the review and during falsification rows 2 and 3 above, and it reads that payload correctly.

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
