# REVIEW-2 — stage 2, commit range `a82d4e0..100c508`

**VERDICT: PASS-WITH-FINDINGS**

The range holds three logical changes: stage 1's own remediation (`4b18420`), the R4-1 feature (`eb4a13b`), and two ledger bookkeeping commits (`8d1ce30`, `100c508`), plus the stage-1 review artifact (`5be3c64`).
All of it is correct at HEAD, none of it touches the schema, and none of it takes a prohibited action.
The stage-1 remediation is the strongest work in either round so far: the three unguarded F1 sites REVIEW-1 named now have guards that I broke individually and watched fail for the defect they name, and the builder correctly overturned its own reviewer's mechanism for R0-7 (I traced the code and the builder is right, the reviewer was wrong).

The findings are that **R4-1's verification does not exercise the two places R4-1 actually lives** — the view wiring that connects the store to the plan, and the branch that picks between the two wordings — while `PROD-READINESS-2.md:156` claims the opposite in as many words: *"Falsified, at the wiring rather than at a helper."*
I cut the wiring and swapped the wordings and every test on both the host and the simulator stayed green.

---

## Verification re-derived from scratch (nothing below is read from an artifact)

| measurement | `reviews-2/BASELINE-2.md` at `7a3cf54` | re-derived by me at `100c508` |
|---|---|---|
| `scripts/verify.sh` | exit 0, 533 (246 / 113 / 174) | **exit 0**; OttoDomain **248**, OttoPersistence **113**, OttoUI **185**, total **546** |
| `swiftlint --strict` | clean | **clean** (inside `verify.sh`, exit 0) |
| simulator from `Packages/OttoUI/` | `** TEST SUCCEEDED **`, 101 / 65 / 20, 7 known issues | **`** TEST SUCCEEDED **`**, **102 / 70 / 26**, **7 known issues**, exit 0 |

Deltas reconcile exactly to the diff, per commit:

- host OttoUI 174 → 185 = `a82d4e0` +4, `4b18420` +4, `eb4a13b` +3. The commit messages' 178 → 182 → 185 are all correct.
- simulator 20 → 26 = `CalendarEraViewTests` +3, `DynamicTypeTests` +1, `TodaySectionPlanTests` +2; 65 → 70 = `a82d4e0` +3, `CalendarEraTests` +1, `CoverageHonestyTests` +1. `eb4a13b`'s claimed "102/70/26" is exact.
- the 7 known issues are the same four `EmptyStateTests` accessibility assertions at `:211`, `:235`, `:254`, `:295`. Nothing regressed.

The non-Gregorian harness reproduces, and so do all three of its baselines:

```
th_TH@calendar=buddhist        185 tests, 1 issue   (DisplayFormattingTests.swift:49)
ja_JP@calendar=japanese        185 tests, 1 issue   (DisplayFormattingTests.swift:49)
ar_SA@calendar=islamic-umalqura 185 tests, 5 issues (DisplayFormattingTests.swift:49,59,68,69,
                                                    NotificationReconciliationTests.swift:170)
```

### Stage-1 remediation: falsified independently, and it holds

Reverting the three fix lines REVIEW-1 finding 1 named (`CalendarDayBinding.asDate`'s default, `InsightsView.monthText`'s calendar, `DisplayFormatting.spokenText`'s default) in a scratch clone at `100c508`:

```
=== GREGORIAN ===  ✔ Test run with 185 tests in 32 suites passed.
=== BUDDHIST  ===  ✘ Test run with 185 tests in 32 suites failed with 5 issues:
  CalendarEraViewTests:37  (binding.asDate().wrappedValue → 1483-08-15 05:17:32 +0000)
                            == (gregorian.date(from:) → 2026-08-15 04:00:00 +0000)
  CalendarEraViewTests:51  (stored → 2569-08-15) == (day → 2026-08-15)
  CalendarEraViewTests:59  (InsightsView.monthText → "สิงหาคม 2026") == ("สิงหาคม 2569")
  CalendarEraTests:105     summary.spokenText → "…on Dec 31, 2512 BE."
  DisplayFormattingTests:49 (pre-existing)
=== BUDDHIST, --filter CalendarEra ===
  ✘ Test run with 7 tests in 2 suites failed with 4 issues.
```

Every one of the four fails for the defect it names, and `:51` is the DatePicker write path putting an era-numbered year into billing data - the site REVIEW-1 said mattered most.
The Gregorian result is the honest limitation, stated in both test files and in `PROD-READINESS-2.md:116`.
The ledger's falsification row 4 ("4 issues") is the filtered run and is exact; the unfiltered command prints 5.

### R4-1's three claimed falsifications all reproduce

```
plan's .coverageGap branch removed  → ✘ 3 issues, first being
    (ledgerFailed → [needsAction, next30Days]).contains(.coverageGap)
lastPassFailed = outcome == nil removed → ✘ (store).lastPassFailed → false
.frame(height: 44) on the card      → ✘ (accessibility → 44.0) > (regular * factor → 66.0), twice
                                       ** TEST FAILED **, exit 65
```

The pre-fix probe reproduces too: with the branch removed, `plan` returns `[needsAction, next30Days]` for both the ledger-failed and pass-failed states against `[needsAction, next30Days, coverage]` for the healthy one, exactly as `PROD-READINESS-2.md:138-140` records.

---

## Findings

### 1. P2 — R4-1's view wiring can be cut with every test green, and the ledger claims it was falsified there

**severity:** P2, not P1: the code at HEAD is correct and the card does appear.
What is missing is any artifact that would notice if it stopped appearing - the same standard REVIEW-1 finding 1 applied to F1, applied here for consistency.
It sits at the top of P2 because the record does not merely omit the gap, it asserts the opposite.

**evidence.**
In a scratch clone at `100c508`, deleting `lastPassFailed: model.notifications?.lastPassFailed ?? false` from `TodayView.swift:52` (the `Input` field carries a default, so this compiles):

```
✔ Test run with 185 tests in 32 suites passed after 0.053 seconds.
```

Separately, replacing `coverageGapSection`'s body (`TodayView.swift:138-142`) with `EmptyView()`, so the card is never constructed at all:

```
✔ Test run with 185 tests in 32 suites passed after 0.050 seconds.
```

Nothing in the tree renders `TodayView`: `grep -rn "TodayView" Packages/OttoUI/Tests/` returns nothing, and the simulator suite's only view-hosting file is `EmptyStateTests`, which hosts the Subscriptions list.
The first cut is the consequential one. `lastPassFailed` is the entire reason the store gained new state, and it is the only input that produces the **pass-failed** card - the case the commit message leads with (`pass failed : [needsAction, next30Days]`). With the argument gone, the ledger-failure card still renders via `input.scheduleOutcome?.canClaimCoverage == false`, so half of R4-1 silently disappears while the other half keeps working and the suite keeps passing.

Against this, `PROD-READINESS-2.md:156` reads **"Falsified, at the wiring rather than at a helper."**
The three rows under that heading are `TodaySection.plan` (a pure static function the test calls directly - the helper-shaped seam), `NotificationStatusStore.apply` (a store), and a `.frame` on `CoverageGapCard` (a leaf view).
Each of those is real and each reproduces; none of them is the wiring.

**why the builder missed it.**
`TodaySection.plan` was extracted precisely so the composition rule would be testable, and once the rule had a guard the seam felt closed.
But the extraction moved the decision out of the view and left the view's *construction of the input* behind, and that construction is a private method on a `View`.
This is the shape the builder itself diagnosed one commit earlier, in `InsightsView.swift:136-138`: *"a `private` member of a `View` is the one shape no host test can reach."*
That lesson was applied to `monthText` in `4b18420` and not carried into `eb4a13b`.

### 2. P2 — the two wordings can be swapped and nothing fails, including the sentence the ledger says must never appear

**evidence.**
`CoverageGapCard.headline` and `.detail` (`TodayView.swift:274-290`) branch on `failureCount > 0`.
`PROD-READINESS-2.md:147` gives the reason two wordings exist: *"a whole failed pass has no per-subscription count and '0 subscriptions couldn't be updated' is not what happened."*
Inverting both ternaries in a scratch clone - so a whole failed pass renders exactly `"0 subscriptions couldn't be updated"`:

```
host:      ✔ Test run with 185 tests in 32 suites passed after 0.053 seconds.
simulator: ✔ "the coverage-gap card grows … in both wordings" passed after 0.244 seconds.
           ** TEST SUCCEEDED **, exit 0
```

`assertGrows` measures fitted height only, so it is satisfied by either wording in either slot.
Both `headline` and `detail` are `private`, so no host test can reach them either.

`PROD-READINESS-2.md:164` attributes this to the environment: *"The rendered strings are not asserted: this host vends no accessibility tree."*
That is true and I confirmed it - all 7 known issues are `labels.contains` / activation failures inside `EmptyStateTests` - but it is the wrong diagnosis for this gap.
The missing guard is not on the *rendered* string, it is on the **branch selection**, which needs no accessibility tree at all: making `headline` and `detail` non-private, exactly as `monthText` was made non-private in the previous commit for exactly this reason, puts both under `swift test` on the host.
Recorded as an environment limit, the gap reads as unavoidable when it is not.

**why the builder missed it.**
"Assert the copy" and "assert the accessibility tree" were treated as the same task, so the known impossibility of the second was taken to dispose of the first.

### 3. P3 — N2-1 misdiagnoses three of its five tests, and its scope claim is contradicted by the builder's own numbers four lines above it

**evidence.**
`PROD-READINESS-2.md:188`: *"five tests pin rendered date strings that a non-Gregorian `Calendar.autoupdatingCurrent` legitimately writes differently, so they fail on any non-Gregorian host: `DisplayFormattingTests.swift:49,59,68,69` and `NotificationReconciliationTests.swift:170`."*

The five line numbers are right. The characterisation is wrong for three of them, and the scope claim is wrong for four.
Running the `ar_SA@calendar=islamic-umalqura` harness at `100c508` myself:

```
DisplayFormattingTests.swift:59  (cycleText(every45) → "Every ٤٥ days")     == "Every 45 days"
DisplayFormattingTests.swift:68  (subscriptionCountText(1) → "١ subscription") == "1 subscription"
DisplayFormattingTests.swift:69  (subscriptionCountText(3) → "٣ subscriptions") == "3 subscriptions"
```

Those three are **Arabic-Indic numerals from the `ar_SA` locale's numbering system**. They are not date strings, they contain no date, they never touch `Date.FormatStyle`, and the calendar is irrelevant to them - `cycleText` interpolates an `Int` through `String(localized:)` and `subscriptionCountText` through `AttributedString(localized:)`.
The stated mechanism (*"`Date.FormatStyle` renders through the process calendar and a `.locale()` call does not override it"*) is correct for `:49` and `NotificationReconciliationTests.swift:170` and inapplicable to the other three.

"They fail on any non-Gregorian host" is falsified by the numbers recorded at `PROD-READINESS-2.md:122` and in `CalendarEraTests.swift:27-29`, which the builder measured itself: 1 issue under `th_TH@calendar=buddhist` and `ja_JP@calendar=japanese`, 5 under `ar_SA`.
I reproduced all three. On the two non-Gregorian hosts that are not also Arabic-numeral locales, four of the five pass.

The same misdiagnosis is **shipped in source** at `CalendarEraTests.swift:30-32`: *"all of which pin rendered strings that a non-Gregorian `Calendar.autoupdatingCurrent` legitimately writes differently."*
The per-locale counts in that comment are correct; the causal sentence is not.

The consequence is bounded - N2-1 is a NEXT ROUND note about pre-existing tests, and the failing-test inventory is accurate - but whoever picks it up is told to fix over-specified date assertions and will find three tests that have nothing to do with dates.

**why the builder missed it.**
The five failures were collected from one `ar_SA` run in a stage whose entire subject was the calendar, and the calendar was assumed to be the cause of everything the run printed rather than read off each message.

### 4. P3 — "440 lines" is not reproducible from the committed artifacts; the figure is 456

**evidence.**
`PROD-READINESS-2.md:168`: *"The card pushed `TodayView.swift` to 440 lines, past SwiftLint's 400-line `file_length`."*
Reconstructing the unsplit file - `TodaySectionPlan.swift`'s enum body reinserted into `TodayView.swift` at `100c508`, its file header and imports dropped - gives 456 lines, and SwiftLint says so:

```
TodayView.swift:456:1: error: File Length Violation: File should contain 400 lines
or less: currently contains 456 (file_length)
```

The load-bearing half of the claim is true and I confirmed it independently: `.swiftlint.yml` carries no `file_length` override, so SwiftLint's default 400-line warning applies and `--strict` makes it an error; the split was necessary and the file was untouched (`git diff --name-only a82d4e0 100c508 -- .swiftlint.yml` is empty).
Only the number is unreproducible.
This is the class REVIEW-1 finding 5 raised one commit earlier - *"a number carried from a working note and never re-derived from the committed diff"* - recurring in the very document written to correct it.

**why the builder missed it.**
Measured at some intermediate working state and not re-derived once the enum's own new members (`.coverageGap`'s doc comment, `Input.lastPassFailed`) had been written.

### 5. P3 — the REVIEW RANGES table still has no row for this stage, which is REVIEW-1 finding 6 recurring

**evidence.**
`PROD-READINESS-2.md:44-47` carries rows for stage 0 and stage 1 only.
`a82d4e0..100c508` - the range this review was handed - appears nowhere in the ledger, and neither does the reviewed head.
`:42` introduces that table as the fix for round 1's `RF-2`, the blind spot in which commits fell outside every review's range; `reviews-2/REVIEW-1.md:196` had already made the argument that *"the range and the reviewed head - both of which were knowable at commit time - should have gone in with the commit."*
Stage 1's row was added in `4b18420`. Stage 2's was not added in `eb4a13b` or in either bookkeeping commit, so the table is one stage behind for the second time.

**why the builder missed it.**
The row is being held for the verdict again, which is the same "I will record it later" that produced `RF-2`.

---

## Checked and found clean

- **SwiftData schema.** No change of any kind. `git diff a82d4e0 100c508 | grep -E '^\+.*(@Model|VersionedSchema|SchemaMigrationPlan|@Attribute|@Relationship|SchemaV|MigrationStage|Schema\()'` matches exactly one line, and it is prose inside `reviews-2/REVIEW-1.md` describing the absence of such a change. No file under `Packages/OttoPersistence` is touched. V3 is untouched. `NotificationStatusStore.lastPassFailed` is an in-memory `@Observable` property on a class that is never persisted.
- **Prohibited actions by the builder.** Twelve files changed, all of them `PROD-READINESS-2.md`, `reviews-2/REVIEW-1.md`, or source/test files under `Packages/OttoUI`. `.swiftlint.yml`, `.github/workflows/`, `project.yml`, every `Package.swift`, `PROD-READINESS.md`, everything in `reviews/`, and every narrative document are untouched. No new dependency, no new config key, no Swift language mode or SDK change. Reflog shows five ordinary commits and no rebase, reset, amend, or tag operation. `.git/FETCH_HEAD` does not exist and `refs/remotes/origin/main` is still `406a5a6`, so nothing was fetched or pulled; `git branch -a --contains 100c508` returns only the local branch, so nothing was pushed.
- **The R4-1 copy exception was not exceeded.** The card names a count and nothing else - `CoverageGapCard` takes a single `Int` and has no other input, and `ScheduleOutcome.ledgerFailures` is `[UUID]`, so no vendor or amount is reachable without a fetch that does not happen. It reuses `unreadableRecordsSection`'s shape exactly (`Label` / `VStack` headline + subheadline / orange `exclamationmark.triangle` / `.accessibilityElement(children: .combine)`). No new screen, no new setting, no new navigation, no new persistence. Extending it to `.provisional` mirrors `.coverage`'s own pre-existing `authorized || provisional` gate rather than widening scope.
- **No other feature smuggled.** The only other source changes are a one-line comment repoint in `LiveNotificationClient.swift:234`, `InsightsView.monthText` going from `private func` to `static func` (module-internal, no public API change, required by REVIEW-1 finding 1), and the `TodaySection` move. I diffed the moved enum against its `a82d4e0` form: the only semantic change is the `.coverageGap` case, the `lastPassFailed` input, and the restructuring of the coverage `if` into an `if/else if` that preserves `.coverage`'s condition exactly.
- **The file split is authorized and behaviour-preserving.** The scope constraint explicitly requires restructuring over relaxing a limit, `.swiftlint.yml` is untouched, and I confirmed the unsplit file genuinely violates `file_length` under `--strict`.
- **The fix does not relocate a bug.** F1's remediation adds guards and widens one method's visibility; it moves no logic. R4-1 is purely additive to `plan` - I confirmed `.coverage`'s emission condition is bit-for-bit the same before and after, so no state that previously showed the coverage sentence stops showing it.
- **Error handling.** Nothing is swallowed. `apply(nil)` still drops the stale outcome, `reschedule`'s catch is unchanged, and `lastPassFailed` makes a previously-invisible failure *more* visible rather than less. `reconcileLedger`'s per-subscription failure collection is untouched.
- **Guards that stay green before and after.** Each new guard was individually falsified above and each died with the line it guards. The one inert pair is `TodaySectionPlanTests.swift:57-58` (`#expect(ledgerFailed != healthy)`), which was already true before the fix because `healthy` carried `.coverage`; the file says so itself in the comment immediately above, and the load-bearing `contains(.coverageGap)` assertions on the next lines are the ones that fire. Disclosed, not concealed.
- **Assertions already true for an unrelated reason.** Checked the four candidates. `CalendarEraViewTests.swift:59` compares two strings that both render through the process calendar, so it is a real comparison and not a tautology - it prints `"สิงหาคม 2026" == "สิงหาคม 2569"` on revert. `CoverageHonestyTests`'s opening `#expect(!store.lastPassFailed)` is trivially true from the default, but the two assertions after it are not, and I proved both fail when the derivation line is deleted. `spokenTextIsGregorian` computes its expected string from a locally built Gregorian calendar rather than from the code under test.
- **"Cannot be verified" claims.** Two are made in this range and I attempted both. The accessibility one is real: every one of the 7 known issues is a `labels.contains` or activation failure inside `EmptyStateTests`, so this host does not vend a usable tree. Its *scope* is overstated, which is finding 2. The `handleBackgroundRefresh` one is true as stated - I read `NotificationCoordinator.swift:149-183` and confirmed `onOutcome` is never called on either the normal or the expiration path, while `rescheduleSoon` (`:114-125`) calls `onOutcome?(outcome)` with `try?`, so all five listed triggers do publish nil; the file opens with `#if os(iOS)`, so none of it compiles under host `swift test`. That gap is correctly routed to round 1's `R4-2`.
- **The traced R0-7 mechanism is right, and the builder was right to correct its own reviewer.** `PROD-READINESS-2.md:112` says no reminder is planned at all, not a trigger 543 years out. I verified each step: `NotificationScheduler.swift:16,76` do define the 90-day horizon as cited, `ReminderSchedule.swift:33` computes `let window = today...today.adding(days: horizonDays)` and every planner filters `in: window`, `OttoStore+BillingEvents.swift:54` is literally `let windowStart = min(storedWatermark ?? today, today)`, and `reconcileLedger` (`NotificationScheduler.swift:261-301`) appends to `failures` only on a thrown error - so era-numbered data produces an empty plan, no rows, no ledger failures, `canClaimCoverage == true`, and `coveredThrough` at the full horizon. `reviews-2/REVIEW-1.md:134`'s "543 years out" was wrong and the ledger correctly says so. Raising R0-7 to P1 follows from that mechanism and is not inflation.
- **Severity elsewhere is neither inflated nor deflated.** F1 keeps round 1's P1. N2-1 is P2 for a pre-existing test-quality issue that blocks nothing. Both RESOLVED terminal states have artifacts I reproduced. The two boundaries F1 explicitly does not cover are stated rather than claimed closed.
- **Nothing marked resolved without an artifact.** F1 cites `a82d4e0` + `4b18420` and R4-1 cites `eb4a13b`; all three exist, all three are inside a reviewed range, and I falsified a guard from each.
- **Citations spot-checked and accurate.** `NotificationScheduler.swift:16,76`, `OttoStore+BillingEvents.swift`'s `min(storedWatermark ?? today, today)`, `unreadableRecordsSection` as the aggregate-card precedent, `ScheduleOutcome.canClaimCoverage == ledgerFailures.isEmpty`, the five `rescheduleSoon` trigger call sites, and the per-locale issue counts in `CalendarEraTests.swift:27-29` all say what they are claimed to say. `a82d4e0`'s diff does add exactly 6 tests and 14 assertions, and the remediation adds exactly 4, as `PROD-READINESS-2.md:123` states. "Eight guards" reconciles to 4 `CalendarEraTests` + 3 `CalendarEraViewTests` + the `LiveNotificationClientTests` trigger guard.
- **REVIEW-1's findings are genuinely closed, or correctly reclassified.** Finding 1: closed by three new guards I broke individually. Finding 2: the consequence is now written down and the mechanism is *better* than the review's. Finding 3: the source comment is repointed at the ledger (`reviews-2/BASELINE-2.md:64`'s copy of the same forward reference was left alone, but that file is a frozen baseline record and the target now exists, so the citation resolves). Finding 4: the pre-existing non-Gregorian baseline is now recorded in both the ledger and the source, and the counts are correct - only the causal explanation is wrong, which is finding 3 above. Finding 5: 14 assertions and 6 tests are now stated and both re-derive. Finding 6: partly - stage 1's row landed, stage 2's did not, which is finding 5 above. Finding 7: the "real framework types, not the subsystem" correction is accurate.

## Prohibited actions by me: none, and what I did instead

- No network call of any kind. No `git ls-remote`, `git fetch` or `git pull`. Remote state was read with `git show-ref`, `git remote -v`, `git branch -a --contains` and the absence of `.git/FETCH_HEAD` only. `git clone /Users/<user>/dev/otto <scratch>` is a local-filesystem clone.
- No device. Three iOS Simulator runs only, all on `id=<simulator-udid>`: one clean at HEAD from `Packages/OttoUI/`, and two `-only-testing:OttoUITests` falsification runs from the scratch clone.
- No edit to any repository file except this one. Every falsification edit was made in a throwaway clone under the session scratch directory, outside the repository, and the clone was `git checkout -- .` reset after each run; it ends clean at `100c508`.
- Nothing deleted, nothing in `<backup-dir>` touched, no `rm -rf` on any path outside the scratch directory I created.
- `scripts/verify.sh` exited 0, so it wrote no `verify-*-failure.log` into the repository.

Repository state at the end of this review: `git rev-parse HEAD` = `100c508b3fc5a67f9fe4af4f15b8bd3b0176a5ba`, `git status --porcelain` empty apart from this file.
