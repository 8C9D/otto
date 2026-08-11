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
| 1 | **R0-7 / N2-2** | Calendar days already stored under a non-Gregorian device calendar are never repaired | **RESOLVED as detection for 11 of 13 / DEFERRED as repair** - stage 2; the V3 freeze is NOT lifted |
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

## ITEM 1 - R0-7 / N2-2, the days already stored under a non-Gregorian calendar

**RESOLVED as a detection for 11 of the 13 calendars that can cause it, DEFERRED as a repair.**
The V3 schema freeze is **not** lifted, and the reason is not caution: **`OttoSchemaV4` cannot supply the fact the repair needs.**
The harm F1 created on such a device - zero reminders behind a Today that claims full coverage - is closed for every calendar whose era offset is measured in centuries.
It is **not** closed for Ethiopic (+8 years) or Indian/Saka (-78), which `reviews-3/REVIEW-2.md` found and which no distance threshold can reach; that residual is stated in full under the remediation below and carried to NEXT ROUND.
The wrong dates are repaired in no case.

### Reconfirmed at HEAD by executing the defect

Not by reading `PROD-READINESS-2.md`'s trace.
A throwaway probe ran the **real** `NotificationScheduler.reschedule` over a subscription whose stored anchor is `2569-08-06` - what a pre-F1 build wrote on a Buddhist device for "6 Aug 2026" - with `today` at `2026-08-11`, beside an identically-shaped healthy control:

```
PROBE   scheduledCount=0  pending=0  ledgerFailures=0  canClaimCoverage=true  coveredThrough=2026-11-09  plan=0
CONTROL scheduledCount=4             ledgerFailures=0  canClaimCoverage=true  coveredThrough=2026-11-09
```

Round 2's trace is exact, and one detail of it is worse than the sentence conveys: the two outcomes are **identical on every field Today reads**.
`scheduledCount` is not on Today; `canClaimCoverage` and `coveredThrough` are, and they agree.
A device with no reminders at all is indistinguishable, at the surface, from one with four.

**This reproduces on a Gregorian host.**
The corruption lives in the stored *values*, not in the reading, so it needs no non-Gregorian harness - which is also why the guard added below runs on every CI machine, unlike F1's own.

### The schema decision, and why it is not a deferral

The prompt permits `OttoSchemaV4` on four conditions and requires this run to decide rather than inherit.
Decided: **no V4.**
The reason is a defect in the premise, not a failure of the conditions.

**A V4 marker records the calendar the device is set to at MIGRATION time, not the calendar that wrote the rows.**
The V3→V4 stage runs once, years after the data was written, and the only value it could put in a `writingCalendar` column is `Calendar.current.identifier` as read at that moment.
That is precisely the guess the prompt forbids, and it is worse than a coin flip in both directions:

- a user who switched **Buddhist → Gregorian before updating** gets a marker saying "gregorian", no repair runs, and the data stays wrong;
- a user who switched **Gregorian → Buddhist before updating** gets a marker saying "buddhist", the repair runs, and **correct billing dates are shifted 543 years into the past.**

There is no way to tell those two devices apart, and the second outcome destroys data that was right.
So the column adds cost and no information: **`Calendar.current` is already readable at repair time without a schema change**, and a column that can only be filled from it tells a future reader nothing the future reader could not have read directly.

The evidence that *does* exist is already in V3.
Every record carries the §5.0 audit quartet, and `createdAt` is a `Date` - an absolute instant no calendar corrupts.
A row created at a true instant in 2026 whose `expectedDate` is 2569 is detectably inconsistent **with its own record**, and that is inference from stored evidence rather than a guess about the device.
It is also not enough to *repair* with: identifying which calendar produced a given `(y, m, d)` is only a year offset for Buddhist, Minguo and Persian, while Islamic months and days are not Gregorian ones shifted at all and Japanese year 8 is ambiguous across five eras (Meiji 8, Taisho 8, Showa 8, Heisei 8, Reiwa 8) - though `createdAt` disambiguates those instantly, which is a correction recorded below.
**The schema was never the limitation.** The limitation is that the writing calendar was not recorded and cannot be recovered, and V4 does not change that.

**Against the four conditions, one by one:**

1. **Item 2 lands first - MET.** Stage 1, `87d6508` + `7d531de`. It is a real gate: it now catches a missing stage, a mis-wired stage, and (after the reviewer's finding) a version identifier that was copied and never bumped.
2. **The migration proved on data written by the old schema - not attempted, and it is not what fails.** The mechanics are provable here; `WatermarkRelocationMigrationTests` already builds a V2 store on disk, closes it and reopens it at V3, so the harness exists and `reviews/REVIEW-0.md` §4's concern about verifying from the writing context is answerable. What cannot be proved is the migration's **input**, because the input is a guess.
3. **Idempotent and reversible in effect - satisfiable, and irrelevant.** A one-shot marker in the device-state store would give idempotence with no schema change at all, since that store is local-only and explicitly outside the versioned chain (`OttoDeviceStateSchema.swift:11-15`). A Gregorian device is untouched by construction. Neither answers condition 2's problem.
4. **Condition 4 therefore applies**, on its own stated grounds: *"shipping an unverifiable migration on the store that holds the money is worse than both."*
   The failure mode is not "the repair does nothing"; it is "the repair silently rewrites correct billing dates", on a device nobody can inspect, with no way to tell which case you are in.

### What changed instead

Two additions, no schema, no data mutation, no new screen or setting.

- **`CalendarDay.isPlausibleStoredDay(asOf:)`** and **`Subscription.implausibleStoredDays(asOf:)`** in `OttoDomain` (`StoredDayPlausibility.swift`).
  A stored day more than **100 years** from today cannot be a date Otto schedules against.
  Every calendar Foundation offers is centuries away from the Gregorian numbering `CalendarDay` is built on - Buddhist +543, Hebrew +3760, Islamic −578, Minguo −1911, Japanese Reiwa −2018, Persian −621 - and the nearest miss is five times outside the window.
  It makes **no claim about which calendar wrote the day and performs no conversion**; both would be guesses.
- **`NotificationScheduler.reconcileLedger`** reports such a subscription as a ledger failure, logs which days, and skips it.
  `ledgerFailures` already drives `canClaimCoverage`, which already drives round 2's `CoverageGapCard`, so the silent state becomes a visible one through machinery that exists.

The fields checked are exactly the ones the planner and the materializer read as days to schedule against: the stored anchor, the trial's entered start and derived conversion date, a pause's scheduled resume, and the last recorded use.
The anchor is read directly rather than through `billingAnchor(asOf:)`, because that derivation compares the conversion date against `today` - the comparison the corruption breaks.

### Predicted observable difference, then measured

Predicted before the change: the corrupt device keeps `scheduledCount=0` (nothing is repaired) but gains `ledgerFailures=[id]` and `canClaimCoverage=false`; the healthy device is bit-for-bit unchanged; every existing test is unchanged because no fixture in the repository is more than a century from its own `today`.

Measured: all three hold.
Every fixture year in `Packages/*/Tests` is 1896-2028, and the three pre-1900 ones are date-engine arithmetic tests that never reach a scheduler.
Host suites went 258 / 119 / **201** with no pre-existing test touched - `verify.sh` totals **578** after the remediation below added two more domain tests (256 / 576 before it), not the 575 an earlier draft's figures implied, because the fifth OttoUI test lands in the pre-existing `SchedulingLogTests` rather than the new file this section is about.

### Falsified, four ways, at the call site each time

| what was broken | result |
|---|---|
| the **wiring** in `reconcileLedger` deleted, helper untouched | **6 issues across 4 tests** on the whole suite: `ImplausibleStoredDayTests:45,46,84,111,112` and `SchedulingLogTests:119`. An earlier draft said 5 across 3 - it was measured with `--filter` on one file and omitted the log test, which the fourth row shows is load-bearing |
| `isPlausibleStoredDay` forced to `true` | **12 issues in OttoDomain** plus 6 in OttoUI. An earlier draft said 5, again a filtered run |
| the field list cut back to `cycleStartDay` alone | 3 issues - the trial, the pause resume and the last-used cases |
| **only** the log statement deleted, failure reporting kept | `lines.last { $0.contains("reason=implausibleStoredDays") && … } → nil` - at the target-line `#require`, not at the canary |

The healthy-device test passes under every one of them, which is what makes it a control rather than a fourth copy of the same assertion.

### Two things this stage got wrong and found by falsifying

- **A test that passed for the wrong reason, caught before it shipped.**
  The fourth test first asserted that a corrupt subscription leaves no ledger rows and no watermark afterwards.
  Both are true **with the fix reverted**: a 2569 anchor produces no charges in a 2026 window either way, and `FakeBillingEventRepository.materializeEvents` never advances a watermark at all.
  It asserted nothing about the change.
  It now asserts the **call** - `materializeCalls == [healthy.id]` - which is what the fix actually alters, and it fails when the wiring is removed.
- **An invalid falsification, recorded rather than hidden.**
  The first attempt at falsification 1 located the end of the block with `s.index("                continue\n            }\n")` and no start offset, so it matched an earlier `continue` in the file and cut the wrong region; the suite stayed green and the falsification looked like a failure of the test.
  Re-done with the search anchored to the block, and the removal printed and the symbol count checked (`grep -c` → 0) before the run.
  This is round 2's own "patched the first of two identical lines" defect, in a different tool.

### Remediation after `reviews-3/REVIEW-2.md`

The verdict is PASS-WITH-FINDINGS over nine findings.
One is P1 and is a defect in this stage's own change; it is fixed here.

- **Finding 1 (P1) - the threshold's justification was a false universal, and the test written to guarantee it could not fail.**
  The doc comment, this ledger and the guarding test all said *every* calendar Foundation offers is centuries from Gregorian, and all three used the **same six offsets**: the test was the claim's own premise asserted back at itself.
  Re-derived independently rather than taken on the reviewer's word - asking each of the 16 identifiers this SDK declares what it writes for Gregorian 2026-08-06:

  ```
  buddhist  2569-8-6 (543)   chinese 43-6-24 (1983)   coptic 1742-11-30 (284)
  hebrew    5786-12-23 (3760) islamic{,Civil,Tabular,UmmAlQura} 1448-2-2x (578)
  japanese  8-8-6 (2018)     persian 1405-5-15 (621)  republicOfChina 115-8-6 (1911)
  ethiopicAmeteMihret 2018-11-30 (8)   <- NOT caught, and representable
  indian              1948-5-15  (78)  <- NOT caught, and representable
  gregorian / iso8601 / ethiopicAmeteAlem  write the Gregorian numbers, so no corruption arises
  ```

  The reviewer drove both misses through the real scheduler: they schedule **four reminders on the wrong days** with `canClaimCoverage=true`, and the wrong anchor is not visible on the list either, because what the list renders is the derived next-charge date. That is worse than the Buddhist state this stage set out to close, not merely uncovered by it.

  **Fixed three ways.** The doc comment now states the true coverage and names both misses. The test now **asks Foundation** - it derives each stored triple from the calendar rather than reciting an offset - and pins the uncatchable set as a positive assertion, so a future change that catches one of them fails the test and forces the record to be updated. A second test pins *why* they are uncatchable.

  **The reviewer's proposed alternative was measured and is not an improvement.**
  It suggests keying detection off `createdAt` - real evidence, and its 13/13 sensitivity is right. Its specificity was tested against six hand-picked legitimate fixtures and came back clean. Scanned systematically instead, over every ordinary Gregorian anchor in the 11 years before a 2026-08-06 creation:

  ```
  2018-11-30  FLAGGED by ethiopicAmeteMihret     <- "I've had this since Nov 2018"
  2018-12-01  FLAGGED       2018-11-29  FLAGGED
  2019-03-01  clean   2020-06-15 clean   1970-01-01 clean   2099-12-31 clean
  scanned 4001 ordinary anchors; 64 would be FLAGGED as corrupt
  ```

  **1.6% false positives on ordinary data**, in a ~64-day band, because Ethiopic 2018-11-30 *is* Gregorian 2026-08-06 - the collision is exact, not approximate.
  A false positive here silences reminders for a **working** subscription, which is a worse harm than the false negative it removes, and it lands on a shape as ordinary as "held since late 2018".
  So the rule is not adopted. The measurement goes to NEXT ROUND with the design, so whoever picks it up starts from the constraint rather than from six clean fixtures.

- **Finding 2 (P2) - three of the four baseline measurements were absent from this section**, and the one number that moved (simulator 108 → 113) was the one nobody wrote down. All four are now recorded under "Baseline at the end of this stage" below. The narrative was organised around predict-then-measure-the-change, which is a stronger discipline than a baseline re-run and displaced it.
- **Finding 3 (P3)** - the host total was 200, measured 201; the run's cumulative total is 576. Corrected above.
- **Finding 4 (P3)** - the cost figure attributed host noise to the change. Corrected above with the reviewer's controlled A/B; the real delta is ~+1 s.
- **Finding 5 (P3)** - two falsification rows were measured with `--filter` and reported as whole-suite numbers. Corrected above; both err in the safe direction, the guard being stronger than the table said.
- **Finding 6 (P3) - `deduplicated and in day order` was a documented contract with no test.** Removing the `Set` and the `.sorted()` left the suite green. Now guarded, and the falsification produces `[2569-08-06, 2569-08-06, 2569-08-20, 2569-08-06]` against the expected two-element result.
- **Finding 7 (P3) - "exactly the fields the materializer reads" was not exact.** It omits the §5.3 watermark, which left the versioned schema in Wave 6A and is not on `Subscription` at all. The reviewer tried to make it bite and could not: a corrupt watermark widens the window without changing the sequence, because charges generate from the anchor rather than the window start. So the wording was wrong and the code was not; the doc comment now says which and why.
- **Finding 8 (P3) - skipping also suppresses `invalidateOutdatedUpcomingEvents`,** so era-numbered `.upcoming` rows already written are retained rather than tombstoned. Deliberate on reflection and now stated in the code: this stage prefers visible wrongness to a tidy lie, and the rows clear on the next pass once the dates are repaired. It was not disclosed before, and the stage's own test asserted it without anyone noticing.
- **Finding 9 (P3) - two supporting claims in the schema decision were wrong.** "Three eras" is five, and `createdAt` disambiguates all five - corrected above. "The schema was never the limitation" is true of repair and also true of detection, which is the sense in which finding 1 bites. The decision's load-bearing step - that a marker can only record `Calendar.current` at migration time - was attacked by the reviewer and survives; the Islamic variants disagree by up to two days on the same instant, which alone makes a repaired date a guess.

**One thing this stage does that it never claimed, credited because it cuts the other way.**
For a **negative**-offset calendar the pre-stage behaviour was not "nothing is scheduled" - it was a materialization pass over a window centuries wide. With an unrepaired Japanese anchor and watermark at year 8 against a 2026 horizon, `expectedCharges` yields **24,220** rows for one subscription on one pass, against 3 for a healthy one. The new guard skips before `materializeEvents` is reached, so this stage prevents it. Only the Buddhist case was ever measured here, where `min(2569-08-06, today)` collapses the window to nothing - so the worse half of the defect was never seen by the person fixing it.

### Baseline at the end of this stage - all four, measured

| measurement | `reviews-3/BASELINE-3.md` | at this stage | verdict |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 251 / 118 / 196 = 565 | exit 0, 258 / 119 / 201 = **578** | +13, exactly this run's new tests |
| `swiftlint --strict` | clean | clean | unchanged |
| simulator suite | 108 / 70 / 31, 7 known issues | **113** / 70 / 31, 7 known issues | +5, this stage's OttoUI tests |
| non-Gregorian harness | 1 / 1 / 5 | 1 / 1 / 5, same five citations | unchanged |

The simulator's 108 → 113 is the first time that number has moved in this run, and it is recorded here rather than left for a later stage to discover against a stale baseline.
The new tests also pass under all three non-Gregorian locales, including `ar_SA`: `CalendarDay.description` is `String(format:)` with no locale, so it does not render Arabic-Indic digits and the host-independence claim holds where it was most likely not to.

### What a non-Gregorian user's actual position is at the end of this run

Stated concretely, because declining V4 obliges it.

**On a fresh install, any calendar: correct.** F1 is right, nothing is stored wrong, and this stage is a no-op.

**On a device that already holds pre-F1 data:**

1. Reminders for every affected subscription are **still not scheduled**. This run does not repair that and does not claim to.
2. Today no longer says they are. `canClaimCoverage` is false, so round 2's coverage-gap card appears - *"N subscriptions couldn't be updated / Otto couldn't refresh their reminders on its last check, so some may be missing. Nothing was deleted, and it will try again."*
3. The subscription list and detail screens show the wrong dates **in plain sight** - "Aug 6, 2569" - because F1 made the display resolve the stored numbers honestly rather than cancelling the error out.
4. **The repair is manual, and it works.** Re-pick the next-charge date on each affected subscription (and the trial start, pause resume, or last-used date the log names). With F1 in place the DatePicker now writes Gregorian, so a re-picked date is stored correctly and the subscription starts scheduling on the next pass. The log line names exactly which days to fix.
5. `docs/next-wave.md` and the app carry no instruction saying so. Writing one is a documentation change to a narrative document this run is forbidden to edit, so it goes to NEXT ROUND.

**Should F1 be gated off for them? No.**
Gating it off means resuming era-numbered writes into billing data - the defect F1 exists to stop - and it would restore delivery only by making the two errors cancel again, which is a working system built on two compensating faults.
It is also not implementable where the seam is: `CalendarDay.conversionCalendar` is a static computed property in the domain with no access to the store, so "gate it off if this device holds corrupt data" would mean global mutable state under every date conversion in the app.
The card plus the visible wrong dates plus a manual repair is a worse experience and an honest one; the gate is a better experience and a lie.

### What this does NOT do

- **It does not repair anything.** The days stay wrong until a human fixes them.
- **The card's wording is imprecise for this case.** "It will try again" is true and will not succeed. Re-wording it means new user-facing copy, which is outside this run's scope - round 2 needed an explicit exception to add that card at all. NEXT ROUND.
- **It only covers the scheduling pass.** `SubscriptionFlowService` and the import path can still act on a corrupt day; they are not where the silent-coverage harm is, and widening the check to them is a blast radius this stage did not measure.
- **The threshold is a judgment.** 100 years is five times the nearest era offset and forty years beyond the oldest plausible billing anchor, but it is a constant chosen here, not derived from a spec.

### Cost, measured

**An earlier draft claimed "~12 s to 21-41 s" and that number is wrong.**
It was two consecutive runs of a bimodal measurement read as a range, with every second of an unrelated slow log read booked to the new test.
`reviews-3/REVIEW-2.md` finding 4 ran the controlled A/B this needed - alternating a worktree at `ddb04bb` (pre-change, 196 tests) with HEAD (201 tests), four runs back to back:

```
PRE-CHANGE (ddb04bb) run 1   196 tests passed after 13.366 seconds
HEAD (e4f4872)       run 1   201 tests passed after 12.863 seconds
PRE-CHANGE (ddb04bb) run 2   196 tests passed after 11.928 seconds
HEAD (e4f4872)       run 2   201 tests passed after 14.802 seconds
```

**The delta attributable to this change is about +1 s**, not +9 to +29 s.

What is real, and worse than a fixed cost: the same 201-test suite measured **11.9 s and 91.4 s on this host in one session**, an 8x spread with no code change, because the `OSLogStore` tests run in parallel and all block on the same log daemon - the suite's wall time simply *is* that read, whatever it costs that minute.
This stage adds a **fifth** such test, so it adds one more waiter on an unbounded read, on CI runners this run cannot exercise.
That sharpens the CANNOT ASSESS entry rather than softening it.
Taken anyway, and disclosed rather than buried: the alternative is a new log line with no executable guard, which is round 2's own R5-2 shipped again in the run whose item 7 is the same defect class.

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
