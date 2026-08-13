# REVIEW-6 - round 4, stage 6 (every remediation)

Range reviewed: `1a1d23b..92174e4` (17 commits).
Reviewed head: `92174e4`.
Ledger: `PROD-READINESS-4.md`. Baseline: `reviews-4/BASELINE-4.md`.
Prior verdicts in this run: `reviews-4/REVIEW-1.md` … `REVIEW-5.md`, `reviews-4/REVIEW-AA92CA7.md`.

Every `PROD-READINESS-4.md:NNN` citation below is a line number in `git show 92174e4:PROD-READINESS-4.md`, not in the working tree - the branch advanced twice under me (`a9144c7`, `3ec68e2`, both ledger-only) and that file moved. Quoted text is the stable reference.

verdict: REJECT

## Summary

The code in this range is right and small, and I could not break the parts that matter.
The entire production diff is three files, two of which are comment-only; the only behaviour change in the whole range is eight lines in `AppModel+Export.swift`.
All five baseline dimensions reproduce at `92174e4` exactly as the ledger's own verification table records them, all 51 builds across all 17 commits pass, the SwiftData schema is untouched, `.swiftlint.yml` and `.github/workflows/` are untouched, nothing was pushed or rewritten, and no assertion was removed that did not move to another file.

**Five of the six guards the ledger claims for the stage-1/stage-4 remediation bite, at exactly the issue counts recorded**, and the sixth is honestly recorded as still green.
`reviews-4/REVIEW-5.md` finding 1 is genuinely closed: reverting the pass-end call site to its pre-fix interpolation now fails, 1 issue, in the window `SchedulingLogTests` already had open, at zero new `OSLogStore` reads.
`reviews-4/REVIEW-4.md` finding 3 is genuinely closed: adding the tombstoned row's own amount to the log line fails on the new `!line.contains("1099")` assertion, 2 issues.
`reviews-4/REVIEW-2.md` finding 2's re-derived falsification counts reproduce to the digit - I measured 15 domain issues over 3 tests plus 2 in OttoUI over 1 test for row 1, exactly as re-recorded.
The item-6 falsification correction reproduces: under `OS_ACTIVITY_MODE=disable` all three OttoPersistence log-reading tests fail at `requireDelivered`.
`reviews-4/REVIEW-AA92CA7.md`'s N2-4 reopening is true and I re-derived it at this head rather than taking it: the failure entry still caps at 1037 characters and names 15 complete identifiers of 64 failed rungs.

It is rejected for what the record does, not for what the code does.

**First, a P2 finding is recorded closed and its replacement names a step the affected user cannot perform.**
`docs/next-wave.md` was rewritten because an earlier version told a non-Gregorian user to re-pick dates that have no picker. The new row for `lastUsedDate` says it "is only ever written as *today*, by answering 'Yes - still using it' on a usage check-in; doing that once overwrites the corrupt value with a correct one."
Measured: an active subscription whose `lastUsedDate` is 2569 - the exact Buddhist corruption this document's own example uses - is planned **zero** usage check-ins, where the identical fixture with a plausible last use is planned one. The check-in is counted *from* `lastUsedDate`, so the corrupt field suppresses the only notification the document names as its repair. The in-app control that does work, "I used this today", is named nowhere.

**Second, the single production behaviour change in the range has no observer, and the ledger records it as "Fixed." with no falsification.**
Deleting the `catch`-branch generation guard from `AppModel+Export.swift` leaves the whole simulator suite `** TEST SUCCEEDED **`. Every other fix in the same remediation section carries a measured issue count; this one carries a sentence. `N4-9` is disclosed as unguarded and this is not.

**Third, three corrections this range announces are not applied to the surfaces a later round reads, and two of the surviving statements were written inside this range after the review that refuted them.**
`56f5f55` is titled "Correct the concurrency claims the stage-3 review measured false"; at `92174e4` `ITEM 4`'s own body still says `peakConcurrency == 2` "**does not reproduce**: measured, the two passes run one after the other at peak 1", the `NOT DEFECTS` table added by `d2b9c85` records "5 passes at peak concurrency 3", and the `N4-3` entry added by `cb034b7` still says at P3 that "Whether the two can OVERLAP is **not** established". Each is contradicted by the remediation section in the same file.
`d7c2792` is titled "Withdraw a wrong correction"; the withdrawn 2K+1 conviction survives verbatim at `:563` and the withdrawn figure survives at `:619`.

**Fourth, roughly fifteen findings from three of the six reviews are neither fixed nor carried**, including three ledger sentences a reviewer measured false that still stand at this head.

None of this is a regression, none of it is fabricated, nothing hides a production error, and there is no P1.
I considered PASS-WITH-FINDINGS. I did not take it because this is the run's *remediation* range: its one job is that a finding recorded closed is closed, and two are not - one of them the run's only user-facing deliverable for the population it cannot detect, rewritten once for exactly this defect and shipped with it again.

## What I ran

All mutation work was done in three detached worktrees I created under my own scratchpad (`wt/rev6`, `wt/mut`, `wt/mut2`), all at `92174e4`. All three are removed and `git worktree list` now shows only `/Users/<user>/dev/otto`; every one was `git status --porcelain` empty before removal.
No command's `--package-path` pointed into the main tree; `verify.sh` ran from my own worktree and clones itself into its own temp directory. I made no commit, ran no network command, touched no physical device, touched nothing in `<backup-dir>`, ran no `git checkout --` in the main tree, and deleted no file I did not create - the three probe files I added inside worktrees I deleted myself.
Every mutation was applied by a script that printed the exact text it removed and asserted the occurrence count before writing, and was reverted from a saved copy.

Host: macOS 15.6.1 (Darwin 24.6.0), arm64, Xcode 26.3, SwiftLint 0.65.0, simulator `<simulator-udid>`.

### The five baseline dimensions, re-measured at `92174e4`

**1. `./scripts/verify.sh` - exit 0.**

```
== VERIFIED: 92174e421499125f943d6de655c9e59261e8f6fd builds, tests, and lints from a clean clone
   OttoDomain: 261
   OttoPersistence: 127
   OttoUI: 209
   total: 597 tests
./scripts/verify.sh  196.58s user 38.49s system 116% cpu 3:21.67 total
```

Baseline `2d8913c` was 258 / 124 / 207 = 589. The ledger's FINAL VERIFICATION column says `261 / 127 / 209 = 597`. **Exact match.**

**2. `swiftlint --strict`, standalone - exit 0.**

```
Done linting! Found 0 violations, 0 serious in 225 files.
```

Ledger: `clean, 225 files`. **Exact match.** Baseline was 220.

**3. Simulator suite, from `Packages/OttoUI/` - exit 0.**

```
✔ Test run with 119 tests in 22 suites passed after 8.232 seconds.
✔ Test run with  72 tests in 12 suites passed after 0.305 seconds.
✘ Test run with  52 tests in  9 suites passed after 5.030 seconds with 7 known issues.
** TEST SUCCEEDED **
```

Ledger: `119 / 72 / 52 = 243`, 7 known issues. **Exact match.** Baseline was 117 / 72 / 36. The seven known issues are the unchanged `EmptyStateTests` accessibility assertions; this host vends no AX tree.
I ran the simulator suite ten times in total across this review (one clean head run, eight mutations, one coordinator falsification); both runs that should have been green were, byte-identical in shape.

**4. Non-Gregorian harness - 1 / 1 / 5, the same five citations.**

Bundle path absolute, run from the worktree root, per `CalendarEraTests.swift`'s header.

```
th_TH@calendar=buddhist          1 issue   209 tests in 38 suites failed after 15.198 s
    DisplayFormattingTests.swift:49:9   ("Aug 15, 2569 BE") == "Aug 15, 2026"
ja_JP@calendar=japanese          1 issue   209 tests in 38 suites failed after 15.729 s
    DisplayFormattingTests.swift:49:9   ("Aug 15, Reiwa 8") == "Aug 15, 2026"
ar_SA@calendar=islamic-umalqura  5 issues  209 tests in 38 suites failed after 16.442 s
    DisplayFormattingTests.swift:49:9   ("Rab. I 2, 1448 AH") == "Aug 15, 2026"
    DisplayFormattingTests.swift:59:9   ("Every ٤٥ days")     == "Every 45 days"
    DisplayFormattingTests.swift:68:9   ("١ subscription")    == "1 subscription"
    DisplayFormattingTests.swift:69:9   ("٣ subscriptions")   == "3 subscriptions"
    NotificationReconciliationTests.swift:170:9  ("… on Rab. I 12.") == "… on Aug 25."
```

Identical to `reviews-4/BASELINE-4.md`, at 209 tests rather than 207.

**5. Flake rate - 12 of 12, and 6 of 6.**

`swift test --package-path Packages/OttoUI`, twelve consecutive unmutated runs in a clean worktree at `92174e4`:

```
run  1 rc=0 ✔ 209 tests in 38 suites passed after 20.402 s
run  2 rc=0 ✔ 209 …  15.019 s     run  8 rc=0 ✔ 209 …  16.965 s
run  3 rc=0 ✔ 209 …  12.441 s     run  9 rc=0 ✔ 209 …  15.602 s
run  4 rc=0 ✔ 209 …  10.891 s     run 10 rc=0 ✔ 209 …  15.582 s
run  5 rc=0 ✔ 209 …  11.472 s     run 11 rc=0 ✔ 209 …  15.112 s
run  6 rc=0 ✔ 209 …  14.091 s     run 12 rc=0 ✔ 209 …  15.627 s
run  7 rc=0 ✔ 209 …  14.238 s
SUMMARY pass=12 fail=0
```

`swift test --package-path Packages/OttoPersistence`, six consecutive runs:

```
run 1 rc=0 ✔ 127 tests in 26 suites passed after 34.670 s
run 2 rc=0 ✔ 127 …  27.101 s     run 5 rc=0 ✔ 127 …  32.563 s
run 3 rc=0 ✔ 127 …  33.910 s     run 6 rc=0 ✔ 127 …  34.499 s
run 4 rc=0 ✔ 127 …  35.238 s
SUMMARY pass=6 fail=0
```

**12 of 12 and 6 of 6.** Spread 10.9 s - 20.4 s, much narrower than `reviews-4/BASELINE-4.md`'s 15.5 - 126.4 s; the batch ran with nothing else of mine on the host, which is the known cause and not a finding. `SyncActivationServiceTests`, the pre-existing flake `reviews-4/REVIEW-2.md` finding 10 saw once in 24, did not fire in any of my 18 host runs.

### Per-commit build sweep - every commit in the range, all three packages

`swift build --build-tests --package-path Packages/<pkg>` in a detached worktree, detaching onto each of the 17 commits in turn: **51 of 51 OK, 0 failed.**

```
d609790  d2b9c85  c902d45  cb034b7  80eeb97  f3e5aa1  56f5f55  29fa754  f7a76ab
38b1137  d7c2792  ae73bad  8a56e52  4ea69b5  c79dc8c  92d8629  92174e4
```

### Falsifications

Each printed the exact text it removed and asserted the occurrence count was 1 (or 2, where stated) before writing; each was reverted from a saved copy and `git status --porcelain` confirmed empty afterwards.

| # | what I broke | ledger records | I measured |
|---|---|---|---|
| M1 | `requestExport`'s body emptied (`AppModel+Export.swift:63`) | 2 issues | **2 issues** ✅ `requestExportBuildsTheFile` at `SettingsExportTests.swift:292` and `:293` |
| M2 | `await onMutation?()` deleted from `PaymentMethodsStore.delete` | 1 issue | **1 issue** ✅ `aPaymentMethodDeleteWithdraws` at `:319` |
| M3 | `preparing` restored to single-valued (3 edits) | 1 issue | **1 issue** ✅ `theTwoKindsDoNotShareState` at `:234` |
| M4 | `exportFailures[kind] = nil` → `exportFailures.removeAll()` | 1 issue | **1 issue** ✅ `aFailureOnOneKindIsNotClearedByTheOther` at `:271` |
| M5 | the reminder-time `withdrawPreparedExports()` deleted | 1 issue | **1 issue** ✅ `aReminderTimeChangeWithdraws` at `:346` |
| M6 | both cancellation-evidence withdraws deleted | still green (N4-9) | **`** TEST SUCCEEDED **`** ✅ as disclosed |
| M7 | the `catch`-branch generation guard removed | **no row; "Fixed."** | **`** TEST SUCCEEDED **`, rc 0** ❌ finding 2 |
| M8 | the tombstoned row's own `amount` added to the log line | "Both are asserted now" | **2 issues** ✅ `UnreportableInvalidationTests.swift:174`, both on `!line.contains("1099")` |
| M9 | pass-end call site reverted to the exact pre-fix interpolation | 1 issue | **1 issue** ✅ `SchedulingLogTests.swift:197`, `…ledgerFailures=1").contains("truncatedAfter=")` |
| M10 | the pass-end emission deleted altogether | not claimed | **1 issue** at `:193` |
| M11 | the guard's own pass retagged `.foreground` → `.stateChange` | not claimed | **1 issue** at `:193` - but **green** once a sibling emits, see finding 7 |
| F2 | `next = self.queued` → `next = nil` in `rescheduleSoon` (`reviews-4/REVIEW-3.md`'s F2, re-run because this range edited that suite's triggers) | 1 issue | **1 issue** ✅ `NotificationCoordinatorTests.swift:250`, `(scheduler.passes.count → 1) == 2` |
| ITEM3-row1 | `isPlausibleStoredDay` body → `abs(year - today.year) <= 100` | 15 domain / 3 tests + 2 OttoUI / 1 test | **15 / 3** and **2 / 1** ✅ exact |
| E1 | nothing broken; `OS_ACTIVITY_MODE=disable` on OttoPersistence | all three fail at `requireDelivered` | **3 issues** ✅ `CorruptWatermarkTests:58`, `MappingLogPrivacyTests:98`, `UnreportableInvalidationTests:157` |

### Probes I wrote (in my worktrees, deleted with them)

**A. The `docs/next-wave.md` repair path, driven through the real planner.**

```
ZZPROBE healthy  planned=4 usageCheckIns=1 days=[2026-08-30]
ZZPROBE buddhist effectiveStatus=active planned=3 usageCheckIns=0   implausible=[2569-05-01]
ZZPROBE indian   effectiveStatus=active planned=4 usageCheckIns=1   implausible=[1948-05-15]
ZZPROBE paused buddhist isResumedPause=false effective=paused
ZZPROBE paused indian   isResumedPause=true  effective=active
ZZPROBE trial buddhist conversion=2569-05-31 isConvertedTrial=false effective=trial editsAsTrial=true
ZZPROBE trial indian   conversion=1948-06-14 isConvertedTrial=true  effective=active editsAsTrial=true
```

**B. N2-4 re-derived at this head** (`SchedulerFixture`, indices 900+, `refuseAdds(after: 0)`, reading the process's own `scheduling` category):

```
ZZTRUNC subs= 4 entryLen= 822 named=12 failedCount=12   complete
ZZTRUNC subs= 6 entryLen=1037 named=15 failedCount=18   TRUNCATED  tail=…000000000904|2026-10-22|renewal=AddRefused 00000000-0<…>]
ZZTRUNC subs=20 entryLen=1037 named=15 failedCount=60   TRUNCATED
ZZTRUNC subs=64 entryLen=1037 named=15 failedCount=64   TRUNCATED
```

(`reviews-4/REVIEW-AA92CA7.md` says "16 of 64"; my counter requires a `=` in the token and therefore drops the partial trailing identifier. Same measurement, 15 complete plus one truncated fragment.)

**C. The K sweep, re-derived from a standalone Foundation script importing no Otto code** - `America/Toronto`, `createdAt` = Gregorian 2026-08-06 12:00, the thirteen calendars whose year offset at that instant is non-zero (measured, not assumed: `ethiopicAmeteAlem` reads `2026-8-6` on this SDK), 4001 anchors ending at `createdAt`:

```
                          strict/<=   lenient/<=   strict/<   lenient/<
K= 1                          3           3           1          1
K= 3                          7           7           5          5
K= 7                         15          15          13         13
K=31                         62          64          61         62
anchors counted ONLY by the lenient reading: 2018-10-31, 2018-12-31
   2018-10-31 as an Ethiopic triple normalises to 2018-11-1 = Gregorian 2026-07-08
   2018-12-31 as an Ethiopic triple normalises to 2018-13-1 = Gregorian 2026-09-06
distinct Ethiopic readings of createdAt ± 31 days: 63, first 2018-10-29, last 2018-13-01
distinct VALID Gregorian anchors reachable: 62, 2018-10-29 .. 2018-12-30
```

"strict" round-trips the triple back through the calendar and rejects it if Foundation silently normalised it; "lenient" does not.

## Findings

### 1 - P2. `docs/next-wave.md`'s rewritten `lastUsedDate` row names a repair the affected user cannot perform, and omits the one that works

**Evidence.** `docs/next-wave.md:27`, the whole of the row this range added:

> | the last recorded use (`lastUsedDate`) | **There is no picker for this at all.** It is only ever written as *today*, by answering "Yes - still using it" on a usage check-in; doing that once overwrites the corrupt value with a correct one. |

Three things are wrong with it, in ascending order.

*"Yes - still using it" is not a control in the app.* It is a `UNNotificationAction` title (`LiveNotificationClient.swift:111`). The in-app control is `UsageSectionView`'s **"I used this today"** (`PauseFlowView.swift:171`), which calls `AppModel.recordUsage` (`AppModel.swift:191-196`) → `SubscriptionFlowService.recordUsage` (`:148-154`) - the same writer, reachable without waiting for anything. The document names neither it nor the screen it is on.

*"only ever written as today" is true of the field and false of the sentence's implication.* `recordUsage` has two entry points, not one: the notification action (`NotificationActionHandler.swift:156-159`) and the button above. The ledger's own verification of this fix (`PROD-READINESS-4.md:673`) stops at the writer - *"`lastUsedDate` is only ever written as *today* by `recordUsage`"* - and never asks which triggers reach it.

*The named trigger never arrives for the field it repairs.* `usageCheckInReminders` counts the cadence **from `lastUsedDate`** (`ReminderSchedule.swift:228`: `let reference = subscription.lastUsedDate ?? subscription.billingAnchor(asOf: today)`), then breaks out of the loop as soon as `reference.adding(days: multiple * cadence) > window.upperBound` (`:238-239`). With `lastUsedDate` = 2569-05-01 the first candidate is 2569-07-30 and the loop exits immediately. Measured through the real planner, probe A: an otherwise healthy `.active` subscription with a Buddhist-corrupt last use is planned **0** usage check-ins where the identical fixture with a plausible last use is planned **1**. So a user who follows the document waits for a check-in that the corruption itself has suppressed.

2569 is not an edge case I chose: it is this document's own running example (`:11`, `:17`, `:31`).

**Why this is P2 and not P3.** `reviews-4/REVIEW-2.md` finding 3 was P2 for precisely this - "the manual repair shipped to users names two dates the app offers no way to re-pick, under a heading that asserts it works". The heading still asserts it works (`:9`, "**The repair is manual, it works**"). The paragraph is the run's only mitigation for the users it cannot detect, and the ledger stamps the finding closed (`PROD-READINESS-4.md:673`: *"The section is now a field-by-field table that says which dates have a picker, which needs a resume-and-re-pause, and which repairs only by answering the next usage check-in."*). The closing sentence of the section (`:29`) makes the field load-bearing: *"A subscription is repaired - and starts scheduling again on the next pass - once **every** day the log line names is fixed"*, and `lastUsedDate` is one of the five days the log line names (`StoredDayPlausibility.swift:122`).

**What the other three rows are.** I checked them all and they hold.
Row 1 ("Next charge on") - correct on the edit screen (`AddEditSubscriptionView.swift:171`); the parenthetical "(or **Started on**)" names an add-only field, since `offersEntryModeChoice` is `original == nil` (`SubscriptionFormModel.swift:220`) and an edit is pinned to `.nextCharge` (`:187`). Cosmetic.
Row 2 ("Trial started") - correct: `editsAsTrial` is `storedStatus == .trial` (`SubscriptionTransitions.swift:149`), so the picker appears on edit under both offset directions (probe A), and `conversionDate` is `startDate.adding(days: lengthDays)` (`TrialTerm.swift:60-62`), so it does repair with it.
Row 3 ("Billing resumes") - correct, and the case `reviews-4/REVIEW-2.md` raised is genuinely closed: a Buddhist-corrupt `pauseEndsOn` leaves `effectiveStatus == .paused`, so `PauseSectionView` renders "Resume billing now" (`PauseFlowView.swift:137`); an Indian-corrupt one derives to `.active` and renders "Got it - mark as active" (`:122`), which calls the same `resumeSubscription`. Both clear the corrupt day, because `pauseEndsOn` derives from the *open* episode (`PauseEpisode.swift:168`). The row does not mention that the "Billing resumes" picker is behind the "I know when billing resumes" toggle (`PauseFlowView.swift:36-43`); minor.

**Why the builder missed it.** The rewrite was driven off `reviews-4/REVIEW-2.md`'s finding, which was framed as "which fields have a picker". Enumerating pickers is the right question for three of the four rows and the wrong question for the fourth, where the repair is a flow: the writer was found, and nothing asked whether the trigger that reaches the writer survives the corruption. The two call sites of `recordUsage` were then collapsed into the one the notification uses.

### 2 - P2. The only production behaviour change in the range has no observer, and is recorded as "Fixed."

**Evidence.** `git diff --name-only 1a1d23b..92174e4` touches three files under `Sources/`. Two are comment-only (`StoredDayPlausibility.swift`, `NotificationCoordinator.swift` - every added line begins `///`). The third, `AppModel+Export.swift:93-103`, is the whole of this range's production behaviour change:

```swift
} catch {
    preparing.remove(kind)
    if generation == exportGeneration {
        exportFailures[kind] = error.localizedDescription
    }
    throw error
}
```

Removing the `if` - one occurrence, printed - and running the full simulator suite from `Packages/OttoUI/`:

```
✔ 119 in 22 suites   ✔ 72 in 12 suites   ✘ 52 in 9 suites passed with 7 known issues
** TEST SUCCEEDED **   rc=0
```

Byte-identical in shape to the unmutated head.

`PROD-READINESS-4.md:687` records it as:

> **The generation guard covered the success branch and not `catch`.** A failure recorded against a database that has since changed is as stale as a file built from it. Fixed.

Every other entry in that section's table carries a measured issue count, including one honest "**still green**" for the cancellation-evidence pair, which is then carried as `N4-9`. This one carries neither.

**Why this is P2 and not P3.** The underlying defect (`reviews-4/REVIEW-4.md` finding 4) is P3 in impact - a stale failure banner, not a stale file. What makes this P2 is where it sits: this is the remediation range for a review whose headline P2 was *"the remediation's new guards do not bite where the ledger says they do"*, and the answer to it ships the one new behaviour with no guard and no disclosure. `reviews-4/REVIEW-4.md` finding 1's mechanism was "one test was added per probe, and nothing enumerated the new call sites against the tests that observe them"; the same enumeration was not done for the fix that finding 4 asked for.

There is also no reachable test for it: `aFailureOnOneKindIsNotClearedByTheOther` drives a failing transfer but never interleaves a withdrawal with an in-flight build, and `aWithdrawalDuringABuildWins` interleaves a withdrawal with a *succeeding* build. The shape the guard exists for - a build that is superseded and then fails - is produced by nothing.

**Why the builder missed it.** The success-branch guard already had a test (`aWithdrawalDuringABuildWins`), so the `catch` branch looked like the same fix in a second place rather than a second uncovered path. The remediation bullet was written as prose next to a table, and prose does not carry a column that would have been empty.

### 3 - P2. Three corrections this range announces are not applied, and two of the surviving statements were authored inside this range

**Evidence.** All line numbers are `git show 92174e4:PROD-READINESS-4.md`.

**(a) The stage-3 concurrency claims.** `56f5f55` is titled *"Correct the concurrency claims the stage-3 review measured false"*. At `92174e4`:

| still says | contradicted by, in the same file |
|---|---|
| `:399` "The obvious assertion, `peakConcurrency == 2`, **does not reproduce**: measured, the two passes run one after the other at peak 1." | `:651` "That was one run. The reviewer … measured overlap in **45 of 240 iterations**." |
| `:372-373` `peakConcurrency=3` twice, and `:377` "**The peak is 3, not the 5 predicted** - 3 is what the executor actually interleaved, and the number recorded is the measured one." | `:659` "The reviewer measured 2, 5, 3, 3 - including the 5 my sentence said had not happened … **Only the pass count is recorded now**." |
| `:541` `NOT DEFECTS` table: "\| F10 \| fired five triggers - 5 passes at peak concurrency 3 \|" | the same `:659` |
| `:638-639` "**N4-3 (P3)** … Whether the two can OVERLAP is **not** established - the assertion was written, measured at peak concurrency 1, and deleted." | `:654` "**N4-3 is raised from P3 to P2**: it is not a note about coalescing scope, it is F10 still live on a second path." |

`:399` and `:372-377` predate the range (`2082b69`). **`:541` and `:638-639` do not** - `d2b9c85` and `cb034b7` wrote them inside this range, before `f3e5aa1` landed the stage-3 review in the tree, and `56f5f55` did not sweep back to them. So the correction commit left standing two statements its own range had just written and one that its title says it removed.

The corrected version *is* in the shipped source: `NotificationCoordinatorTests.swift:256-283` now carries "**They do overlap, about one run in six**" with both distributions. That is the good half. The ledger's `## NEXT ROUND` list and `## NOT DEFECTS` table are the surfaces a round-5 reader opens, and they say the opposite.

**(b) The K-sweep withdrawal.** `d7c2792` is titled *"Withdraw a wrong correction"*. `:252` says *"That conviction is withdrawn … I convicted three documents on it"* and `:671` says *"the conviction is gone"*. At the same head:

- `:563`, in `## WHAT IS WRONG OR UNDERSPECIFIED IN THE ROUND-4 PROMPT` (written by `c902d45`, inside this range): *"A window of ±K days around a single collision point contains exactly **2K+1** days: 3, 7, 15, **63**. The prompt says 64, `PROD-READINESS-3.md` says 64, and `reviews-3/REVIEW-4.md` records that it 're-derived it to the digit' - overruling `reviews-3/REVIEW-3.md`, which had 63 and was right."* That is the whole withdrawn argument and the whole withdrawn conviction, restated.
- `:619`, the `N3-2` carry-forward row (written by `cb034b7`, inside this range): *"Its K=31 false-positive figure is corrected from 64 to 63."*

The `## WHAT IS WRONG … PROMPT` section is the artifact whose entire purpose is to be read by whoever writes round 5's prompt.

**Why this is P2.** `PROD-READINESS-4.md:702` names this class as the run's worst: *"`reviews-4/REVIEW-4.md` finding 2, and `reviews-4/REVIEW-3.md` finding 5, and `reviews-4/REVIEW-1.md` finding 9 are the same finding, three times. … This is the run's worst process defect and it was restated twice without being fixed."* It is now four more times, in the range that diagnosed it, and half of the instances are text this range wrote.

**Why the builder missed it.** Corrections are written where the review is answered - a new `### Remediation after …` section - and the sections that already said the wrong thing are never re-read. `grep` for the retracted sentence would have found every one of these in one command.

### 4 - P2. Fifteen findings from three of the six reviews are neither fixed nor carried, and three ledger sentences a reviewer measured false still stand

**Evidence.** The ledger's remediation sections answer, by name: all five of `reviews-4/REVIEW-3.md`; all six of `reviews-4/REVIEW-5.md`; `reviews-4/REVIEW-2.md` 1, 2, 3, 4; `reviews-4/REVIEW-4.md` 1, 2, 3, 4; `reviews-4/REVIEW-AA92CA7.md` 1, 2, 3, 4. Nothing in the range - not the remediation sections, not `## NEXT ROUND`, not `## NOT DEFECTS`, not `## DEFERRED` - mentions:

- `reviews-4/REVIEW-2.md` 5, 6, 7, 8, 9, 10
- `reviews-4/REVIEW-4.md` 5, 6, 8, 9, 10 (7 is partly answered - `AppModel+Export.swift` now appears in the FINAL VERIFICATION split list at `:731`)
- `reviews-4/REVIEW-AA92CA7.md` 5, 6, 7, 8 - and `:715` acknowledges "**Plus five P3s**" while recording one of them

Three of those are statements a reviewer measured false and that are still in the ledger at this head:

| still in the ledger | measured false by |
|---|---|
| `:318` "the rule newly rejects only 1900-01-01 to 1955-12-31" | `reviews-4/REVIEW-2.md` finding 9. The old rule `abs(y - 2026) <= 100` already rejected 1900-1925; the **newly** rejected set is 1926-01-01 .. 1955-12-31 |
| `:146` "the footer gains one sentence: *'Otto builds a file only when you ask for it, and stops offering it once your data changes …'*" | `reviews-4/REVIEW-4.md` finding 5. The shipped footer is `SettingsView.swift:177-183`, *"…so a complete copy of your finances isn't left lying around. Editing a subscription or importing a backup withdraws one you already built."* `:352` of the same file says the first sentence was wrong and was replaced |
| `:152` "`reviews-4/REVIEW-1.md` finding 4 caught one of these eight numbers being stale; **all of them were**" | `reviews-4/REVIEW-4.md` finding 6. `reviews-4/REVIEW-1.md:195` says the other six reproduced exactly, and three carry the same value in the new table as the old |

`reviews-4/REVIEW-AA92CA7.md` finding 7 is the one with a contract consequence: `R0-2` is a round-1 P2 that appears in no terminal state in any round's record. `grep -n "R0-2\b"` over `PROD-READINESS-4.md` at this head returns nothing, and the ledger's own contract (`:47`) is *"Terminal states are **RESOLVED** … **DEFERRED** … or **REJECTED TWICE** … There are no others."*

**Why this is P2 and not a pile of P3s.** Individually every one is a record defect. Collectively it is the failure mode the review-range design exists to prevent, applied to the reviews themselves: a remediation range that answers a subset and does not say what happened to the rest leaves the next round unable to tell "considered and declined" from "not read". Two of the three surviving false sentences were flagged *by name, with line numbers* by a reviewer inside this run.

**Why the builder missed it.** Each remediation section was written against the review's headline P2s. Nothing walked the reviews' finding lists to completion, and `## NEXT ROUND` was written before four of the six reviews landed.

### 5 - P3. `N4-7` and `N4-8` are cited in shipped source and name nothing at the reviewed head

**Evidence.** `NotificationCoordinator.swift:183` and `:188`, added by this range to a production file:

> Closing it means putting the gate at the `ReminderScheduling` seam the three callers share rather than in this class, which is a larger change than F10 was scoped to. `PROD-READINESS-4.md` N4-3 and N4-7.
>
> … That is an inherent cost of coalescing rather than a defect … `PROD-READINESS-4.md` N4-8.

At `92174e4`, `grep -n "N4-7\|N4-8"` over the ledger returns only `:658` and `:660` - two sentences inside `### Remediation after reviews-4/REVIEW-3.md` that coin the identifiers in passing. `### Discovered by round 4` ends at `N4-6`. So a reader following the pointer from shipped source into the ledger's carried-item list finds no entry; and the one entry that does exist for the other identifier the same sentence names, `N4-3`, is the stale one from finding 3.

This is `reviews-4/REVIEW-2.md` finding 6 recurring verbatim - *"`N4-2` is cited in shipped source and did not exist for six commits"* - which the ledger accepted at the time.

**Repaired outside my range.** `a9144c7` ("Complete the carried-forward list and the assumptions"), which landed while I was measuring, adds `N4-7` through `N4-12` as proper entries. The finding stands against `92174e4`, which is the head I was given, and it is closed on the branch.

### 6 - P3. The K=31 figure the ledger retains reproduces under no definition I can construct; the strict answer is 62

**Evidence.** The withdrawal at `:252` is right about the *argument*: the Ethiopic band is not contiguous and 2K+1 does not hold. I confirmed that independently - the K=31 band skips 2018-10-31, because Ethiopic months are 30 days and that triple is not an Ethiopic date.

What it retains is wrong in two ways.

First, the evidence quoted for 63. `:252` says the readings are *"**63 distinct days spanning 2018-10-29 to 2019-01-01**, a 65-day span"*. Measured: there are 63 distinct Ethiopic readings of `createdAt ± 31 days`, and the last of them is **2018-13-01**, not 2019-01-01 - Ethiopic's thirteenth month. The "65-day span" is that month-13 date read as though it were January. A triple with month 13 cannot be a Gregorian stored day at all, so it is not a false positive of anything.

Second, the number. Over the 4001 Gregorian anchors the sweep scans, with the reading round-tripped so that Foundation's silent normalisation cannot manufacture a match, I measure **62 / 4001 (1.55%)** at K=31 - and 3 / 7 / 15 at K=1 / 3 / 7, agreeing with everyone. Without the round-trip guard I measure **64**, and the two extra anchors are exactly `2018-10-31` and `2018-12-31`, neither of which is a valid Ethiopic date:

```
2018-10-31 as an Ethiopic triple normalises to 2018-11-1 = Gregorian 2026-07-08
2018-12-31 as an Ethiopic triple normalises to 2018-13-1 = Gregorian 2026-09-06
```

So `reviews-3/REVIEW-3.md`'s 63, `PROD-READINESS-3.md`'s 64, `reviews-4/REVIEW-2.md`'s 64 and this ledger's 63 are four values for one quantity, and the one that survives a reading no Ethiopic device could have written is a fifth: 62. The ledger's `:266` is the right conclusion - *"the figure decides nothing here"* - and `:257`'s claim *"My scan still returns 63, under **both** readings"* is not reproducible under either reading I can build.

**Severity P3**, not higher, for the reason the ledger gives: the `createdAt` cross-check is declined on the sensitivity-versus-gap table, where the numbers differ by two orders of magnitude, and `reviews-4/REVIEW-2.md` confirmed that table reproduces cell for cell. Recorded because it is the third round in which this cell has been wrong, and because it was re-derived in this range in direct response to a review.

### 7 - P3. The new R4-3 guard asserts over an unpinned shared log window, and a sibling satisfies it

**Evidence.** `SchedulingLogTests.swift:192-195`, the assertion this range added to close `reviews-4/REVIEW-5.md` finding 1:

```swift
let passEnd = try #require(
    lines.last { $0.hasPrefix("pass end trigger=foreground") },
    "the trigger-tagged pass emitted no pass-end line"
)
```

`lines` is `Self.schedulingLogLines(since:)` - the whole `scheduling` category for the process. The two assertions twenty lines above it in the same test are pinned to a fixture UUID the test owns (`:167`, `lines.last { … && $0.lowercased().contains(mine) }`); this one is pinned to nothing but a trigger name shared by every foreground pass in the target. The same file still states the window's reach as "~80 ms" at `:92`, while the comment this range wrote in `UnreportableInvalidationTests.swift:130-135` puts it at 15.30 / 12.66 / 15.12 seconds and says that is *"what makes pinning to an identifier this test owns necessary rather than tidy"*.

Measured against a population I control. M11 alone - retag the test's own pass `.foreground` → `.stateChange`, so its production path stops producing the line the assertion looks for:

```
✘ SchedulingLogTests.swift:193:27  lines.last { $0.hasPrefix("pass end trigger=foreground") } → nil
✘ Test run with 209 tests in 38 suites failed with 1 issue.
```

M11 with one temporary sibling test added to the same target, driving trigger-tagged `.foreground` passes for six seconds:

```
✔ Test run with 6 tests in 2 suites passed after 12.119 seconds.
```

The `#require` is satisfied by a line the test did not produce. `@Suite("What a failed scheduling pass leaves behind (RF-3)")` carries no `.serialized` trait, so its tests already interleave.

**What it does and does not disarm.** The R4-3 regression itself stays caught: under M9 a sibling's line lacks `truncatedAfter=` too, so `passEnd.contains("truncatedAfter=")` still fails. What the masking covers is the presence half - the pass ceasing to emit a foreground-tagged line at all, which is the shape M10 and M11 both have. Today no sibling emits one, which is why M10 and M11 are red at head.

This is `N4-12`'s own hazard - which this range coined - reproduced in the range's own new assertion: *"a sibling's canary masks a deleted canary, wherever tests share a log window … Every canary falsification in this tree needs `--filter` or a suppressed subsystem, and none of them says so."*

### 8 - P3. `OttoLog.swift`'s doc comment still carries the justification the ledger withdrew, and says the emission is unguarded

**Evidence.** `OttoLog.swift:96-100`, untouched by this range:

> Composed here rather than interpolated at the call site so a test can read the line without opening `OSLogStore` - the tree already blocks on that daemon nine times, and a tenth reader for one field is not a trade worth making. What this does NOT guard is the emission; see `PROD-READINESS-4.md` N4-5.

Both halves are now false. The ledger at `:498` says *"**N4-5 is closed**, and the cost I quoted for it was never the cost on the table"*, and `:668` carries `N4-5` as CLOSED. The emission *is* guarded - I broke it two ways and both fail. The comment sits directly above the function the fix is about, and `SchedulingLogTests.swift:34-38` - the other comment `reviews-4/REVIEW-5.md` finding 6 flagged - *was* corrected in this range, which shows the sweep was done and stopped one file short.

### 9 - P3. The full-branch sweep claims 30 commits; the branch has 32

**Evidence.** `PROD-READINESS-4.md:752-756`:

> **Every one of this run's 30 commits builds all three packages** … `SWEEP: 30 building, 0 non-building, 30 commits`

`git log --format=%h 2d8913c..92174e4 | wc -l` gives **32**. Thirty is the count at `c79dc8c`, two commits before the head that publishes the sentence; `92d8629` and `92174e4` touch only `PROD-READINESS-4.md`, so the claim is materially true and numerically wrong. Recorded because the sentence is offered as "the artifact rather than the claim" and the artifact does not cover the head it is stamped at. My own sweep covers all 17 commits of this range at 51/51.

## Explicit checks

- **Fabricated or unreproducible findings.** Two numbers do not reproduce: the K=31 figure (finding 6) and the "30 commits" sweep (finding 9). Everything else in the range reproduces, and several claims reproduce that I expected not to - all five guarded rows of the item-1 remediation table to the issue count and the failing test's name, item 3's re-derived row 1 at 15/3 + 2/1, the `OS_ACTIVITY_MODE` row at three issues on the three named tests, the N2-4 truncation at 1037 characters, and the `pass end` guard at 1 issue under the reviewer's own mutation. The `NOT DEFECTS` table's F10 row carries a figure the same file says should not be recorded (finding 3), which is a retained number rather than a fabricated one.
- **Citations that do not say what they are claimed to say.** Four. `:146` (footer copy the tree replaced), `:152` ("all of them were"), `:318` ("newly rejects"), and `:252`'s "2019-01-01" for a month-13 Ethiopic date. Plus the two dangling identifiers in shipped source, finding 5. I checked the citations that carry the range's own load and they hold: `NotificationCoordinator.swift:170-180`'s claim that exactly five trigger classes reach `rescheduleSoon` in production is exact (`:112`, `:117`, `:132`, `:338`, `:363` - and `NotificationStatusStore.swift:45-48` really does call the scheduler directly with `.stateChange`); `StoredDayPlausibility.swift:59-64`'s corrected attribution of "forty years beyond the oldest plausible billing anchor" to `PROD-READINESS-3.md` ITEM 1 rather than to a doc comment is right; `SchedulingLogTests.swift:34-38`'s newly scoped "no PRODUCTION reader" is right, and the two test readers it names exist.
- **Severity inflation or deflation.** One deflation, finding 3: `N4-3` is carried at P3 in the entry a round-5 reader reads while the same file raises it to P2 and measures 45/240 and 74/180. One under-scoping, finding 2: an unguarded production change presented without the disclosure its sibling `N4-9` gets. No inflation found - `N4-7` and `N4-10` and `N4-11` are all carried at P2, which matches what was measured, and `N4-6`'s deferral is correctly scoped.
- **Features smuggled past the no-features rule.** None. Three production files, two comment-only; the third adds a conditional, no new API, no new copy, no navigation. `docs/next-wave.md` is explicitly permitted. No `UserDefaults` key, no `Package.swift` or `project.yml` change, no dependency, no new screen. `git diff --name-only 1a1d23b..92174e4` over `.swiftlint.yml`, `.github/`, every `Package.swift`, `project.yml`, `PROD-READINESS{,-2,-3}.md`, `reviews/`, `reviews-2/`, `reviews-3/`, `DECISIONS.md`, `README.md` and every `docs/` file except `next-wave.md` returns **nothing**.
- **Any SwiftData schema change.** None. The range touches nothing under `Packages/OttoPersistence/Sources/` at all - the only OttoPersistence file in the diff is a test. No `Stored*`, no `OttoSchemaV*`, no `OttoMigrationPlan`. V3 stays frozen.
- **Prohibited actions.** None observed. `git show-ref` puts `refs/heads/main` and `refs/remotes/origin/main` both at `406a5a6`, so nothing was pushed or merged; `.git/FETCH_HEAD` does not exist; `git tag` is empty; `92174e4` is still an ancestor of the branch tip, so no history was rewritten. `.swiftlint.yml` is untouched - no rule relaxed, disabled, re-thresholded, and no `excluded:` path added; the one `excluded:` entry (`Packages/*/.build`) is pre-existing. `--strict` is clean over 225 files, so nothing was made to pass by widening a rule.
- **No test weakened.** `git diff 1a1d23b..92174e4 -- Packages/ | grep '^-' | grep -E '#expect|#require'` returns 18 lines; 16 of them are the four withdrawal tests moving verbatim into `SettingsExportWithdrawalTests.swift`, and the other two belong to `theTwoKindsDoNotShareState`, which was rewritten to start two builds instead of one - strictly stronger, and M3 proves it bites where the old version did not. 35 assertions added, none disabled: no `withKnownIssue`, `.disabled`, `.enabled(if:)` or `XCTSkip` anywhere in the diff.
- **The file split.** Forced and behaviour-preserving. `SettingsExportTests.swift` is 377 lines at head; re-inlining `SettingsExportWithdrawalTests.swift`'s five test bodies (~105 lines) puts it past SwiftLint's default 400-line `file_length`, and `.swiftlint.yml` sets no override. The moved tests are byte-identical apart from `await transfer.isWaiting` → `await transfer.waiting > 0`, forced by the spy's `Bool` → `Int` change so it can park two builds. The three spies lost `private` so both files share them, which is what the new file's header says. The simulator arithmetic reconciles exactly: SettingsExportTests 5 out / 5 in, the new suite +4, bucket 48 → 52, suites 8 → 9.
- **Fixes that relocated a bug rather than removed it.** No. Finding 2 is a fix with no observer, not a relocation - the guard is in the right branch and does the right thing. Finding 1 is the adjacent case one level up: a documented procedure repaired for two fields and left broken for a third.
- **Error handling that hides errors.** Nothing new. The one change to an error path *narrows* what is recorded (`exportFailures[kind]` is skipped for a superseded generation), and the error is still thrown to the caller unchanged; the user-visible effect is a banner that is not shown for a request the model has already superseded, which is the intent. Nothing is caught and discarded anywhere in the diff.
- **Verification that does not exercise the changed path.** Finding 2, squarely, and it is the only production behaviour in the range. The two comment-only production changes need none.
- **Tests that pass for the wrong reason.** One, finding 7, and it is the range's headline guard. Everything else I tried to break, broke: eleven mutations, each failing at an assertion that names the thing I broke, none at a setup step.
- **Flaky or environment-dependent tests, especially over a shared log window.** No flake observed - 12 of 12 on OttoUI, 6 of 6 on OttoPersistence, ten simulator runs, three harness locales, all with identical counts. Three tests in the range assert over shared log windows: `UnreportableInvalidationTests` is pinned to subscription index 7011 and its pin is load-bearing; `SchedulingLogTests`' skip-line assertion is pinned to fixture UUID 88; the new pass-end assertion is pinned to nothing (finding 7). The new UI tests' `settle` loops all now capture and assert their return - `#expect(bothParked, …)` and `#expect(withdrawn, …)` - which closes the half of `reviews-4/REVIEW-4.md`'s flake note that mattered.
- **A further `OSLogStore`-reading test.** **None added.** The count stays at ten (OttoUI 7, OttoPersistence 3). The R4-3 guard was closed inside a query `SchedulingLogTests` already opens, which is exactly what the prompt's "why a shared query would not do" asks for and what `reviews-4/REVIEW-5.md` demonstrated. This is the constraint the range respects best.
- **Anything marked resolved without an artifact.** Finding 2. Also finding 1, in the sense that a P2 is stamped closed on a rewrite nobody executed - and it does not survive execution.
- **Every commit in the range builds all three packages.** Yes - 51 of 51 across 17 commits.
- **Falsifications broke the thing the finding is about.** Every mutation touched a production call site, a production log statement, a production wiring line or the test's own entry point - never a proxy. Each printed the removed text and asserted its occurrence count before writing. The one presence-assertion I attacked over a shared window (finding 7) was checked against a population I built myself.

## What I could not check, and why

- **That a human tapping the export row produces a file.** Unchanged and correctly carried as `N4-1`. `requestExport` is now guarded - M1 gives 2 issues - and the closure in `SettingsView.swift:212-216` is reachable by no test in this project. I established only the negative.
- **That a user can actually perform the `docs/next-wave.md` repair on a device.** Finding 1 is established by execution against the planner and by reading every affordance's visibility condition; I did not drive the app on a simulator with a corrupt database and tap through it. What I measured is that the notification the document names is never scheduled for the corrupt field, and that a control the document does not name reaches the same writer.
- **Release configuration.** Debug only. `verify.sh` builds the app target unsigned for a generic simulator destination. ASSUMPTION 3 carries.
- **A physical device**, and therefore the file protection class on exports left in `tmp`, real `BGAppRefreshTask` behaviour, and whether either real user is on a non-Gregorian calendar. Prohibited this run; ASSUMPTION 1 carries.
- **The `OSLogStore` readers on a CI runner.** Unchanged CANNOT ASSESS. All ten passed here, in `verify.sh`, in every flake run and in every harness locale, with no canary firing. I reproduced the *shape* of the environment failure with `OS_ACTIVITY_MODE=disable`, which is the closest available proxy.
- **Whether the concurrent passes `N4-7` measures actually corrupt anything.** `reviews-4/REVIEW-3.md` proved overlap and not harm; nothing in this range changes that, and settling it needs a fake client that records interleaved reads and writes. It is the open question behind `N4-3` / `N4-7` and it is correctly carried.
- **The other four rows of `reviews-4/REVIEW-AA92CA7.md`'s P3 list, and round 1's `R0-2` on its merits.** I established only that they are in no terminal state in round 4's record.
- **Whether my flake batch and the baseline's are comparable.** Mine ran on a quiet host and is much faster (10.9-20.4 s against 15.5-126.4 s). Pass/fail is comparable; wall time is not.
- **Two commits landed after my range while I worked** - `a9144c7` and `3ec68e2`, both `PROD-READINESS-4.md`-only. `a9144c7` closes finding 5 by adding `N4-7` .. `N4-12` as entries. `3ec68e2` adds an `## EVERY UNVERIFIED FIX, AND WHY` table which does **not** list the `catch`-branch generation guard, so finding 2 is not repaired by it. Neither touches findings 1, 3, 4, 6, 7, 8 or 9. My verdict is on `92174e4`.
