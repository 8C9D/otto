# REVIEW-2 - round 4, stage 2 (item 3, N3-1 / N3-2)

Range reviewed: `6ef51ee..00cb0f1` (three commits: `abef4a7`, `2afde29`, `00cb0f1`).
Reviewed head: `00cb0f1`.
Ledger: `PROD-READINESS-4.md`. Baseline: `reviews-4/BASELINE-4.md`. Prior verdict in this run: `reviews-4/REVIEW-1.md`.

verdict: PASS-WITH-FINDINGS

## Summary

The code change is right, it is the smallest change that closes the named half of the item, and the guards on it bite.
I re-derived the sixteen-calendar offset table against Foundation from a script that imports no Otto code and it reproduces digit for digit, including `indian [-79, -78]` and `ethiopicAmeteMihret [-8, -7]`.
Thirteen calendars can corrupt a stored day; round 3's symmetric century caught eleven, the asymmetric window catches twelve, and Ethiopic is the only miss - exactly what the source comment claims.
I reproduced the ledger's "Reconfirmed at HEAD by executing the defect" block by driving the real `NotificationScheduler` over all four anchors and it matches on every field and every fire day, including the four wrong days an Indian-written anchor schedules.
I broke the rule four ways at the call site and every mutation failed on assertions that name the change.
All five baseline dimensions are at or above `reviews-4/BASELINE-4.md`, all nine per-commit builds pass, and the stage touches no schema, no lint rule, no workflow, no dependency and no config key.

What is not sound is the record around the code, in three places, and one of them puts a false correction into the project's history.

First, the ledger's headline correction of the K sweep is itself wrong.
It declares "**64 is wrong and 63 is right, arithmetically**" and says three prior documents "agreed on a number that 2K+1 refutes".
Measured here under the parameters those documents state, the answer is **64**, and the 2K+1 model the argument rests on does not hold at K=31 because the Ethiopic offset flips between -7 and -8 inside the window.
`PROD-READINESS-3.md` and `reviews-3/REVIEW-4.md` were right; the ledger has overruled them with an argument in place of a measurement.

Second, three of the four falsification counts for this item do not reproduce, and one of them is a verbatim carry-over of round 3's number that this stage's own new test invalidates.
`reviews-4/REVIEW-1.md` finding 4 raised exactly this defect one stage earlier and the ledger states it swept every such number; item 3's table was not swept.

Third, `docs/next-wave.md` - the whole content of commit `00cb0f1`, and the only thing this run does for the users it cannot detect - tells them to "re-pick every date the log names", naming four dates.
Two of them have no picker in the app at all, and for a paused or an un-converted trial subscription one of them has no affordance of any kind.
The paragraph's own headline is "**The repair is manual, it works**", and no artifact in this run shows anyone performing it.

None of this is a defect in shipped behaviour and none of it makes the item's terminal state wrong - the decline of the `createdAt` cross-check rests on the sensitivity-versus-gap table, which reproduces cell for cell.
I considered REJECT and did not take it because the code is correct and the guards are real; the three P2s are record and copy defects, and they should be fixed before this item is stamped, not by redoing the stage.

## What I ran

All mutation work was done in three detached worktrees I created under my own temp path; all three are removed.
I made no commit, ran no network command, touched no physical device, and did not modify the main working tree - which carried other people's uncommitted work throughout, and still does.
The branch advanced from `2082b69` to `f3e5aa1` while I measured; none of the four files in my range has changed since `00cb0f1`, committed or uncommitted.

### The five baseline dimensions, re-measured at `00cb0f1`

**1. `./scripts/verify.sh` - exit 0.**

```
== VERIFIED: 00cb0f161c9cce857da0c7c60c6a510be01f9f95 builds, tests, and lints from a clean clone
   OttoDomain: 261
   OttoPersistence: 124
   OttoUI: 208
   total: 593 tests
```

Baseline `2d8913c` was 258 / 124 / 207 = 589; stage 1 (`6ef51ee`) was 260 / 124 / 207 = 591.
The +1 domain is this stage's net domain test count (one test removed, two added) and the +1 OttoUI is `indianAnchorWithdrawsTheCoverageClaim`.

**2. `swiftlint --strict`, standalone.**

```
Done linting! Found 0 violations, 0 serious in 221 files.
```

221 files, unchanged from stage 1 - this stage adds no file.

**3. Simulator suite, from `Packages/OttoUI/`, two consecutive runs.**

```
run 1  ✔ 118 in 22 suites  ✔ 72 in 12 suites  ✘ 40 in 8 suites passed with 7 known issues  ** TEST SUCCEEDED **  rc=0
run 2  ✔ 118 in 22 suites  ✔ 72 in 12 suites  ✘ 40 in 8 suites passed with 7 known issues  ** TEST SUCCEEDED **  rc=0
```

Baseline 117 / 72 / 36; stage 1 117 / 72 / 40. The +1 in the first bucket is the new `OttoServicesTests` test. The 7 known issues are the unchanged `EmptyStateTests` accessibility assertions.

**4. Non-Gregorian harness - 1 / 1 / 5, the same five citations.**

Run from the repo root with an absolute bundle path.

```
th_TH@calendar=buddhist          1 issue   DisplayFormattingTests.swift:49:9  ("Aug 15, 2569 BE") == "Aug 15, 2026"
ja_JP@calendar=japanese          1 issue   DisplayFormattingTests.swift:49:9  ("Aug 15, Reiwa 8") == "Aug 15, 2026"
ar_SA@calendar=islamic-umalqura  5 issues  DisplayFormattingTests.swift:49:9  ("Rab. I 2, 1448 AH") == "Aug 15, 2026"
                                           DisplayFormattingTests.swift:59:9  ("Every ٤٥ days") == "Every 45 days"
                                           DisplayFormattingTests.swift:68:9  ("١ subscription") == "1 subscription"
                                           DisplayFormattingTests.swift:69:9  ("٣ subscriptions") == "3 subscriptions"
                                           NotificationReconciliationTests.swift:170:9  ("… on Rab. I 12.") == "… on Aug 25."
```

Identical to `reviews-4/BASELINE-4.md`, at 208 tests rather than 207.

**5. Flake rate - 11 of 12, then 12 of 12; the one failure is pre-existing and not this stage's.**

Batch A at `00cb0f1`, twelve runs: **pass=11 fail=1**. Run 12 failed with 2 issues:

```
✘ "an engaged kill switch blocks enabling - releasing the brake is its own deliberate act"
    SyncActivationServiceTests.swift:120:15  an error was expected but none was thrown
    SyncActivationServiceTests.swift:125:9   try loadState(suite).isEnabled == false
```

I then ran two clean batches back to back with nothing else of mine running:

```
2d8913c (baseline)  12 runs  pass=12 fail=0   (12.6 s - 52.3 s)
00cb0f1 (head)      12 runs  pass=12 fail=0   (14.5 s - 50.6 s)
```

So 23 of 24 at the reviewed head and 12 of 12 at baseline.
`git log 2d8913c..HEAD -- SyncActivationServiceTests.swift SyncActivationService.swift` is empty: round 4 has not touched this test or its subject.
The suite is `.serialized` and comments that "`UserDefaults` is not Sendable, so every use opens its own instance over the same suite; the suite name is the shared state" (`SyncActivationServiceTests.swift:41-43`), which is the shape of a `cfprefsd` propagation race between the instance that writes the kill switch and the instance that reads it.
Batch A overlapped my own Foundation probe scripts, so it was under load I created; I record the failure because it happened, and I attribute it to a latent pre-existing race rather than to this stage.

### Per-commit build sweep

`swift build --build-tests --package-path Packages/<pkg>` for OttoDomain, OttoPersistence and OttoUI at each of the three commits in the range: **9 of 9 OK.**

```
abef4a7 OttoDomain OK   abef4a7 OttoPersistence OK   abef4a7 OttoUI OK
2afde29 OttoDomain OK   2afde29 OttoPersistence OK   2afde29 OttoUI OK
00cb0f1 OttoDomain OK   00cb0f1 OttoPersistence OK   00cb0f1 OttoUI OK
```

### Independent re-derivation against Foundation (standalone script, imports no Otto code)

The doc comment's offset table, over every day of Gregorian 2026 at noon America/Toronto:

```
buddhist [+543,+543]  chinese [-1984,-1983]  coptic [-284,-283]  ethiopicAmeteMihret [-8,-7]
hebrew [+3760,+3761]  indian [-79,-78]       islamic/Civil/Tabular/UmmAlQura [-579,-578]
japanese [-2018,-2018]  persian [-622,-621]  republicOfChina [-1911,-1911]
ethiopicAmeteAlem [0,0]  gregorian [0,0]  iso8601 [0,0]
```

Every row matches `StoredDayPlausibility.swift:47-53` exactly.
For the 2026-08-06 instant: **13 corrupting calendars, old symmetric century caught 11, the new 70/100 window catches 12, Ethiopic the only miss.**
The 1900-01-01..2126-12-31 sweep (82,910 days): the new rule rejects `1900-01-01 .. 1955-12-31`, the **newly** rejected set (old accepted, new rejects) is `1926-01-01 .. 1955-12-31`, and nothing is newly accepted.

### Reproducing the ledger's "executing the defect" block

I added a probe suite to my worktree that drives the real `NotificationScheduler` and prints the fire days, ran it at `00cb0f1`, then again with round 3's symmetric century restored (which is `abef4a7`'s behaviour), then removed it.

With the symmetric century restored - the state the ledger and `ImplausibleStoredDayTests.swift:74-83` say they measured:

```
indian(-78)   anchor=1948-05-15 scheduled=4 ledgerFailures=0 canClaimCoverage=true
              fireDays=[2026-8-12, 2026-9-12, 2026-9-23, 2026-10-12]
ethiopic(-8)  anchor=2018-11-30 scheduled=4 ledgerFailures=0 canClaimCoverage=true
              fireDays=[2026-8-27, 2026-9-27, 2026-10-19, 2026-10-27]
healthy       anchor=2026-08-06 scheduled=4 ledgerFailures=0 canClaimCoverage=true
              fireDays=[2026-9-3, 2026-10-3, 2026-11-3, 2026-11-4]
buddhist      anchor=2569-08-06 scheduled=0 ledgerFailures=1 canClaimCoverage=false
```

**Byte-for-byte the ledger's block**, every field and every fire day.

At `00cb0f1`, unmutated:

```
indian(-78)   scheduled=4 ledgerFailures=1 canClaimCoverage=false   fireDays unchanged
ethiopic(-8)  scheduled=4 ledgerFailures=0 canClaimCoverage=true    coveredThrough=2026-11-09
```

So both disclosed limitations are real and I confirmed them rather than taking them on trust: the fix withdraws the coverage claim for Indian and **does not stop the four wrong-day reminders**, and Ethiopic is untouched - four reminders on the wrong days while Today states coverage through the full horizon.

### Falsifications

Each printed the exact text it removed and asserted exactly one occurrence in the file before mutating; each restored the file and verified it byte-identical afterwards.

| mutation | ledger records | I measured |
|---|---|---|
| `isPlausibleStoredDay` body → `abs(year - today.year) <= 100` | 6 domain issues + 2 through the scheduler | **15 domain issues / 3 tests** + 2 / 1 test ❌ |
| `plausibleStoredDayYearsBehind` 70 → 78 | "the same 6 + 2" | **16 domain issues / 3 tests** + 2 / 1 test ❌ |
| `plausibleStoredDayYearsAhead` 100 → 70 (symmetric the other way) | 5 issues | 5 issues / 2 tests ✅ |
| the `if !implausible.isEmpty { … continue }` block deleted from `NotificationScheduler` | 6 issues over 4 tests | **8 issues over 5 tests** ❌ |

The failing tests are the right ones in every case:

```
M1/M2 domain: coverageAcrossFoundationsCalendars, indianIsCaughtByTheAsymmetry, windowEdges
M1/M2 ui:     an Indian-written anchor can no longer claim coverage either
M3 domain:    realDatesSurvive, windowEdges
M4 ui:        coverageIsNotClaimed, theOthersStillSchedule, theLedgerIsNotTouched,
              indianAnchorWithdrawsTheCoverageClaim, SchedulingLogTests' skip-line test
```

The substance of every row holds - the eight-year margin really is load-bearing, and the asymmetry really is needed in both directions. Only the counts are wrong.

## Findings

### 1 - P2. The K-sweep "correction" from 64 to 63 is itself wrong, and it convicts three prior records of an error they did not make

**Evidence.** `PROD-READINESS-4.md:245-247`:

> `| 31 | **63** / 4001 (1.57%) | **64** | **63** |`
> "**64 is wrong and 63 is right, arithmetically**: a window of ±K days over a single collision point contains exactly 2K+1 days, and 3, 7, 15, 63 is that sequence. Round 3's ledger overrode `reviews-3/REVIEW-3.md`'s correct 63 with 64 … Three documents agreed on a number that 2K+1 refutes."

Repeated at `:538` and used at `:594` to record N3-2 as closed "with its K=31 false-positive figure corrected from 64 to 63".

I re-derived it from a standalone Foundation script under the parameters the prior records state - `America/Toronto`, `createdAt` = Gregorian 2026-08-06 12:00, the **thirteen** calendars that can corrupt (all sixteen minus `gregorian`, `iso8601` and `ethiopicAmeteAlem`, which writes the Gregorian numbers exactly on this SDK), scanning the 4001 ordinary Gregorian anchors in the eleven years before creation, flagging an anchor when its triple read under any of the thirteen lands within K days of `createdAt`:

```
K= 1  flagged=  3 / 4001 (0.07%)   2018-11-29 .. 2018-12-01
K= 3  flagged=  7 / 4001 (0.17%)   2018-11-27 .. 2018-12-03
K= 7  flagged= 15 / 4001 (0.37%)   2018-11-23 .. 2018-12-07
K=31  flagged= 64 / 4001 (1.60%)   2018-10-29 .. 2018-12-31
```

**64**, and 1.60% - which is `PROD-READINESS-3.md:242-246` exactly, and `reviews-3/REVIEW-4.md:214` exactly.

The reason the 2K+1 argument fails is measurable. Printing the Ethiopic band with its deltas gives 64 stored days spanning d = -31 to d = +31: the Ethiopic year offset flips between -7 and -8 across its new year and Ethiopic months are 30 days, so reading Gregorian triples under it is neither a pure translation nor injective, and one extra stored day lands inside the ±31 window. At K = 1, 3 and 7 the window does not reach the discontinuity, which is why those three are 2K+1 and agree everywhere. **The model is right for three of the four rows and wrong for the one the ledger used it to overturn.**

The only way I could produce 63 was by scanning a window *centred* on `createdAt` (which excludes the 2018 Ethiopic band entirely) while leaving `ethiopicAmeteAlem` in the candidate set, so that every "false positive" counted is the anchor matching *itself* through an identity calendar. That is an artifact, not a measurement.

**Why this is P2 and not P3.** It is not a rounding disagreement: the ledger states a number it says it measured, states an argument it says is decisive, and on the strength of both writes into the permanent record that `PROD-READINESS-3.md` and `reviews-3/REVIEW-4.md` are wrong and that `reviews-3/REVIEW-4.md`'s "re-derived it to the digit" was mistaken. It is the one place in this stage where a claim is not merely unreproducible but actively corrupts a prior record that was correct. It is not P1 because the decision it supports - declining the `createdAt` cross-check - does not depend on it: that rests on the sensitivity-versus-gap table, which reproduces exactly (below), and 1.60% versus 1.57% changes nothing.

**Why the builder missed it.** The arithmetic model is clean, it explains three of the four rows perfectly, and it flatters a reviewer's instinct that a disagreeing measurement must be a boundary bug. Having derived it, the fourth row was concluded rather than re-run against the calendar that actually produces the band.

### 2 - P2. Three of the four falsification counts do not reproduce, and one is a stale copy of round 3's number that this stage's own test refutes

**Evidence.** `PROD-READINESS-4.md:304-309`, the "Falsified four ways" table for item 3. Measured against the shipped tests, with the removed text printed and the occurrence count asserted before each mutation:

- Row 1, "back to round 3's symmetric century": records **6 domain issues**, produces **15**. The 6 cannot be reached from the shipped test: `indianIsCaughtByTheAsymmetry` alone contributes 13 (one at `StoredDayPlausibilityTests.swift:147` plus twelve from the loop at `:151-157`), `coverageAcrossFoundationsCalendars` 1 and `windowEdges` 1. The "+2 through the real scheduler" half reproduces exactly.
- Row 2, "backward bound set to 78": records "the same 6 + 2", produces **16 + 2**. It is not "the same" as row 1 either - the extra issue is `#expect(CalendarDay.plausibleStoredDayYearsBehind == 70)` at `:196`.
- Row 4, "the scheduler stops calling `implausibleStoredDays`": records **6 issues over 4 tests**, produces **8 issues over 5 tests**. Six-over-four is verbatim `PROD-READINESS-3.md:184` and `reviews-3/REVIEW-2.md:84` - round 3's figure for the same mutation. This stage adds `indianAnchorWithdrawsTheCoverageClaim`, which fires under exactly this mutation on two assertions, so the number this stage's own work invalidates is the number it published.
- Row 3, "both bounds set to 70", records 5 and produces 5 over 2 tests. ✅

**Why this is P2 and not P3.** `reviews-4/REVIEW-1.md` finding 4 raised precisely this defect one stage earlier, and `PROD-READINESS-4.md:139` responds that "every count below is **re-derived against the shipped tests** … `reviews-4/REVIEW-1.md` finding 4 caught one of these eight numbers being stale; all of them were". That sweep was applied to items 1 and 2 and not to item 3, written in the same run by the same hand after the correction was accepted. Three of four rows wrong, one of them demonstrably copied from a superseded round, is a pattern rather than an arithmetic slip - and the falsification table is the only thing standing between "I broke it and a test failed" and "I asserted that I did".

**Why the builder missed it.** Same mechanism the builder itself diagnosed for stage 1: the table is written as the mutations run and the tests grow afterwards. Row 4 additionally looks like a re-measurement because it was true when round 3 recorded it.

### 3 - P2. The manual repair shipped to users names two dates the app offers no way to re-pick, under a heading that asserts it works

**Evidence.** `docs/next-wave.md:19` - the whole substance of commit `00cb0f1`:

> "For each affected subscription, open it and **re-pick every date the log names** - the next charge date, and where they exist the trial start, the pause resume date, and the last-used date."

Under the heading at `:9`: "**The repair is manual, it works**, and nothing in the app says so."

Two of the four named dates have no picker anywhere in the app. `grep -rn DatePicker Packages/OttoUI/Sources Otto` returns six sites: `AddEditSubscriptionView.swift:160` and `:170` (the anchor, "Started on" / "Next charge on"), `:217` ("Trial started"), `PauseFlowView.swift:38`, `CancellationSectionView.swift:173`, `SettingsView.swift:57` (reminder time). So:

- **`lastUsedDate` has no picker at all.** Its only writer is `SubscriptionFlowService.recordUsage` (`:148-152`), which sets it to `today` and nothing else, reached from one button - `PauseFlowView.swift:172`, "I used this today". An edit carries the old value through untouched: `SubscriptionFormModel.swift:362`, `lastUsedDate: original?.lastUsedDate`.
- **`pauseEndsOn` has no picker for an already-paused subscription.** `PauseFlowView`'s date picker sits behind "Pause billing…", which `PauseSectionView` renders only when `effectiveStatus(asOf:) == .active` (`PauseFlowView.swift:141-147`). A paused subscription gets "Resume billing now" and nothing else (`:135`). An edit carries the episode through untouched: `SubscriptionFormModel.swift:356`, `pauseEpisodes: original?.pauseEpisodes ?? []`, and `pauseEndsOn` is derived from the open episode (`PauseEpisode.swift:168`).

For a **Buddhist-style (positive-offset) corruption the `lastUsedDate` case is a dead end**, not merely a mis-worded step. `UsageSectionView` renders only when `effectiveStatus(asOf:) == .active` (`PauseFlowView.swift:164`). A subscription stored `.paused` with `pauseEndsOn` = 2569 never satisfies `isResumedPause` (`Subscription.swift:235`), and one stored `.trial` with a 2569 conversion date never satisfies `isConvertedTrial` (`:242`), so neither ever renders the Usage section - and the log line names the offending day while the app offers no control that can change it.

The two fields *are* repairable by other actions the paragraph does not mention: tapping "I used this today" overwrites `lastUsedDate` with a plausible day (at the cost of recording a use that did not happen), and "Resume billing now" closes the episode so `pauseEndsOn` becomes nil. So the outcome claim survives; the procedure as written does not.

**Why this is P2.** This paragraph is the entire user-facing deliverable of the reviewed head and the only mitigation this run offers the users it cannot detect. It asserts "it works" in bold, and the ledger stamps item 3 partly on it (`PROD-READINESS-4.md:318`: "`docs/next-wave.md` now tells them how to repair it"). No artifact anywhere in this run shows the procedure being performed. A user following it literally re-picks the anchor, sees the subscription still skipped because of a field the instructions told them to re-pick and the app will not let them, and concludes the repair does not work.

**Why the builder missed it.** The five fields were enumerated from `implausibleStoredDays` (`StoredDayPlausibility.swift:113-125`), which is the correct list of what is *checked*. Nothing enumerated the same five against the app's *writers*, and the two that fail are the two whose writers are flows rather than form fields.

### 4 - P3. "Round 3's own doc comment" contains no such sentence

**Evidence.** `StoredDayPlausibility.swift:59-62`, shipped in source:

> "Round 3's own doc comment named "forty years beyond the oldest plausible billing anchor" as its justification for a century"

and `PROD-READINESS-4.md:282`: "round 3's own doc comment contains the refutation - it justified a century as *"forty years beyond the oldest plausible billing anchor"*".

`git show 6ef51ee:…/StoredDayPlausibility.swift` is round 3's doc comment in full. It justifies the century with "A century is inside all of those and outside any date a user could mean" and "Deliberately generous within that limit". The quoted phrase does not appear in it, or in any doc comment: `grep -rn "forty years"` over the whole repo returns `PROD-READINESS-3.md:303` and the round-4 texts that cite it.

The quotation is verbatim and the inference drawn from it is fair, so this is a citation pointing at the wrong artifact rather than a fabrication. It matters because the rhetorical force of "round 3's own **doc comment** contains the refutation" comes from its being in the code the change edits, and it is not.

**Why the builder missed it.** Round 3's ledger and round 3's doc comment were read together while writing the replacement, and the stronger of the two attributions was the one written down.

### 5 - P3. The reviewed head records none of the measurements this review was asked to check, breaking the rule this range itself introduces

**Evidence.** `abef4a7` - the first commit in my range - adds `PROD-READINESS-4.md:82-83`:

> "**A stage's reviewed head is the commit that RECORDS its measurements, not its last code commit**, so the numbers a reviewer is asked to check are inside the range it is given rather than only in the tree it is standing on."

At `00cb0f1`, `PROD-READINESS-4.md` is 198 lines, has no `## ITEM 3` section, and its REVIEW RANGES table has stage 2's range, head and verdict cells all blank. Every measurement table for this item - the K sweep, the sensitivity table, the field-by-field table, the falsification table - was written in `2082b69` ("Record items 4 through 7"), five commits past the reviewed head. The ledger later discloses the cause at `:490`: "Stages 2, 3 and 4 were measured jointly at `b054506`, not three times at three heads."

The consequence is benign for correctness and I reproduced the tables anyway from the current tree, but the rule was written in this range and broken by this range, and `reviews-4/REVIEW-1.md` finding 9 already recorded the same class of drift one stage earlier. Neither commit in this range records a measurement: `abef4a7` is stage 1's bookkeeping and `00cb0f1` is a documentation paragraph.

**Why the builder missed it.** The rule was written as a fix for stage 1's drift, in the same commit that fixed stage 1's row, and was then not applied to the stage that commit opened.

### 6 - P3. `N4-2` is cited in shipped source and did not exist for six commits

**Evidence.** `ImplausibleStoredDayTests.swift:101-107`, added by `2afde29`, states the fix's central limitation and defers the record to it:

> "this does NOT stop the wrong-day reminders … `PROD-READINESS-4.md` N4-2 records it."

At `00cb0f1`, `grep -n "N4-2" PROD-READINESS-4.md` returns nothing: N4-1 and N4-3 through N4-6 are each coined where they are stated, and N4-2 is only ever referred to. It was finally defined at `PROD-READINESS-4.md:611` several commits later, and the definition is good (it is a P2 and it says the right thing). Recorded because the identifier a shipped test comment points a future reader at named nothing at the moment the reviewer was asked to check it, and because the thing deferred is this item's most important residual risk. **Closed by later work**, not by this range.

### 7 - P3. The twelve-iteration loop in the stage's headline test has one degree of freedom the function ignores

**Evidence.** `StoredDayPlausibilityTests.swift:149-157`:

```swift
// Every month, not just the one instant: the Saka offset is 78 or 79
// depending on whether the date falls before or after the new year.
for month in 1 ... 12 {
    let stored = try #require(CalendarDay(year: 2026 - 78, month: month, day: 15))
```

The year is `1948` on all twelve iterations, and `isPlausibleStoredDay` reads only `year` (`StoredDayPlausibility.swift:79-82`). Twelve assertions with one distinct input. The comment's stated reason for the loop - that the offset is 78 **or 79** - is exactly the case the loop does not construct: `2026 - 79 = 1947` never appears in the test, in either file. The 79 branch is caught anyway (it is further from the bound, not nearer), so nothing is unguarded; what is wrong is that the test claims month coverage it cannot have and multiplies its own issue count by twelve, which is what makes finding 2's row 1 unreconstructable.

### 8 - P3. The first assertion of `indianIsCaughtByTheAsymmetry` cannot fail

**Evidence.** `StoredDayPlausibilityTests.swift:146`:

```swift
#expect(abs(indian.year - today.year) <= 100, "round 3's symmetric century accepted this day")
```

`indian` is `day(1948, 5, 15)` and `today` is `day(2026, 8, 11)`, both constructed three lines above; `abs(1948 - 2026) = 78`. No production code participates. The doc comment is honest that this is "that rule, spelled out", so it is documentation and not a false guard - but it sits inside a `⛔` test whose title says "the symmetric rule would not have", and it is the only assertion in the file that makes that comparison, so a reader is entitled to think something checks it. What actually checks it is my mutation M1 and the `knownUncatchable` equality.

### 9 - P3. "The rule newly rejects only 1900-01-01 to 1955-12-31" is the wrong set

**Evidence.** `PROD-READINESS-4.md:294`. Swept over 1900-01-01..2126-12-31, 82,910 days: the new rule rejects `1900-01-01 .. 1955-12-31`; the days it *newly* rejects - accepted by `abs(y - 2026) <= 100`, rejected by the asymmetric window - are `1926-01-01 .. 1955-12-31`. The sentence conflates the two and overstates the delta by twenty-six years. The neighbouring claims in the same paragraph are exact: "the oldest accepted stored day moves from 1926-01-01 to 1956-01-01" ✅, "it rejects nothing in the forward direction that the old rule accepted" ✅ (nothing is newly accepted either), and "the only pre-1956 fixtures in the tree are `DateEngineEdgeCaseTests.swift:52-54` (1896, 1900, 1904), which … never reach a scheduler or `implausibleStoredDays`" ✅ (the only other pre-1956 literal is `CalendarDayTests.swift:74`, a `daysIn(month:year:)` leap-year check, not a stored day). The error is in the conservative direction.

### 10 - P3. A pre-existing flake in `SyncActivationServiceTests`, surfaced once under load

**Evidence.** `SyncActivationServiceTests.swift:112-125`, `killSwitchBlocksEnable`, failed 1 of 24 runs at the reviewed head and 0 of 12 at `2d8913c` (full output in "What I ran"). Untouched by round 4. The suite is `.serialized` and its own comment at `:41-43` names the shared state: each use opens its own `UserDefaults` instance over a named suite, so `engageKillSwitch`'s write and `enableSync`'s read cross `cfprefsd` with no synchronisation. Not this stage's, not a regression, and not clean either - it is the second latent flake in twelve months of this branch's history and it would fail a CI job the same way.

## Explicit checks

- **Fabricated or unreproducible findings.** Two, both in the ledger's numbers rather than in its claims. Finding 1 (the K sweep's 63) and finding 2 (three of four falsification counts). Everything else reproduces: the sixteen-calendar offset table digit for digit, the four-anchor scheduler block field for field including all twelve fire days, the "13 corrupting / 12 caught / Ethiopic alone missed" split, the 1926→1956 boundary move, the pre-1956 fixture claim, and the sensitivity-versus-gap table - every cell of it, `13/13` down to `0/13`, including the `1/13` at K=1, gap=3. That last table is the load-bearing evidence for declining the `createdAt` cross-check, and it is exact.
- **Citations that do not say what they are claimed to say.** Two. Finding 4 (`StoredDayPlausibility.swift:59-62` and `PROD-READINESS-4.md:282` attribute a `PROD-READINESS-3.md` sentence to a doc comment) and finding 6 (`ImplausibleStoredDayTests.swift:106` cites an N4-2 that did not exist). Everything else I spot-checked is exact: `PROD-READINESS-3.md:242-246` really does say 3 / 7 / 15 / 64, `reviews-3/REVIEW-3.md:158` really does say 63, `reviews-3/REVIEW-4.md:5` really does say "the K sweep re-derives to the digit", `DateEngineEdgeCaseTests.swift:52-54` really are 1896 / 1900 / 1904. The `docs/next-wave.md` log-line example is accurate down to the formatting: subsystem `com.arthurzhang.otto` and category `scheduling` (`OttoLog.swift:23,31`), `CalendarDay.description` is `%04d-%02d-%02d` (`CalendarDay.swift:210`), and `OttoLog.list` sorts and joins with a space (`OttoLog.swift:82-84`), so `days=[2569-08-06 2569-08-20]` is what the device would print. The coverage-gap headline "N subscriptions couldn't be updated" matches `TodayView.swift:274`.
- **Severity inflation or deflation.** One deflation, now corrected by later work and outside my range: `PROD-READINESS-4.md:318` says only "Reminders are still scheduled and still on the wrong days (see N4-2)" while the pointer was dangling; N4-2 as eventually written carries it at P2, which I agree with - I measured four reminders on 2026-8-12/9-12/9-23/10-12 for a subscription the app now flags, and four on 2026-8-27/9-27/10-19/10-27 for an Ethiopic one it does not flag at all. The stage does not overstate what it closed: it says "HALF RESOLVED", it names Ethiopic as permanently unreachable, and both halves are true as measured.
- **Features smuggled past the no-features rule.** No. The diff is five files: one production file (two constants and a two-line predicate), two test files, `docs/next-wave.md` (explicitly permitted) and the ledger. No new screen, no navigation, no user-facing copy in the app, no `UserDefaults` key, no `Package.swift` or `project.yml` change. `plausibleStoredDayYears` is replaced by two constants of the same visibility rather than added to.
- **Any SwiftData schema change.** None. `git diff --name-only 6ef51ee..00cb0f1 -- Packages/OttoPersistence/ '*Schema*' '*Migration*'` is empty; nothing under `Packages/OttoPersistence/Sources/` is touched at all. The schema stays frozen at V3, and the item needs no schema - it reads three integers already on the value.
- **Prohibited actions.** None observed. `git show-ref` puts `refs/heads/main` and `refs/remotes/origin/main` both at `406a5a6`, so nothing was pushed or merged; `.git/FETCH_HEAD` does not exist; there are no tags; the branch reflog is fourteen plain `commit:` entries with no rebase, reset or amend, and `00cb0f1` is still an ancestor of the tip. `.github/workflows/` and `.swiftlint.yml` are untouched, so no rule was relaxed, disabled, re-thresholded or excluded - and lint is clean at `--strict` over 221 files, so nothing was made to pass by widening a rule. No prior record was edited: `git diff --name-only 6ef51ee..00cb0f1` over `PROD-READINESS.md`, `PROD-READINESS-2.md`, `PROD-READINESS-3.md`, `reviews/`, `reviews-2/`, `reviews-3/` and `reviews-4/` returns nothing. **No `OSLogStore` read was added** - the count stays at the baseline's nine, and this stage's new test reads no log.
- **Fixes that relocated a bug rather than removed it.** No, but the fix is narrower than "the corruption is detected", and the narrowing is structural rather than accidental. Detection is a function of the stored **year** only, so it catches a corrupt day exactly when the writing calendar's offset exceeds 70 years *in the past direction as of today*. A future date written on an Indian device is stored 78 years earlier and therefore looks *more* plausible, not less: a `pauseEndsOn` in 2034 stores as 1956, which is exactly on the boundary and escapes. The ledger discloses precisely this ("The single miss is a `pauseEndsOn` **eight** years out") and the mitigation it offers is real (such a subscription's anchor is caught anyway). Recorded here because it is a property of the approach that will drift: the same `pauseEndsOn` escapes for a widening set of dates every year that passes.
- **Error handling that hides errors.** None added. The predicate is total and returns `Bool`; nothing is caught, swallowed or defaulted anywhere in the diff. The path the change feeds - `failures.append` plus an `.error`-level log plus `continue` - is unchanged from round 3 and is the opposite of swallowing. The one thing worth naming, unchanged by this stage, is that skipping also suppresses `invalidateOutdatedUpcomingEvents` for that subscription, which the source states deliberately at `NotificationScheduler.swift:227-233`.
- **Verification that does not exercise the changed path.** No. Both new tests reach the changed line: the domain tests call `isPlausibleStoredDay` directly, and `indianAnchorWithdrawsTheCoverageClaim` drives the real `NotificationScheduler.reschedule` end to end over a real `Subscription`. Every mutation I applied failed at an assertion about the change, never at a setup step. The gap is the other direction - the *harm*, four reminders on the wrong days, is asserted by nothing; `scheduledCount == 4` pins that they are still scheduled but no test names the days. I confirmed the days by probe instead.
- **Tests that pass for the wrong reason.** One, and it is honest about it: `indianIsCaughtByTheAsymmetry`'s first assertion (finding 8) compares two literals. One more that passes for a thinner reason than it claims: the same test's twelve-iteration loop (finding 7). The `#expect(caught >= 10)` floor at `:109` was not raised when the catch count went from 11 to 12, so it is a walk-liveness check rather than a coverage assertion - defensible, and the real guard beside it (`missed == knownUncatchable`) is exact-equality and does bite, which M1 and M2 both demonstrate. Everything else fails when broken: I broke the rule four ways and the scheduler wiring once, and each time the tests that name the change failed.
- **Assertions that were changed - strengthening or weakening.** Four changes; three strengthenings and one disclosed relaxation.
  - `knownUncatchable: {"ethiopicAmeteMihret", "indian"}` → `{"ethiopicAmeteMihret"}` (`:51`). **Strengthening.** It is compared by exact equality against the measured `missed` set, so shrinking it demands strictly more of the rule. M1 and M2 both fail on it. This is the mechanism round 3 built working exactly as its own comment said it should.
  - `noThresholdCatchesTheTwo` → `noThresholdCatchesEthiopic` (`:120-130`). **Strengthening.** The removed assertion was `#expect(day(1948,5,15).isPlausibleStoredDay(...))` - an assertion that the defect persists - and its inverse now lives at `:147` plus a scheduler-level test. A second Ethiopic-range date (`2019-08-06`) was added.
  - `windowEdges` (`:184-199`). **Strengthening.** Three assertions become seven; both constants are pinned by name and their ordering asserted. M3 fails here.
  - `realDatesSurvive`: `day(1926, 8, 11)` → `day(1956, 8, 11)` (`:174`). **A relaxation of the accepted-input guarantee, permitted and disclosed.** The old expectation is precisely the width that let Indian through, so it "encoded the defect" in the sense the scope rule allows, and the strengthening is shown elsewhere. But it should be called what it is: the suite no longer guarantees that a century-old legitimate stored day survives, and a real stored day in 1926-1955 now silences that subscription's reminders and raises a coverage-gap card. I swept the tree and no fixture that reaches a scheduler carries such a date, and the argument that no field can sensibly carry one is sound. No test was skipped, disabled, or given `withKnownIssue`; the diff adds no `.disabled`, `.enabled(if:)` or `withKnownIssue` anywhere.
- **Flaky or environment-dependent tests.** One, pre-existing and not this stage's: finding 10. Nothing this stage added is environment-dependent - both new tests are pure value assertions or run against in-memory fakes, neither opens `OSLogStore`, and the calendar walk asks Foundation rather than asserting from a literal. `indianAnchorWithdrawsTheCoverageClaim` passed in all 24 head runs, both simulator runs, all three harness locales and every mutation run where it was not the subject.
- **Anything marked resolved without an artifact.** The terminal state is properly evidenced. "RESOLVED for Indian/Saka" is supported by the domain equality test, the scheduler test and my own probe; "DEFERRED for Ethiopic" is supported by the offset measurement and by my probe showing Ethiopic still schedules four wrong-day reminders with `canClaimCoverage=true`; "the `createdAt` cross-check is declined" is supported by the sensitivity table, which reproduces exactly. The one claim resting on no artifact is `docs/next-wave.md`'s "the repair is manual, **it works**" - finding 3.
- **Every commit in the range builds all three packages.** Yes - 9 of 9, table above.

## What I could not check, and why

- **That a user can actually perform the repair `docs/next-wave.md` describes.** I established the negative by reading every `DatePicker` site and every writer of the two fields - finding 3 - and by confirming the section-visibility conditions. I did not drive the app on the simulator and tap through it, so I cannot say what a person meets on screen, only what the code offers. This is the finding, and I did not close it either.
- **Whether `PROD-READINESS-3.md`'s 64 and my 64 share a wrong assumption.** Two independent scripts and one prior reviewer's independent script now agree on 64 under the stated parameters, and I printed the band and its per-day deltas so the disagreement with 63 is explained rather than asserted. What I cannot rule out is that all three of us share a modelling choice the original detector proposal did not intend - the proposal itself is not in the repository, so "the parameters the prior records state" is the best available definition of the question.
- **Release configuration.** Debug only. ASSUMPTION 3 carries, unchanged from every prior round.
- **A physical device**, and therefore whether either real user is on a non-Gregorian calendar. ASSUMPTION 1 carries; live exposure remains nil under it and no locale defaults to Ethiopic or Indian.
- **The `OSLogStore` readers on a CI runner.** Unchanged CANNOT ASSESS. This range adds no reader; the count stays at the baseline's nine, all of which passed in `verify.sh`, in both simulator runs and in all 24 flake runs, with no canary firing.
- **`aa92ca7`**, correctly routed to its own reviewer and its own range. Not in mine.
- **The other stages.** Stage 1's remediation (`b054506`), stages 3, 4 and 5 all landed after `00cb0f1` while I worked. I read only; nothing I did can have disturbed them, and I confirmed that none of the four files in my range has changed since `00cb0f1`, committed or uncommitted.
- **Whether the `SyncActivationServiceTests` flake reproduces under load deliberately.** It appeared once, in a batch that overlapped my own scripts, and did not recur in 12 clean runs at head or 12 at baseline. I did not try to force it, because a reviewer manufacturing load to make a pre-existing test fail proves nothing about the stage under review.

## A note on my own worktree hygiene

I created three detached worktrees under my own temp path and removed all three; `git worktree remove` succeeded for each and `git worktree prune` is clean.
`git worktree list` does **not** show only the main tree: seven worktrees remain that I did not create (`rev4/wt`, `rev4/wt2`, `rev4/wt3`, `rev5/wt-head`, `rev5/wt-mut`, `rev5/wt-sweep`, `wt-aa92ca7`, `wt-parent`, `wt-tip`), belonging to the concurrent reviewers of stages 4 and 5, of `aa92ca7`, and of the branch tip.
One of them was already present when I started. I left them alone: removing a worktree I did not create would delete another reviewer's in-flight mutation work, which is the failure round 3 recorded and the reason the rule exists.
I ran no command whose `--package-path` pointed at the main tree, so I contributed nothing to the `.build` contamination `PROD-READINESS-4.md:495-503` describes.
