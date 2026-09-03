# REVIEW-2 — stage 2, range 87d6508..e4f4872

verdict: PASS-WITH-FINDINGS

The code in this range is additive, well-falsified and honest about its own limits, and the baseline is intact on all four measurements — I ran all four rather than reasoning about them.
Three of the ledger's four falsification rows reproduce; the fourth reproduces and is stronger than reported.
The stage also prevents a failure it never measured and does not claim (finding 9's note).

One finding is load-bearing against the ledger's argument rather than against its code.
The threshold this stage introduces is justified — in the ledger and in the shipped source — by a universal claim about Foundation's calendars that is false in two instances, and the test written to guarantee that universal enumerates a hand-picked list rather than Foundation's set, so it cannot fail on either.
I reproduced the resulting miss end to end against the real scheduler.
It does not invalidate the stage: the demonstrated defect (Buddhist) is genuinely closed, the V3 freeze holds, and nothing prohibited happened.

## What I ran

**Scope of the range.**

```
$ git log --oneline 87d6508..e4f4872
e4f4872 Refuse to claim coverage over a stored day no calendar could have meant
ddb04bb Add the adversarial review of stage 1
7d531de Assert the schema versions strictly increase, and read the stages by pattern match

$ git diff --name-status 87d6508..e4f4872
M	PROD-READINESS-3.md
A	Packages/OttoDomain/Sources/OttoDomain/Models/StoredDayPlausibility.swift
A	Packages/OttoDomain/Tests/OttoDomainTests/StoredDayPlausibilityTests.swift
M	Packages/OttoPersistence/Tests/OttoPersistenceTests/CloudKitCompatibilityTests.swift
M	Packages/OttoUI/Sources/OttoServices/NotificationScheduler.swift
A	Packages/OttoUI/Tests/OttoServicesTests/ImplausibleStoredDayTests.swift
M	Packages/OttoUI/Tests/OttoServicesTests/SchedulingLogTests.swift
A	reviews-3/REVIEW-1.md
```

No schema file, no `.swiftlint.yml`, no `.github/workflows/`, no narrative document.
The only production change is **+22 lines, 0 deletions** in `NotificationScheduler.swift`.
All 23 deletions under `Packages/` are in `CloudKitCompatibilityTests.swift` — the `Mirror`-to-`switch` replacement that closes REVIEW-1's finding 2.

**Baseline, all four measurements, measured at HEAD.**

```
$ ./scripts/verify.sh            # exit 0
== VERIFIED: e4f48727e483e881dcc5a36b34f6639542d174aa builds, tests, and lints from a clean clone
   OttoDomain: 256
   OttoPersistence: 119
   OttoUI: 201
   total: 576 tests

$ swiftlint --strict --quiet     # exit 0, SwiftLint 0.65.0, no output

$ cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"   # exit 0
✔ Test run with 113 tests in 21 suites passed after 3.597 seconds.
✔ Test run with 70 tests in 12 suites passed after 0.076 seconds.
✘ Test run with 31 tests in 6 suites passed after 3.175 seconds with 7 known issues.
** TEST SUCCEEDED **

non-Gregorian harness (the command in CalendarEraTests.swift:15-20):
  th_TH@calendar=buddhist          201 tests, 1 issue   DisplayFormattingTests.swift:49
  ja_JP@calendar=japanese          201 tests, 1 issue   DisplayFormattingTests.swift:49
  ar_SA@calendar=islamic-umalqura  201 tests, 5 issues  DisplayFormattingTests.swift:49,59,68,69
                                                        NotificationReconciliationTests.swift:170
```

**No regression.**
565 → 576 host tests is exactly the eleven tests this run added (1 in stage 1, 10 in stage 2) and nothing else.
The simulator's first bucket moved 108 → 113, which is the five new OttoUI tests; 70 / 31 and the 7 known issues are unchanged, and the seven are still the `EmptyStateTests` accessibility labels.
Non-Gregorian is 1 / 1 / 5 at the same five file:line citations `BASELINE-3.md:143-171` records — including under `ar_SA`, where the numbering system is Arabic-Indic and the new log test's `line.contains("2569-08-06")` assertions still pass, so the host-independence claim in `StoredDayPlausibilityTests.swift:14-16` holds where it is most likely not to.

**Every commit in the range builds.**
Detached worktrees under a scratch path I created:

```
7d531de  OttoDomain Build complete! (438.33s)  OttoPersistence (67.22s)  OttoUI (26.03s)
ddb04bb  OttoDomain Build complete! (28.18s)   OttoPersistence (44.96s)  OttoUI (32.79s)
e4f4872  covered by verify.sh, which clones the committed HEAD and also builds the app target
```

Worktrees removed; `git worktree list` shows only the repository.

**Mutation testing.** All mutations applied in a detached worktree at `e4f4872`, never in the main tree, so the main tree's `git status --porcelain` was empty throughout and is empty now.

| mutation | measured result |
|---|---|
| the `if !implausible.isEmpty { … continue }` block deleted, helper untouched (589 chars removed, symbol count verified 0) | **6 issues across 4 tests** — `ImplausibleStoredDayTests:45,46,84,111,112` and `SchedulingLogTests:119` |
| `isPlausibleStoredDay` forced to `true` | **12 issues** in OttoDomain (all 5 new tests bar the healthy control), **6** in OttoUI |
| field list cut back to `cycleStartDay` alone | **3 issues** — the trial, the pause resume, the last-used cases. Reproduces the ledger's row 3 exactly |
| only the log statement deleted, failure reporting kept | **exactly 1 issue**, at `SchedulingLogTests.swift:119:24` — the target-line `#require`, not the canary. Reproduces row 4 exactly |
| `plausibleStoredDayYears` 100 → 200 | 3 issues in `windowEdges`. The constant is pinned on both edges and by name |
| `continue` removed, failure still reported (materialize from the corrupt anchor anyway) | 2 issues at `ImplausibleStoredDayTests:111,112`. Confirms the ledger's own "assert the call, not the result" correction is load-bearing |
| the `Set` dedup and `.sorted()` removed | **suite stays green** (finding 6) |

**Probes** (created by me, run, deleted; all in the worktree).
A Foundation-calendar enumeration against the shipped `isPlausibleStoredDay`; the real `NotificationScheduler.reschedule` over Saka- and Ethiopic-written anchors; `expectedCharges` over an era-numbered materialization window; and a standalone comparison of the shipped rule against a `createdAt`-keyed one.

**Citations opened** (check 2): `PROD-READINESS-3.md:141` → `OttoDeviceStateSchema.swift:11-15` is exactly the "NOT part of `OttoMigrationPlan` … never gains a CloudKit configuration" paragraph ✅; `:199`'s quoted card copy is verbatim `TodayView.swift:274` and `:281-282` ✅; `:132` "`createdAt` is a `Date`" → `Subscription.swift:82` ✅; `:206` "`CalendarDay.conversionCalendar` is a static computed property in the domain" → `CalendarDay.swift:169-173` ✅; `:182` "`FakeBillingEventRepository.materializeEvents` never advances a watermark" → the only `watermarks[…] =` writes are at `:24,34,40`, and `materializeEvents` only reads at `:79` ✅; `:186`'s self-reported invalid falsification is real — there is an earlier bare `continue` at `NotificationScheduler.swift:168` before the new one at `:235`, so an unanchored search would indeed have cut `caughtUpCancellationEpisodes` ✅.

## Findings

### 1. The 100-year window misses two of Foundation's calendars, and the universal that justifies it is asserted in the ledger, in the shipped source, and in the test that is supposed to guarantee it

- severity: **P1**
- evidence:

  `StoredDayPlausibility.swift:30-35` states the justification as a universal:

  > Every calendar Foundation offers numbers its years with an offset of hundreds of years from the Gregorian ones `CalendarDay` is built on … A century separates every one of them from any billing date a subscription can plausibly carry, and the nearest miss (Islamic, 578 years) is still five times outside it.

  `PROD-READINESS-3.md:151` repeats it, and `:214` builds the threshold's defence on it ("100 years is five times the nearest era offset").

  Measured against Foundation rather than against the list. A probe that does exactly what a pre-F1 build did — ask each calendar for the year/month/day of one instant, then store those three integers — run against the **shipped** `isPlausibleStoredDay(asOf:)`:

  ```
  PROBE buddhist:            stored 2569-08-06  |dYear|=543   isPlausibleStoredDay=false
  PROBE chinese:             stored 0043-06-24  |dYear|=1983  isPlausibleStoredDay=false
  PROBE coptic:              stored 1742-11-30  |dYear|=284   isPlausibleStoredDay=false
  PROBE ethiopicAmeteMihret: stored 2018-11-30  |dYear|=8     isPlausibleStoredDay=true   <──
  PROBE hebrew:              stored 5786-12-23  |dYear|=3760  isPlausibleStoredDay=false
  PROBE indian:              stored 1948-05-15  |dYear|=78    isPlausibleStoredDay=true   <──
  PROBE islamic:             stored 1448-02-23  |dYear|=578   isPlausibleStoredDay=false
  PROBE islamicCivil:        stored 1448-02-21  |dYear|=578   isPlausibleStoredDay=false
  PROBE islamicTabular:      stored 1448-02-22  |dYear|=578   isPlausibleStoredDay=false
  PROBE islamicUmalqura:     stored 1448-02-23  |dYear|=578   isPlausibleStoredDay=false
  PROBE japanese:            stored 0008-08-06  |dYear|=2018  isPlausibleStoredDay=false
  PROBE persian:             stored 1405-05-15  |dYear|=621   isPlausibleStoredDay=false
  PROBE republicOfChina:     stored 0115-08-06  |dYear|=1911  isPlausibleStoredDay=false
  ```

  The nearest miss is **Ethiopic at 8 years**, not Islamic at 578, and Indian (Saka) at 78 is also inside.
  Both produce a fully representable `CalendarDay` (month 11 day 30 and month 5 day 15 are both valid under `CalendarDay.init?`).

  The same pass, through the real `NotificationScheduler.reschedule`, seeded with what each device would have written for Gregorian 2026-08-06 and asked for 2026-08-11:

  ```
  PROBE BUDDHIST (control): anchor 2569-08-06
    implausibleStoredDays=[2569-08-06]  ledgerFailures=1  canClaimCoverage=false  scheduled=0
  PROBE INDIAN/SAKA:        anchor 1948-05-15
    implausibleStoredDays=[]            ledgerFailures=0  canClaimCoverage=true   scheduled=4
    pending = [ …|2026-08-12|renewal, …|2026-09-12|renewal, …|2026-10-12|renewal, …|2026-09-23|usageCheckIn ]
  PROBE ETHIOPIC:           anchor 2018-11-30
    implausibleStoredDays=[]            ledgerFailures=0  canClaimCoverage=true   scheduled=4
    pending = [ …|2026-08-27|renewal, …|2026-09-27|renewal, …|2026-10-27|renewal, …|2026-10-19|usageCheckIn ]
  PROBE HEALTHY (control):  anchor 2026-08-06
    implausibleStoredDays=[]            ledgerFailures=0  canClaimCoverage=true   scheduled=4
    pending = [ …|2026-09-03|renewal, …|2026-10-03|renewal, …|2026-11-03|renewal, … ]
  ```

  This is worse than the state the stage exists to remove, not merely uncovered by it.
  The Buddhist device gets zero reminders and now says so.
  The Saka device gets four reminders **on the wrong days** — warned about a charge on the 15th while the vendor charges on the 6th — with `canClaimCoverage=true`, so Today claims full coverage, and the wrong anchor is not visible on the list either, because what the list renders is the derived next-charge date (`2026-08-15`), which looks entirely ordinary.
  The ledger's `:200` consolation — "the subscription list and detail screens show the wrong dates in plain sight" — does not hold for these two.

  **The guarding test cannot fail on this.**
  `StoredDayPlausibilityTests.swift:32` is titled "every calendar's era offset lands outside the plausible window", but `:23-30` is a six-entry literal (`Buddhist, Hebrew, Islamic, Minguo, Japanese, Persian`) — the same list as the doc comment.
  It enumerates the claim's supporting examples, not Foundation's calendar set, so it asserts the six and is silent on the ten it omits, two of which are the ones that fail.
  This is the "test that passes for the wrong reason" class in its most self-sealing form: the test, the source comment and the ledger all cite one another and none of the three consults Foundation.

  **This is not fixable by tuning the constant, and a correct alternative exists.**
  Ethiopic is 8 years off; no year-distance window that admits the ledger's own `day(1970, 1, 1)` fixture (`:54`, 56 years) can also reject 8.
  The alternative is the evidence the ledger itself identifies at `:132-133` — "`createdAt` is a `Date` — an absolute instant no calendar corrupts" — and then never uses, because `:134` rejects it for being insufficient to **repair** with. That objection is correct and irrelevant: the shipped change is a detector, and detection only needs to know *that* a day is wrong. Reading the stored triple back under each Foundation calendar and asking whether any lands near the record's own `createdAt`, measured:

  ```
  SENSITIVITY (what each calendar stored for Gregorian 2026-08-06, createdAt = that instant, K = 31 days)
    ethiopicAmeteMihret  yearWindowRule=MISSED  createdAtRule=CAUGHT
    indian               yearWindowRule=MISSED  createdAtRule=CAUGHT
    (the other 11 calendars: CAUGHT by both)
  SPECIFICITY (legitimate Gregorian anchors on a record created 2026-08-06)
    1970-01-01 (the ledger's long-past import)  clean
    2019-03-01 (a 7-year-old subscription)      clean
    2099-12-31 (the ledger's prepaid term)      clean
    1926-08-11 / 2126-08-11 (its window edges)  clean
  ```

  13 of 13 caught, 0 of 6 false positives, no schema change, V3 data only.
  I tested this on the anchor only, with K = 31 days; a field that need not sit near `createdAt` (`lastUsedDate`, a far-future `pauseEndsOn`) would need its own window, and I did not characterise that. I am not claiming a finished design — I am claiming the ledger closed off this line by answering a question about repair that detection had not asked.

  **What this does not undermine.** No locale *defaults* to either calendar (I scanned `Locale.availableIdentifiers`: zero hits), so reaching them needs an explicit `@calendar=` keyword — which is what the run's own harness uses (`-AppleLocale th_TH@calendar=buddhist`) and what iOS's Settings calendar picker emits, but whether that picker offers Indian or Ethiopic I cannot determine from this host. Combined with ASSUMPTION 1 (both real users Gregorian), live exposure is nil today. The false universal, though, is proven regardless of who can reach it, and `:214`'s "What this does NOT do" names the threshold as a judgment without naming this as its shape.

- why the builder missed it: the offsets were assembled once, as an argument for a number, and then re-used three times — as the doc comment's justification, as the ledger's justification, and as the test's fixture table. Once the same six values are the premise, the evidence and the assertion, no amount of falsifying *around* them can reach them: every mutation the ledger ran varied the threshold, the wiring or the field list, and each of those is downstream of the list. The one question that would have found it — "ask Foundation for its calendars rather than listing them" — is the only one the design never poses, and it is the same shape as REVIEW-1's finding 1, where every mutation varied `stages` and none varied a `versionIdentifier`.

### 2. Three of the four baseline measurements are absent from the stage's record, and the one number that moved is the one nobody wrote down

- severity: **P2**
- evidence: `BASELINE-3.md:17` fixes the standard — "Every later 'nothing worse than baseline' claim in this run is measured against: 565 host tests, lint clean under `--strict`, simulator 108 / 70 / 31 with 7 known issues, non-Gregorian 1 / 1 / 5."
  `PROD-READINESS-3.md`'s ITEM 1 reports one of those four: "Host suites went 256 / 119 / 200" (`:165`). There is no `swiftlint`, no simulator and no non-Gregorian result anywhere in the section, and no `verify.sh` run recorded.

  This matters here rather than as bookkeeping because the simulator number **changed in this stage** — 108 → 113, the five new OttoUI tests — and that is the first time in the run it has moved. A later stage comparing against `BASELINE-3.md:14`'s 108 has no record saying why it is now 113, and an unrecorded move in the one suite the host `swift test` totals cannot see is precisely where a regression would sit unnoticed. Stage 1's reviewer measured all four and said so (`REVIEW-1.md:34-65`); stage 2's ledger did not.

  I ran all four. They hold: `verify.sh` exit 0 at 256 / 119 / 201 = 576, `swiftlint --strict` clean, simulator 113 / 70 / 31 with the same 7 known issues and `** TEST SUCCEEDED **`, non-Gregorian 1 / 1 / 5 at the same five citations.
- why the builder missed it: the stage's own narrative is organised around *prediction then measurement of the change* ("Predicted observable difference, then measured"), which is a stronger discipline than a baseline re-run and displaced it. The prediction was about the host suites, so the host suites were the thing measured.

### 3. The ledger's measured host-suite total is wrong by one

- severity: **P3**
- evidence: `PROD-READINESS-3.md:165` reads "Host suites went 256 / 119 / **200**".
  The stage adds 5 domain tests, 4 in `ImplausibleStoredDayTests` and 1 in `SchedulingLogTests`; 196 + 5 = 201. Measured twice, independently:

  ```
  $ swift test --package-path Packages/OttoUI
  ✔ Test run with 201 tests in 37 suites passed after 12.863 seconds.

  $ ./scripts/verify.sh
     OttoUI: 201
     total: 576 tests
  ```

  So the run's cumulative total is 576, not the 575 the ledger's figures imply.
- why the builder missed it: the five new tests land in two files in two different suites, and the four-test file is the one the section is about; the single test added to the pre-existing `SchedulingLogTests` is discussed a paragraph later, under Cost, where it is described as a time expense rather than as a count.

### 4. The cost figure is not reproducible and attributes host noise to the change

- severity: **P3**
- evidence: `PROD-READINESS-3.md:218` claims "The OttoUI suite goes from **~12 s to 21-41 s** (two consecutive full runs: 40.8 s and 21.0 s)."

  Controlled A/B on this host, alternating between a worktree at `ddb04bb` (pre-change, 196 tests) and the working tree at `e4f4872` (201 tests), four runs back to back:

  ```
  ### PRE-CHANGE (ddb04bb) run 1   ✔ 196 tests passed after 13.366 seconds.
  ### HEAD (e4f4872)     run 1     ✔ 201 tests passed after 12.863 seconds.
  ### PRE-CHANGE (ddb04bb) run 2   ✔ 196 tests passed after 11.928 seconds.
  ### HEAD (e4f4872)     run 2     ✔ 201 tests passed after 14.802 seconds.
  ```

  The delta attributable to the change is about **+1 s**, not +9 to +29 s.
  Separately, my first HEAD run of the day measured **91.427 s** for the same 201 tests, with the four pre-existing `OSLogStore` tests reporting 90.9 / 91.2 / 91.4 s each — they are parallel and all block on the same log daemon, so the suite's wall time is that read, whatever it happens to cost. On one host in one session the same suite measured 11.9 s and 91.4 s: an 8x spread with no code change between them.

  The direction of the ledger's error is conservative — it overstates its own cost — so nothing is being hidden. But the number is presented as a property of the change and is not one, and the real shape of it sharpens rather than softens the CANNOT ASSESS entry at `:311`: what is unbounded on an unknown runner is the log read, and this stage adds a fifth test that waits on it.
- why the builder missed it: two consecutive runs of a bimodal measurement look like a range. Nothing in the method compares against the same suite without the change, so every second of an unrelated slow read was booked to the new test.

### 5. Two falsification rows under-report their own results

- severity: **P3**
- evidence: `PROD-READINESS-3.md:171`, row 1, claims the wiring's removal gives "5 issues across 3 tests". Measured on the full OttoUI suite, with the block removed by an anchored search and the symbol count verified at 0 first:

  ```
  ✘ ImplausibleStoredDayTests.swift:45:9   ledgerFailures → [] == [corrupt.id]
  ✘ ImplausibleStoredDayTests.swift:46:9   canClaimCoverage → true == false
  ✘ ImplausibleStoredDayTests.swift:84:9   ledgerFailures → [] == [corrupt.id]
  ✘ ImplausibleStoredDayTests.swift:111:9  materializeCalls == [healthy.id]
  ✘ ImplausibleStoredDayTests.swift:112:9  invalidateCalls == [healthy.id]
  ✘ SchedulingLogTests.swift:119:24        lines.last { … reason=implausibleStoredDays … } → nil
  ✘ Test run with 201 tests in 37 suites failed after 25.850 seconds with 6 issues.
  ```

  **6 issues across 4 tests.** The row omits the log test, which the very next row (row 4) shows is load-bearing.
  Row 2, "`isPlausibleStoredDay` forced to `true` | 5 issues", measures **12 issues in OttoDomain alone** plus 6 in OttoUI.
  Rows 3 and 4 reproduce exactly, including row 4's "exactly 1 issue, at the target-line `#require` and not at the canary".

  Both discrepancies run in the safe direction — the guard is stronger than the table says — but the table reads as whole-suite measurement and two of its rows are filtered ones.
- why the builder missed it: rows 1 and 2 break things whose tests live in one file, so running `--filter` on that file is the natural loop; rows 3 and 4 have no such focal file and were run whole. The table records four results from two different scopes without distinguishing them.

### 6. `implausibleStoredDays` documents two properties nothing guards

- severity: **P3**
- evidence: `StoredDayPlausibility.swift:53` promises the result is "deduplicated and in day order", implemented at `:77-80` by a `Set` and a `.sorted()`.
  Replacing that whole tail with `candidates.filter { !$0.isPlausibleStoredDay(asOf: today) }` leaves the entire OttoDomain suite green:

  ```
  ✔ Test run with 5 tests in 1 suite passed after 0.001 seconds.
  ```

  Both properties are reachable in practice — `lastUsedDate == cycleStartDay` and `trial.startDate == cycleStartDay` are ordinary shapes — and the observable consequence is a duplicated day in the log line a user's helper is meant to read, which is the surface `SchedulingLogTests` exists to protect. `OttoLog.list` sorts internally (`OttoLog.swift:60`), so ordering is restored downstream by luck rather than by contract.

  Small on its own; recorded because the stage's whole thesis is that an unguarded behaviour is one that silently stops being true, and this is a documented contract with no test.
- why the builder missed it: every test in the file was written against the detector's *decision*, and dedup/order are properties of its *presentation*. `everyScheduledFieldIsChecked` compares against a two-element array (`:93`) that happens to be sorted and distinct, so it looks like it pins both and pins neither.

### 7. "Exactly the fields the planner and the materializer read" is not exact

- severity: **P3**
- evidence: `StoredDayPlausibility.swift:55-56` and `PROD-READINESS-3.md:156` both state the field list is "exactly the ones the planner and the materializer read as days to schedule against".
  The materializer reads one more stored `CalendarDay` that this check never sees — the materialization watermark: `OttoStore+BillingEvents.swift:56-58` does `let storedWatermark = try deviceWatermark(for: subscription.id)` / `let windowStart = min(storedWatermark ?? today, today)`.

  I tried to make this bite and could not, which is worth reporting as clearly as the gap itself. With a stale year-8 watermark beside a *repaired* 2026 anchor the window widens but the sequence does not, because `cycleCharges` generates candidates from the anchor rather than from the window start:

  ```
  PROBE windowStart=0008-08-06 windowEnd=2026-11-12 expectedCharges=4     (anchor 2026-08-06)
  PROBE healthy window                              expectedCharges=3
  ```

  So the omission is currently harmless and the wording, not the code, is what is wrong.
- why the builder missed it: the watermark left the versioned schema in Wave 6A and lives in a different store behind a different repository method, so a review of "which days does a `Subscription` carry" — which is what the helper is — cannot see it.

### 8. Skipping the subscription also skips the cleanup that would have removed its bad rows, and that is not disclosed

- severity: **P3**
- evidence: the new `continue` at `NotificationScheduler.swift:235` sits above `invalidateOutdatedUpcomingEvents` at `:243`, so a skipped subscription is no longer offered to it.
  The stage's own test asserts this: `ImplausibleStoredDayTests.swift:112` requires `invalidateCalls == [healthy.id]`.

  Before this change, a pre-F1 device's era-numbered `.upcoming` rows would have been tombstoned on the next pass — `isExpectedCharge` rejects a 2569 date against a 2026 `today`. They are now retained indefinitely, and they surface on the detail screen's ledger.
  The code comment at `:222-224` justifies the skip only on the write side ("materializing from a corrupt anchor writes ledger rows on dates nothing will ever charge") and the ledger's "What this does NOT do" does not name the read side at all.

  It is arguably the right call — retaining visibly wrong rows is consistent with the stage's own preference for visible wrongness over a tidy lie — and it self-heals the moment the user performs the manual repair `:201` prescribes. Recorded because it is a behaviour change that no sentence in the range accounts for.
- why the builder missed it: the two repository calls are adjacent and were reasoned about as one act ("the ledger pass"), and the falsification that would separate them — assert that invalidate still runs while materialize does not — is not one the fix's story suggests.

### 9. Two supporting claims in the schema decision are wrong, though the decision itself survives

- severity: **P3**
- evidence: the decision at `PROD-READINESS-3.md:117-143` — no V4 — is sound where it matters, and I tried to break it and could not.
  Its load-bearing step is `:121`: a marker column can only be filled from `Calendar.current` **at migration time**, which is not the calendar that wrote the rows, and the Gregorian→Buddhist direction would then rewrite correct billing dates. That is correct, and the fallback ("`Calendar.current` is already readable at repair time without a schema change", `:129`) is correct too. Condition 4's judgment is defensible.

  Two supporting claims are not:

  - `:134` "Japanese year 8 is ambiguous across three eras" — year 8 exists in Meiji (1875), Taisho (1919), Showa (1933), Heisei (1996) and Reiwa (2026): **five**, not three. The error runs in the ledger's favour, but the same sentence's own remedy is two sentences above it — `createdAt` disambiguates all five instantly, since only Reiwa 8 is within days of a 2026 instant. The ledger raises `createdAt` as decisive evidence at `:132`, then argues ambiguity at `:134` without applying it.
  - `:135` "**The schema was never the limitation.**" True for repair, and the reason finding 1 matters: it is also true for *detection*, and the detector that shipped uses none of the V3 evidence the sentence is defending.

  On the Islamic case the ledger is right and I confirmed it: the four variants disagree by up to two days on the same instant (`islamic` 1448-02-23, `islamicCivil` 1448-02-21, `islamicTabular` 1448-02-22, `islamicUmalqura` 1448-02-23), so a repaired billing date would be a ±2-day guess. That alone justifies declining the repair.

  Condition 1 ("item 2 lands first") is recorded as met by "`87d6508` + `7d531de`" (`:139`). `7d531de` is inside *this* stage's range and unreviewed at the moment the decision was taken, so the gate was half-reviewed when it was leaned on. Moot, because the freeze was not lifted.
- why the builder missed it: the section is written to defend a conclusion the author had already reached on the strongest argument (the marker records the wrong instant), and the weaker supporting arguments were never stress-tested because the conclusion did not depend on them.

**One thing the stage does that it does not claim, recorded because it cuts the other way.**
For a negative-offset calendar the pre-stage behaviour was not "nothing is scheduled" — it was a materialization pass over a window centuries wide. Measured with an unrepaired Japanese-calendar anchor and watermark (year 8) against a 2026 horizon:

```
PROBE windowStart=0008-08-06 windowEnd=2026-11-12 expectedCharges=24220
PROBE healthy window                              expectedCharges=3
```

24,220 `BillingEvent` inserts in one pass, on the device store, every pass. The new guard skips that subscription before `materializeEvents` is reached, so this stage prevents it. The ledger only ever measured the Buddhist (positive-offset) case, where `min(2569-08-06, today)` collapses the window to nothing, and so never saw the worse half of the defect it was fixing.

## Explicit checks

1. **Fabricated or unreproducible findings** — **two numbers, no fabrications.** The measured claims re-derive: the PROBE/CONTROL trace at `:104-105` reproduces (with the wiring removed, the corrupt subscription gives `scheduledCount=0, pending=0, ledgerFailures=0, canClaimCoverage=true`, and `coveredThrough=2026-11-09` on both, so "identical on every field Today reads" is exact); falsification rows 3 and 4 reproduce byte-for-byte; the self-caught wrong-reason test is genuine (`FakeBillingEventRepository` writes `watermarks` only at `:24,34,40`, never in `materializeEvents`); the self-reported invalid falsification is genuine (an earlier bare `continue` exists at `NotificationScheduler.swift:168`). The two numbers that do not re-derive are findings 3 and 4, and both err against the builder's own interest.
2. **Citations that don't say what they're claimed to say** — **none.** Every file:line cited in ITEM 1 that I opened is exact; they are listed under "What I ran". Finding 1 is not a bad citation — the sources agree with each other and disagree with Foundation.
3. **Severity inflation or deflation** — **one deflation, finding 1.** The ledger assigns no severities; its self-description is the terminal state. "RESOLVED as detection" over-claims by the two calendars, and `:214`'s disclosure of the threshold as "a judgment" understates it: the number is not merely unprincipled, it is inside two real era offsets, and no value of it can be both wide enough for a 1970 anchor and narrow enough for Ethiopic. Everything else is stated at or below its true weight — `:198-202` and `:211-214` are unusually frank limitation sections.
4. **Features smuggled past the no-features rule** — **none.** What the user sees changes only on a device that holds an implausible stored day, and only by routing through `ScheduleOutcome.ledgerFailures` → `canClaimCoverage` (`ScheduleOutcome.swift:32`) → `TodaySectionPlan.swift:138-140`, all of which predate this range. No new screen, section, setting, navigation or string: the card and its copy are round 2's, unchanged (`TodayView.swift:274,281-282`). The change is one existing card appearing in one more circumstance. Its "it will try again" is permanently false in that circumstance, which the ledger names at `:212` and defers rather than rewriting — the right call under the no-new-copy rule.
5. **SwiftData schema change outside item 1's authorization** — **none, and item 1 did not lift the freeze.** No path under `Sources/OttoPersistence/Schema/` appears in `git diff --name-only 87d6508..e4f4872`. `OttoMigrationPlan.swift:13-19` still reads `[OttoSchemaV1, OttoSchemaV2, OttoSchemaV3]` / `[migrateV1toV2, migrateV2toV3]`, and no `OttoSchemaV4.swift` exists. The four-conditions check reduces to the soundness of the decision to decline, which is finding 9: sound in conclusion, two wrong supporting claims.
6. **Prohibited actions** — **none found.** `.git/FETCH_HEAD` does not exist, so no fetch or pull has ever run in this clone. `.git/ORIG_HEAD` is dated Aug 8, predating the run. The reflog shows one checkout and five commits with no amend, rebase, reset or force entries. No tags exist. `refs/remotes/origin/main` is `406a5a6`, equal to `git merge-base main HEAD`, so nothing was pushed. `<backup-dir>` untouched (`verify.sh` prints a path from `docs/next-wave.md`; it reads nothing there). I made no network call, ran no `ls-remote`/`fetch`/`pull`, touched no physical device, deleted only the four probe files I created, and created no commit.
7. **Fixes that relocated a bug rather than removed it** — **partly, finding 8.** The skip removes the write-side harm and simultaneously removes the cleanup that would have retired the existing bad rows. Not a relocation into a new place, but a suppression the range does not account for. The check itself is in the right layer: the predicate is a pure domain function, the wiring is one `if`/`continue` in the pass that owns ledger upkeep, and nothing was moved to make room.
8. **Error handling that hides errors** — **none.** The new path is the opposite of swallowing: it converts a silent skip into a `ledgerFailures` entry plus an `.error`-level log line, and I confirmed by mutation that removing either one fails a test. One nuance worth naming: `ledgerFailures` now carries two distinct meanings — "materialization threw" and "the stored days are implausible" — which the log distinguishes by `reason=implausibleStoredDays` but the type does not, so the coverage card counts them together. That is a deliberate reuse of an existing surface, not a hidden error.
9. **Verification that doesn't exercise the changed path** — **no.** `ImplausibleStoredDayTests` drives the real `NotificationScheduler.reschedule` end to end and `SchedulingLogTests` reads the line the production statement actually emitted from `OSLogStore`. Every mutation I applied at the call site produced a failure at an assertion about the change, never at a setup step.
10. **Tests that pass for the wrong reason** — **one, and it is finding 1.** `everyEraIsCaught` (`StoredDayPlausibilityTests.swift:32`) claims a universal over Foundation's calendars and tests a six-entry literal that is the claim's own premise; it is green today and would be green if the two calendars it omits were the only ones users had. The ledger's self-caught one is real and I confirmed the fix is load-bearing (removing `continue` fails `:111-112`). The other seven new tests are load-bearing under mutation: the wiring at 4 tests / 6 assertions, the predicate at 12 + 6, the field list at 3, the log statement at exactly 1 at the target `#require`, the threshold at 3. `healthyDeviceIsUnaffected` passes under every mutation, which is what makes it a control. The one unguarded behaviour I found beyond finding 1 is finding 6's dedup and ordering.
11. **Flaky or environment-dependent tests** — **one dependency, disclosed, and worse-behaved than recorded.** `StoredDayPlausibilityTests` reads no clock, locale, calendar or host state, and the scheduler tests pin the zone (`torontoZone`) and the instant (`fixtureNow()`); I confirmed the host-independence claim by running the whole suite under all three non-Gregorian locales, where the new tests pass — including under `ar_SA`, because `CalendarDay.description` is `String(format:)` with a nil locale (`CalendarDay.swift:211`) and so does not render Arabic-Indic digits. The exception is the new `SchedulingLogTests` case, the fifth `OSLogStore(scope: .currentProcessIdentifier)` test: it depends on the log daemon and on `Date()`, and I measured its containing suite at between 11.9 s and 91.4 s on this host in one session. It fails closed (canary first, then a target-line `#require`) so it is a slowness and CI risk rather than a false green. Finding 4 is about the ledger's number for it, not its existence.
12. **Anything marked resolved without an artifact** — **the terminal state is artifact-backed; its non-regression evidence is not.** ITEM 1's "RESOLVED as detection / DEFERRED as repair" rests on committed tests whose falsifications I reproduced, and the DEFERRED half is argued rather than asserted. What has no artifact in the ledger is the baseline: three of four measurements are simply absent (finding 2). I supplied all four.
13. **Every commit in the range builds** — **yes, all three.** `7d531de` and `ddb04bb` built all three packages with `--build-tests` in detached worktrees; `e4f4872` is covered by `verify.sh`, which clones the committed HEAD and additionally builds the app target under `xcodebuild`.
14. **Baseline not regressed** — **verified, all four, by running them, none reasoned about.** `verify.sh` exit 0 at 256 / 119 / 201 = 576; `swiftlint --strict` clean directly and inside `verify.sh`; simulator exit 0, `** TEST SUCCEEDED **`, 113 / 70 / 31 with 7 known issues (the +5 is this stage's OttoUI tests — see finding 2 for the fact that nobody recorded it); non-Gregorian 1 / 1 / 5 at the identical five citations. No pre-existing test was modified anywhere in the range and there are no deletions outside `CloudKitCompatibilityTests.swift`.

## What I could not check, and why

- **Whether iOS's Settings offers the Indian or Ethiopic calendar in its picker.** This decides how reachable finding 1's miss is for a real user. It needs a device or documentation; the device is prohibited and network calls are prohibited. What I could measure — that Foundation supports both, that both produce in-window years from the same instant, that the shipped predicate accepts them, and that no locale defaults to either — I did measure, and finding 1 is stated in those terms only.
- **The two real users' device calendars.** ASSUMPTION 1, undeterminable without the device. Unchanged.
- **Release configuration.** Debug only, matching `PROD-READINESS-3.md:87`. Nothing in the range is configuration-sensitive, but I did not build Release.
- **CI runners.** Whether `OSLogStore(scope: .currentProcessIdentifier)` is readable there is untestable from here without a network call. I confirmed all five such tests pass on this host, which is the evidence the ledger claims and no more — and finding 4 shows the cost of that read varies 8x on a single host, which is the part CI most needs to know and nobody can measure from here.
- **Whether the `createdAt`-keyed detector in finding 1 is a finished design.** I measured its sensitivity across 13 calendars and its specificity against the ledger's own six legitimate fixtures, on the anchor field only, with a 31-day window. I did not characterise it for `lastUsedDate` or a distant `pauseEndsOn`, and I am not asserting it is ready to ship — only that it catches what the shipped rule structurally cannot, on V3 data, with no schema change.
- **A real store.** All scheduler measurements ran against `FakeBillingEventRepository`, which is what the stage's own tests use. Finding 7's watermark measurement is against the domain's `expectedCharges` rather than against SwiftData, so the 24,220-row figure is a count of expected charges, not of observed inserts.

Working tree restored and clean: `git status --porcelain` is empty, `git worktree list` shows only the repository, every probe file was one I created and deleted, no stage file was modified in the main tree at any point (all mutation work ran in a detached worktree), and no commit was created by this review.
