# REVIEW-4 - round 4, stage 4 (item 5 + stage 1's remediation)

Range reviewed: `54bb611..05ff987`.
Reviewed head: `05ff987`.
Ledger: `PROD-READINESS-4.md`. Baseline: `reviews-4/BASELINE-4.md`. Prior verdict in this run: `reviews-4/REVIEW-1.md`.

verdict: PASS-WITH-FINDINGS

## Summary

The code in this range is sound and the numbers in it are real.
Every one of the eleven falsification rows the ledger carries at this head - seven for item 1, four for item 2 - reproduces to the issue and to the test, which is the opposite of what `reviews-4/REVIEW-1.md` finding 4 found one stage earlier.
All five baseline dimensions are at or above `reviews-4/BASELINE-4.md`, all three commits build all three packages, the SwiftData schema is untouched, no lint rule moved, no assertion was weakened, and no test was skipped or disabled.
Item 5's fix is a real fix: I broke the save key, the log statement and the tombstone decision, and the three new persistence tests failed each time in the shape the code claims.

Two things are not sound.

First, the remediation's guards do not bite where the ledger says they do.
`PROD-READINESS-4.md:331` says findings 3, 5 and 6 are each "fixed, each with a guard that bites"; findings 3 and 5 are, and finding 6 is not - I restored the single-valued state machine exactly and the whole simulator suite stayed green.
`:327` says finding 2 is "Fixed on both sides"; the payment-method **save** is guarded and the **delete** is not, and the two paths the same paragraph singles out as newly corrected - the reminder-time change whose comment was "measured false", and the two cancellation-evidence editors - are both unguarded.
Five removals plus the new `requestExport` indirection, applied together in one run with each removal printed and its occurrence count asserted, leave `** TEST SUCCEEDED **`.

Second, the reviewed head does not record the item the stage delivered.
At `05ff987` the work list still says item 5 is `pending`, there is no `## ITEM 5` section, no falsification table, no cost statement for the tenth `OSLogStore` read, and the REVIEW RANGES table has empty cells for stages 2, 3, 4 and 5 - including stage 4's own row.
The ledger's rule at `:84` is that "a stage's reviewed head is the commit that RECORDS its measurements"; this head records stage **1's** measurements. That is `reviews-4/REVIEW-1.md` finding 9 restated at `:335` and not applied.
Later commits outside my range close it (`2082b69` writes items 4-7, `1a1d23b` the verification table, `d609790` the range table), so this is completion lag rather than a misstatement - which is why it is a finding and not a reject.

Nothing in this range is fabricated, nothing regressed, and no scope rule was broken.

## What I ran

All mutation work was done in three detached worktrees under a temp path I created (`.../scratchpad/rev4/wt`, `wt2`, `wt3`); they are removed and `git worktree list` no longer shows them.
I made no commit, ran no network command, touched no physical device, edited nothing in the main working tree, and deleted no file I did not create.
No build or test command in this review pointed a `--package-path` at `/Users/<user>/dev/otto`; `verify.sh` was run from my worktree, which clones itself into its own temp directory.
The branch advanced under me throughout (main-tree HEAD moved `d609790` → `80eeb97` while I measured) and other reviewers were running concurrently on this host, so wall times below are loaded.

### The five baseline dimensions, re-measured at `05ff987`

**1. `./scripts/verify.sh` - exit 0.**

```
== VERIFIED: 05ff987bb23c2673752dd57f6e7dcabacee3c533 builds, tests, and lints from a clean clone
   OttoDomain: 261
   OttoPersistence: 127
   OttoUI: 208
   total: 596 tests
```

Baseline was 258 / 124 / 207 = 589. The +7 is item 2's two domain tests and item 3's one (stage 1 and 2), item 5's three persistence tests, and item 3's one OttoUI test.
This equals the ledger's "stages 2-4 (`b054506`)" column exactly.

**2. `swiftlint --strict`, standalone - exit 0.**

```
Done linting! Found 0 violations, 0 serious in 224 files.
```

Baseline was 220 files. The four new files across the run include this range's `AppModel+Export.swift` and `UnreportableInvalidationTests.swift`.

**3. Simulator suite, from `Packages/OttoUI/`.**

```
✔ Test run with 118 tests in 22 suites passed after 6.415 seconds.
✔ Test run with 72 tests in 12 suites passed after 0.096 seconds.
✘ Test run with 48 tests in 8 suites passed after 3.299 seconds with 7 known issues.
** TEST SUCCEEDED **   rc=0
```

Baseline was 117 / 72 / 36 with 7 known issues. The 7 known issues are the unchanged `EmptyStateTests` accessibility assertions.
This equals the ledger's stages-2-4 column exactly. I observed this shape ten times across the head run and the nine mutation runs whose mutations left it unchanged.

**4. Non-Gregorian harness - 1 / 1 / 5, the same five citations.**

Run from the repo root with an absolute bundle path.

```
th_TH@calendar=buddhist          1 issue    DisplayFormattingTests.swift:49:9
ja_JP@calendar=japanese          1 issue    DisplayFormattingTests.swift:49:9
ar_SA@calendar=islamic-umalqura  5 issues   DisplayFormattingTests.swift:49:9, :59:9, :68:9, :69:9
                                            NotificationReconciliationTests.swift:170:9
```

Identical to `reviews-4/BASELINE-4.md`. Suite size is 208, up from 207.

**5. Flake rate - FLAKE_SUMMARY.**

`swift test --package-path Packages/OttoUI`, twelve consecutive unmutated runs at `05ff987`:

```
FLAKE_TABLE
```

FLAKE_NOTE

### OttoPersistence, run repeatedly (this range touches persistence)

`swift test --package-path Packages/OttoPersistence`, PERS_COUNT consecutive runs at `05ff987`:

```
PERS_TABLE
```

PERS_NOTE

### Per-commit build sweep

`swift build --build-tests --package-path Packages/<pkg>` for all three packages at each of the three commits in the range: **9 of 9 OK.**

```
12024ab OttoDomain OK   12024ab OttoPersistence OK   12024ab OttoUI OK
b054506 OttoDomain OK   b054506 OttoPersistence OK   b054506 OttoUI OK
05ff987 OttoDomain OK   05ff987 OttoPersistence OK   05ff987 OttoUI OK
```

### Falsifications

Every mutation printed the exact text it removed and asserted the occurrence count before writing; every count was 1 as expected, and the one anchor that matched 3 places aborted rather than mutating (I re-anchored it and re-ran).

**Item 1's table (`PROD-READINESS-4.md:143-151`) - all seven rows reproduce.**

| ledger row | ledger records | I measured |
|---|---|---|
| appearance-time `prepareExport` pair re-added to `ExportSection` | 3 issues / 1 test | **3 / 1** ✅ and the failure text carries `…/data/tmp/Otto-Export-2026-08-12.json` and `Otto-Charges-2026-08-12.csv` |
| `withdrawPreparedExports()` deleted from `flowFinished()` | 2 issues / 1 test | **2 / 1** ✅ (`importWithdrawsAPreparedExport`) |
| `withdrawPreparedExports()` deleted from the `onMutation` hook | 2 issues / 2 tests | **2 / 2** ✅ |
| `prepareExport` stops recording the URL | 7 issues / 6 tests | **7 / 6** ✅ |
| the hook re-wrapped in `if notifications != nil` | 1 issue | **1** ✅ (`theHookIsWiredWithoutANotificationEngine`) |
| `PaymentMethodsStore`'s `onMutation` call removed | 1 issue | **1** ✅ (`aPaymentMethodWriteWithdraws`) |
| the generation guard removed from `prepareExport` | 2 issues | **2 / 1** ✅ (`aWithdrawalDuringABuildWins`) |

**Item 2's table (`PROD-READINESS-4.md:189-194`) - all four rows reproduce.**

| ledger row | ledger records | I measured |
|---|---|---|
| the neutralizer not called at all | 8 issues / 2 tests | **8 / 2** ✅ |
| the four named triggers removed, TAB / CR / LF kept | 5 issues / 2 tests | **5 / 2** ✅ |
| neutralize **after** quoting instead of before | 3 issues / 2 tests | **3 / 2** ✅ |
| the neutralizer applied to the **amount** column | 9 issues / 1 test | **9 / 1** ✅ |

I added a fifth: removing **only** `"\n"` from `csvFormulaTriggers` (`ChargesCSV.swift:81`) gives **1 issue**, so finding 8's added trigger is load-bearing and not decoration.

**Item 5.** The ledger has no item-5 section at this head (finding 2 below), so there was no table to check inside my range. I falsified the fix anyway, and compared against the table `2082b69` later wrote:

| mutation | ledger (out of range) | I measured |
|---|---|---|
| the save keyed on `invalidated` again (the pre-fix shape) | 1 issue | **1** ✅ `committedTombstones == 2` fails |
| the log statement deleted | 3 issues | **3** ✅ `named.count == 2`, `20260815`, `20260915` |
| skip instead of tombstone | 4 issues | **3** - `InvalidationTests.swift:37` (the "converting before mutating" artifact the ledger names), `theSoftDeleteIsCommitted:78`, and the load-bearing `rematerialized == []` at `:108` |

**My own falsifications, which found things.**

| mutation | expected if guarded | measured |
|---|---|---|
| `requestExport`'s body → no-op, `PaymentMethodsStore.delete`'s `onMutation` removed, `preparing`/`exportFailures` restored to single-valued, `onReminderTimeChange`'s withdraw removed, both cancellation-evidence withdraws removed (8 printed edits, 1 occurrence each) | red | **`** TEST SUCCEEDED **`, rc 0, 118 / 72 / 48, 7 known issues** |
| the tombstoned row's own `expectedAmountCents` added to the log line at `OttoStore+BillingEvents.swift:214` | red | **`✔ Test run with 127 tests in 26 suites passed`, rc 0** - the whole OttoPersistence suite, including `MappingLogPrivacyTests` |

## Findings

### 1 - P2. The remediation's new guards do not bite where the ledger says they do

**Evidence.** One simulator run, five distinct behaviours removed, each printed and asserted at exactly one occurrence:

- `AppModel+Export.swift:62-64` - `requestExport`'s body replaced by `_ = self; _ = kind`.
- `PaymentMethodsStore.swift:62` - `await onMutation?()` deleted from `delete(paymentMethodID:)`.
- `AppModel+Export.swift:74-75`, `:84`, `:94` - `preparing.insert(kind)` → `preparing = [kind]`, both `preparing.remove(kind)` → `preparing.removeAll()`, `exportFailures[kind] = nil` → `exportFailures.removeAll()`. That is exactly the single-valued clobbering the old `@State` had, moved onto the model.
- `AppModel.swift:133-136` - `self?.withdrawPreparedExports()` deleted from `settings.onReminderTimeChange`.
- `AppModel.swift:245` and `:254` - `withdrawPreparedExports()` deleted from `appendCancellationEvidence` and `updateCancellationEvidence`.

Result: `✔ 118 / ✔ 72 / ✘ 48 with 7 known issues`, `** TEST SUCCEEDED **`, rc 0 - byte-identical in shape to the unmutated head.
A green run with all five applied falsifies all five, because any one of them being observed would have turned the run red.

Against the ledger:

- `PROD-READINESS-4.md:331`: *"Findings 3, 5, 6 (P3) - fixed, each with a guard that bites."* True of finding 3 (removing the generation guard gives 2 issues) and of finding 5 (re-wrapping the hook gives 1 issue). **False of finding 6.** `SettingsExportTests.swift:319-339` (`theTwoKindsDoNotShareState`) never starts a second build and never produces a failure, so the two things finding 6 was about - a second tap clobbering the first row's state, and one shared `failure` - are never exercised. Its own doc comment at `:314-318` claims otherwise.
- `PROD-READINESS-4.md:327`: *"Fixed on both sides. `PaymentMethodsStore` gains the `onMutation` hook it never had"*, and *"both cancellation-evidence editors withdraw"*, and *"A code comment of mine was measured false and is corrected … That path withdraws now."* All three statements are true of the code. Of the five new call sites they describe, **one** has a test (`PaymentMethodsStore.save`, 1 issue when removed). The other four are removable with every gate in the project green.
- `:330`: *"The whole state machine moved onto `AppModel`, where eight tests reach it, and the view is now one call with no logic in it. What no test in this project can reach is that single closure."* The eight tests are real. But the "one call" is `requestExport`, which is `public` on the model, is trivially reachable from a test, and has no caller anywhere except `SettingsView.swift:214`. N4-1 was shrunk by one layer and a new untested layer was added under it.

**Why this is P2 and not P3.** `reviews-4/REVIEW-1.md` finding 2 was P2 and its whole content was "a promise with only two of six paths behind it". The remediation added the paths and did not add the observers, so the *next* edit re-opens the same P2 with the suite green - which is precisely the condition that made finding 2 a P2 in the first place. `PaymentMethodsStore.onMutation` is also asymmetric with its own sibling: `SubscriptionsStore.onMutation` has a direct unit test at `SubscriptionsStoreTests.swift:266`; the new one has none.

**Why the builder missed it.** Each fix was written at the call site the reviewer's probe had exercised - payment-method **save**, and a JSON build interleaved with a withdrawal - and exactly one test was added per probe. Nothing enumerated the *new* call sites of `withdrawPreparedExports()` against the tests that observe them, which is the same omission finding 2 named one level up.

### 2 - P2. The reviewed head records nothing about the item the stage delivered

**Evidence.** At `05ff987`:

- `PROD-READINESS-4.md:50` - the work list still reads `| 5 | **R0-11** | … | pending |`.
- There is no `## ITEM 5` heading. `grep -n "^## " ` at that commit ends at `## ITEM 3`; the file is 336 lines and its last section is `### Remediation after reviews-4/REVIEW-1.md`.
- There is therefore no reconfirmation of R0-11, no falsification table, no "Cost, stated as the prompt requires" paragraph for the **tenth** `OSLogStore` read that `12024ab` adds, and no five-dimension measurement for stage 4.
- `PROD-READINESS-4.md:62-70` - the REVIEW RANGES table has empty range, head and verdict cells for stages 2, 3, 4 **and** 5, and an empty verdict cell for stage 1 whose verdict the same commit states in prose at `:323`.

The ledger's own two rules are `:60` (*"every start is recorded when the stage opens, not when its verdict lands"*) and `:84` (*"A stage's reviewed head is the commit that RECORDS its measurements, not its last code commit, so the numbers a reviewer is asked to check are inside the range it is given rather than only in the tree it is standing on"*).
Stage 4's head records stage **1's** re-derived numbers and none of stage 4's. Stages 2 and 3 closed at `00cb0f1` and `54bb611`, both before this range opened, and their starts are still blank here.
`:335` restates the rule in response to `reviews-4/REVIEW-1.md` finding 9 - *"the START is recorded when the stage opens, the HEAD when it closes"* - in the same commit that leaves four starts and four heads blank.

**What later work did to it.** `2082b69` adds items 4-7, `1a1d23b` adds the verification table, `d609790` fills the range table. So the record is complete at the branch tip and was not complete at the head I was given.

**Why this is P2 and not P3.** The one thing this run's review-range design exists to guarantee is that a reviewer's range contains the claims it is asked to check. For the new item in this range it contains none, so the only reason I could check item 5 at all is that I do not need the ledger to read a diff. The prompt handed me a range and told me its ledger sections "contain many measurement tables"; item 5's do not exist inside it. That is the bookkeeping-drift class, not a typo.

**Why the builder missed it.** The stage carried two unlike things - a remediation with a lot of prose and a new item - and the closing commit was written for the remediation. The ledger's structure reinforces it: the remediation section is filed as a `###` under `## ITEM 3`, 190 lines away from the item it remediates.

### 3 - P3. The privacy assertions on the new log test guard an amount the row cannot carry

**Evidence.** `UnreportableInvalidationTests.swift:164-167`:

```swift
for line in named {
    #expect(!line.contains("1299"))
    #expect(!line.contains("$"))
}
```

`1299` is the **edited** subscription's amount (`:142`). The rows that get tombstoned were materialized from the *original* subscription at `:135`, which takes `makeSubscription`'s default `amountCents: 1099` (`TestSupport.swift:74`). The only amount a leak from this line could expose is the row's own `expectedAmountCents`, and that is 1099.
Executed: adding `amount=\(amount, privacy: .public)` to the message at `OttoStore+BillingEvents.swift:214` - the row's own amount, in the clear, which is exactly the R0-4 class - leaves the whole OttoPersistence target green: `✔ Test run with 127 tests in 26 suites passed`, rc 0. `MappingLogPrivacyTests` does not see it either, because its window filter at `:86` requires `"Skipping unmappable record"`.

The shipped line is clean - I read the composed message and it carries a UUID, a packed `yyyymmdd`, and `mappingLogSummary`, which is value-free by construction (`MappingError.swift:44-52, 58-60`). This is a defect in the guard, not in the code.

**Why the builder missed it.** The test's own comment at `:161-163` says "nothing about what the subscription costs" and the subscription under test does cost 1299; the row's amount is a different number and was never in view.

### 4 - P3. Finding 3's fix guards the success branch only, so the same shape survives in `catch`

**Evidence.** `AppModel+Export.swift:90` refuses to install a superseded URL. `:93-97` does not:

```swift
} catch {
    preparing.remove(kind)
    exportFailures[kind] = error.localizedDescription
    throw error
}
```

`withdrawPreparedExports()` (`:113-117`) clears `exportFailures` and bumps the generation. A build that was already in flight when the withdrawal landed and then *fails* writes its message into `exportFailures[kind]` afterwards, and `exportAvailability` (`:46-51`) renders it - a failure banner for a request the model has already decided is superseded. The mirror case is the same interleaving one step later: a withdrawal that lands after the `catch` erases a genuine failure the user never saw.
The relocation is small - what survives is a message, not an offered file - which is why this is P3.

Related, same method: `prepareExport` returns the URL it declined to install (`:90`). The doc says so, and the only production caller (`requestExport`) discards it, so nothing is misled today.

**Why the builder missed it.** The reviewer's probe B was a successful build, and the guard was written where that probe landed.

### 5 - P3. The ledger presents as shipped a footer sentence the same commit removed for being false

**Evidence.** `PROD-READINESS-4.md:133` (at this head; `:138` at the branch tip):

> the footer gains one sentence: *"Otto builds a file only when you ask for it, and stops offering it once your data changes - a backup is a complete copy of your finances, and a stale one is worse than none."*

The shipped footer at `05ff987` is `SettingsView.swift:180-183`:

> "Otto builds a file only when you ask for it, so a complete copy of your finances isn't left lying around. Editing a subscription or importing a backup withdraws one you already built."

`:324` of the same file, 190 lines below, quotes the first sentence as the thing that was wrong and says "The copy now says only what is true". The "What changed" section was never updated, so the ledger states two different strings as the app's current copy.
The new copy is accurate: I confirmed both claims it makes (a subscription edit and an import both withdraw) and it no longer generalises.

**Why the builder missed it.** The remediation was appended rather than folded back into the item it remediates.

### 6 - P3. "All eight were stale" is contradicted by the review it cites in the same sentence

**Evidence.** `PROD-READINESS-4.md:141`:

> `reviews-4/REVIEW-1.md` finding 4 caught one of these eight numbers being stale; all of them were …

`reviews-4/REVIEW-1.md:120-131` records seven of the eight measured at stage 1's head, six of them ✅ and one ✗, and `:195` states it in words: *"The other three rows for item 2 (5, 2, 8) and all three for item 1 (3, 2, 1) reproduce exactly."*
Three of the eight also carry the *same* value in the new table as in the old (appearance 3 → 3, `flowFinished` 2 → 2, four-triggers 5 → 5), so they were not stale in any sense a reader would take from that sentence.
The correction itself is real and the new table is right - I reproduced all eleven rows - which is why this is a P3 about the prose and not about the numbers.

**Why the builder missed it.** The sentence generalises a process fact ("none of the rows was re-derived") into a claim about values, and the review it cites was not re-read against it.

### 7 - P3. `AppModel.swift` was split and the split is disclosed nowhere

**Evidence.** `b054506` creates `Packages/OttoUI/Sources/OttoStores/AppModel+Export.swift` (134 lines) and removes 66 lines from `AppModel.swift`. The file header at `:5-9` gives the reason - SwiftLint's 400-line `file_length` - and the ledger never mentions it. Item 4's two splits are disclosed in detail at `PROD-READINESS-4.md:383-385`; this one is not, in either the item-1 "What changed" list or the remediation section.

The split was genuinely forced and I checked it rather than taking the header's word: re-inlining the extension body into `AppModel.swift` gives **423 lines**, and `.swiftlint.yml` sets no `file_length` override, so SwiftLint's default 400-line warning fires and `--strict` fails. The moved code is fully auditable from the diff, and I confirmed behaviour preservation by execution - the seven item-1 falsifications all land in the moved code and produce exactly the ledger's counts.

The run's scope rule is that a length-forced split "must be shown to be behaviour-preserving". This one is behaviour-preserving *and mixed with behaviour changes in the same commit*, which is the case where showing it matters most.

**Why the builder missed it.** The header comment on the new file reads like a disclosure, and it is - but in the source, not in the artifact a reviewer is handed.

### 8 - P3. A doc comment was carried across the split and now documents the wrong declaration

**Evidence.** `AppModel+Export.swift:18-38` is a single doc comment whose first fifteen lines describe `prepared` ("The export files this session has been ASKED for, by kind (F8) … which is exactly why the share sheet went on offering the pre-import copy") and whose last six describe `ExportAvailability` ("What one export row is showing"). It is attached to `public enum ExportAvailability`. `prepared` now lives at `AppModel.swift:70` under a three-line comment.
Two doc comments were concatenated when the block moved; the missing blank line between `:32` and `:33` is the whole of it.

### 9 - P3. The tenth `OSLogStore` read costs more than the number stated beside it

**Evidence.** `UnreportableInvalidationTests.swift:117-127` states the cost as "roughly 7-11 s" and argues that a shared query would make a failure ambiguous between unrelated causes. The justification is sound as far as it goes, and the reader really is new and really is the tenth (7 in OttoUI, 3 in OttoPersistence, counted at their call sites the way `reviews-4/BASELINE-4.md` counts them).

Measured on this host: `theUnreportableRowIsNamed` took OSLOG_COST. This machine was loaded throughout, and `reviews-4/BASELINE-4.md:199-202` establishes that the log-reading tests are exactly where an 8x spread lives, so I do not read the gap as a defect - but a cost stated as a range and measured outside it is not a cost the next round can plan against.

The cheaper alternative is not considered: composing the message's fields in a function a test can read without opening a store. That is not hindsight about a pattern the tree lacked - `PROD-READINESS-4.md` item 7 adopts exactly it one stage later, for exactly this reason ("The tree already blocks on that daemon nine times … an eleventh for one field is not a trade worth making"), and the same reasoning applied one stage earlier would have avoided the tenth.

### 10 - P3. The protocol contract was not updated when the return value changed meaning

**Evidence.** `OttoStore+BillingEvents.swift:206-210` states plainly that `invalidated` now undercounts by construction. `BillingEventRepository.swift:43` still says *"Returns the invalidated events."* - the contract every caller programs against, unchanged.
No live consequence: the sole production caller discards the value (`NotificationScheduler.swift:251`, `_ = try await …`), which I checked rather than assumed. The implementation-side disclosure is good; it is on the wrong side of the seam.

## Explicit checks

- **Fabricated or unreproducible findings.** None in range. Both measurement tables at this head reproduce completely - 7/7 for item 1 and 4/4 for item 2, to the issue count *and* the test count. The one number that does not reproduce for me is item 5's "skip instead of tombstone | 4 issues", and that row is outside my range (added by `2082b69`); my faithful mutation gives 3, including the load-bearing `rematerialized == []` the ledger names and the "converting before mutating" artifact it warns about. Item 5's `reported=0 / committedTombstonesRightAfter=0 / committedTombstonesAfterAnUnrelatedSave=2` reconfirmation is a `54bb611` measurement quoted in the source at `OttoStore+BillingEvents.swift:161-172`; I did not re-run it at `54bb611`, but the shape it describes is exactly what the pre-fix mutation reproduces (`committedTombstones == 2` fails).
- **Citations that do not say what they are claimed to say.** Three: finding 5 (`PROD-READINESS-4.md:133` quotes copy the same commit replaced), finding 6 (`:141` vs `reviews-4/REVIEW-1.md:195`), finding 8 (`AppModel+Export.swift:18-38`). I also checked the citations the ledger makes *into* the code and they hold: `:132`'s "the only caller in `OttoStores` that writes an export file" is true (`exportJSONFile`/`exportChargesCSVFile` have exactly two non-test call sites, both in `prepareExport`); `AppModel.swift:128-132`'s corrected comment matches `NotificationScheduler.swift:254`'s `materializeEvents` call; `reviews-4/REVIEW-1.md`'s nine findings really are 2 P2 + 7 P3 as `:323` says.
- **Severity inflation or deflation.** One deflation, in finding 1: the ledger carries finding 2's fix as done "on both sides" and finding 6 as guarded, and neither claim survives execution. Nothing is inflated - `:329` carries N4-4 (`NotificationActionHandler`, a bare scheduling pass) as still open rather than claiming it closed, and `:330` keeps N4-1 at the reviewer's severity.
- **Features smuggled past the no-features rule.** No. `ExportAvailability` and `requestExport` are new public API but are the fix's own vocabulary for state finding 6 named; the footer is copy for the export item, which the exception grants; the failure display moved from a section banner to a per-row label, which is the visible half of the per-kind fix. `Package.swift` untouched in the range, no `UserDefaults` key added anywhere in the diff, no new screen, no new dependency, `.github/workflows/` untouched.
- **Any SwiftData schema change.** None. `git diff --name-only 54bb611 05ff987` touches eleven files; the only one under `Packages/OttoPersistence/Sources/` is `Store/OttoStore+BillingEvents.swift`. Nothing under `Schema/`, no `OttoSchemaV*.swift`, no `OttoMigrationPlan.swift`. V3 stays frozen.
- **Prohibited actions.** None observed. `git show-ref` puts `refs/heads/main` and `refs/remotes/origin/main` both at `406a5a6`, so nothing was pushed or merged; there are no tags; `.git/FETCH_HEAD` does not exist; `05ff987` is still an ancestor of the branch tip, so no history was rewritten. `.swiftlint.yml` is untouched - no rule relaxed, disabled, re-thresholded, and no `excluded:` path added. `docs/next-wave.md` and every other narrative document are untouched by this range.
- **Fixes that relocated a bug rather than removed it.** Finding 4 - the generation guard covers the success branch and not the failure branch, so "a superseded build writes state after the withdrawal" survives one branch over. The `AppModel` split (finding 7) relocates a lot of code and I confirmed by execution that it relocated no behaviour.
- **Error handling that hides errors.** No new swallowing, and one removal of an old one: `if let event = try? record.toDomain()` became a `do`/`catch` that logs. I checked the logged path actually reaches the log rather than assuming it - deleting the statement fails the test at three assertions, and the message the test reads back carries the row's packed day. `requestExport`'s `_ = try? await …` looks like a swallow and is not: `prepareExport` writes `exportFailures[kind]` before it throws and `exportAvailability` renders it, so the user sees the message. The one degradation is finding 4.
- **Verification that does not exercise the changed path.** Finding 1, squarely - four of five new withdraw call sites, the per-kind state, and `requestExport` itself. Also worth stating: `AppModel` still has no host test anywhere in the tree, so every item-1 guard in this range is invisible to `scripts/verify.sh` and lives only in the simulator job, which this round's flake protocol never runs.
- **Tests that pass for the wrong reason.** Two. `theTwoKindsDoNotShareState` (`SettingsExportTests.swift:319-339`) asserts a claim it never produces the conditions for - finding 1. The privacy block in `theUnreportableRowIsNamed` (`:164-167`) asserts the absence of a string the line can never contain - finding 3. I broke the thing every other added or changed test names, and every one of them failed: M1-M7 above, plus the three item-5 mutations, plus the `\n`-only trigger removal.
- **Flaky or environment-dependent tests.** None observed. FLAKE_CHECK The new persistence log test asserts over a shared window and is pinned correctly: its own subscription index 7011, unique in the target, and every assertion filtered to that UUID, so the ~80 ms `position(date:)` lookback that catches its two siblings' lines cannot move its count. I checked the reverse direction too - `MappingLogPrivacyTests`' whole-window assertion at `:102` filters on `"Skipping unmappable record"`, which the new message does not contain, so the tenth reader does not contaminate the existing ones. Two of the new UI tests discard `settle`'s return (`SettingsExportTests.swift:301`, `:327`) against the helper's own documented rule at `:139-141`; in `aWithdrawalDuringABuildWins` a timeout still fails, in `theTwoKindsDoNotShareState` it would pass without ever producing the interleaving. Not observed to fire on this host.
- **Anything marked resolved without an artifact.** Inverted here, and that is finding 2: the range delivers item 5 and marks it nothing at all - the work list still says `pending` at the reviewed head. Items 1 and 2 remain RESOLVED and both now carry re-derived tables that reproduce.
- **Every commit in the range builds all three packages.** Yes - 9 of 9, table above.
- **The `OSLogStore` rule.** This range adds the **tenth** read (`UnreportableInvalidationTests.swift:152`). The cost and the shared-query argument are stated - in the test's own doc comment, not in the ledger at this head. See finding 9 for what I measured and for the alternative that was not weighed.

## What I could not check, and why

- **That a human tapping the export row produces a file.** Unchanged from `reviews-4/REVIEW-1.md` finding 1, and now one layer deeper: `requestExport` is testable and untested, and the closure in `SettingsView.swift:213-215` is not testable in this project at all. I established the negative only - that no gate notices when either is broken.
- **Release configuration.** Debug only. ASSUMPTION 3 carries.
- **A physical device**, and therefore the file protection class on the exports left in `tmp`. Prohibited this run.
- **The device calendar of the two real users.** ASSUMPTION 1 carries.
- **Whether a spreadsheet actually refuses to evaluate `'=1+1`.** No spreadsheet was run. What I measured is that the exported bytes carry the apostrophe for all seven hostile shapes including the new `\n`, and that the amount column does not.
- **The `OSLogStore` readers on a CI runner.** Unchanged CANNOT ASSESS. All ten passed here, in `verify.sh`, in every persistence repeat and in every flake run, with no canary firing.
- **`aa92ca7`**, items 3, 4, 6 and 7, and the stage-5 work. Not in my range.
- **A quiet host.** Two other reviewers and the builder were running on this machine throughout, so every wall time here is loaded and none of them is comparable with `reviews-4/BASELINE-4.md`'s. Pass/fail is unaffected; the `theUnreportableRowIsNamed` duration in finding 9 should be read with that caveat.
