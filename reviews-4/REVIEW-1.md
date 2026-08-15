# REVIEW-1 - round 4, stage 1 (items 1 + 2)

Range reviewed: `2d8913c..6ef51ee`.
Reviewed head: `6ef51ee`.
Ledger: `PROD-READINESS-4.md`. Baseline: `reviews-4/BASELINE-4.md`.

verdict: PASS-WITH-FINDINGS

## Summary

The two named defects are really gone and the guards that say so really bite.
I re-added an appearance-time export to `ExportSection` and the new appearance test failed with three issues and both files back in the simulator's `tmp`; I deleted the withdraw from `flowFinished()` and the import test failed with two; I deleted it from the `onMutation` hook and the delete test failed with one; I disabled the CSV neutralizer four different ways and the two new domain tests failed every time.
All five baseline dimensions are at or above `reviews-4/BASELINE-4.md`, every commit in the range builds all three packages, and the stage touched no schema file, no lint rule, no workflow, no dependency and no existing assertion.

What is not sound is the size of the claim relative to the size of the evidence, in three places.

First, the stage replaced an automatic behaviour with a manual one and nothing in the tree checks that the manual one works.
Deleting the sole call from the new Button to `AppModel.prepareExport(_:)` leaves the entire simulator suite green.
The ledger discloses a weaker version of this as N4-1; the stronger statement is that no artifact in this run shows a user producing an export at all after the change, and the failure mode of a mis-wired button is that backups become impossible rather than merely stale.

Second, the fix is described - and, more seriously, is described *to the user in the app* - as "stops offering it once your data changes", and it does not.
`withdrawPreparedExports()` is reachable from two of at least six paths that change data that the export contains.
I demonstrated by execution that saving a payment method leaves the stale JSON backup on offer, and the code comment that excuses the reminder-time path ("It changes no record") is contradicted by `AppModel`'s own doc comment 190 lines below it.

Third, one recorded falsification count does not reproduce: item 2's "neutralizer not called at all" row records 5 issues and produces 7.
The other six falsification rows across both items reproduce exactly.

None of this is a regression against baseline and none of it is fabricated evidence, which is why this is not a reject.
The two P2 findings should be carried rather than closed with the items.

## What I ran

All mutation work was done in two detached worktrees under a temp path I created; both are removed and `git worktree list` shows only `/Users/<user>/dev/otto`.
I made no commit, ran no network command, touched no physical device, and did not modify the main working tree - which had uncommitted builder work in it throughout, and still does.

### The five baseline dimensions, re-measured at `6ef51ee`

**1. `./scripts/verify.sh` - exit 0.**

```
== VERIFIED: 6ef51ee3cfa2dffd9badb5eabedd63d70296c9ef builds, tests, and lints from a clean clone
   OttoDomain: 260
   OttoPersistence: 124
   OttoUI: 207
   total: 591 tests
```

Baseline was 258 / 124 / 207 = 589. The +2 is item 2's two domain tests, as the ledger states.

**2. `swiftlint --strict`, standalone.**

```
Done linting! Found 0 violations, 0 serious in 221 files.
```

Baseline was 220 files. The new file is `SettingsExportTests.swift`.

**3. Simulator suite, from `Packages/OttoUI/`, three consecutive runs.**

```
run 1  ✔ 117 in 22 suites  ✔ 72 in 12 suites  ✘ 40 in 8 suites passed with 7 known issues   ** TEST SUCCEEDED **  rc=0
run 2  ✔ 117 in 22 suites  ✔ 72 in 12 suites  ✘ 40 in 8 suites passed with 7 known issues   ** TEST SUCCEEDED **  rc=0
run 3  ✔ 117 in 22 suites  ✔ 72 in 12 suites  ✘ 40 in 8 suites passed with 7 known issues   ** TEST SUCCEEDED **  rc=0
```

Baseline was 117 / 72 / 36 with 7 known issues. The +4 is item 1's four tests. The 7 known issues are the unchanged `EmptyStateTests` accessibility assertions.
I ran it three times rather than once because the flake protocol covers only `swift test`, and item 1's entire regression guard lives in a suite that protocol never executes.
`appearanceWritesNothing` also passed in the two mutation runs where it was not the mutated subject, so it is 5 for 5 on this host.

**4. Non-Gregorian harness - 1 / 1 / 5, same five citations.**

Run from the repo root with an absolute bundle path.

```
th_TH@calendar=buddhist            1 issue
  DisplayFormattingTests.swift:49:9   ("Aug 15, 2569 BE") == "Aug 15, 2026"
ja_JP@calendar=japanese            1 issue
  DisplayFormattingTests.swift:49:9   ("Aug 15, Reiwa 8") == "Aug 15, 2026"
ar_SA@calendar=islamic-umalqura    5 issues
  NotificationReconciliationTests.swift:170:9  ("FoodApp charges $15.99 on Rab. I 12.") == "… on Aug 25."
  DisplayFormattingTests.swift:59:9   ("Every ٤٥ days") == "Every 45 days"
  DisplayFormattingTests.swift:49:9   ("Rab. I 2, 1448 AH") == "Aug 15, 2026"
  DisplayFormattingTests.swift:68:9   ("١ subscription") == "1 subscription"
  DisplayFormattingTests.swift:69:9   ("٣ subscriptions") == "3 subscriptions"
```

Identical to `reviews-4/BASELINE-4.md`.

**5. Flake rate - 12 of 12.**

`swift test --package-path Packages/OttoUI`, twelve consecutive unmutated runs at `6ef51ee`:

```
run  1 rc=0 207 tests passed after 17.190 s      run  7 rc=0 ... 14.768 s
run  2 rc=0 ...              13.207 s            run  8 rc=0 ... 13.603 s
run  3 rc=0 ...              13.973 s            run  9 rc=0 ... 13.955 s
run  4 rc=0 ...              18.985 s            run 10 rc=0 ... 15.150 s
run  5 rc=0 ...              12.585 s            run 11 rc=0 ... 23.802 s
run  6 rc=0 ...              23.039 s            run 12 rc=0 ... 15.709 s
SUMMARY pass=12 fail=0
```

Spread 12.6 s - 23.8 s, narrower than the batch either the baseline or the ledger observed; the ledger's stated 13.9 s - 16.4 s window does not reproduce, which is the known host property and not a finding.

### Per-commit build sweep

`swift build --build-tests --package-path Packages/<pkg>` for OttoDomain, OttoPersistence and OttoUI at each of the four commits in the range: **12 of 12 OK**.

```
b2bd5bd OttoDomain OK   b2bd5bd OttoPersistence OK   b2bd5bd OttoUI OK
f1237cc OttoDomain OK   f1237cc OttoPersistence OK   f1237cc OttoUI OK
a412a07 OttoDomain OK   a412a07 OttoPersistence OK   a412a07 OttoUI OK
6ef51ee OttoDomain OK   6ef51ee OttoPersistence OK   6ef51ee OttoUI OK
```

### Falsifications

Each printed the exact text it removed and asserted exactly one occurrence in the file before mutating.

| mutation | ledger records | I measured |
|---|---|---|
| `csvField` body → `rfc4180Quoted(value)` (neutralizer off) | 5 issues / 2 tests | **7 issues / 2 tests** |
| `csvFormulaTriggers` → `["\t", "\r"]` (four named triggers dropped) | 5 issues / 2 tests | 5 issues / 2 tests ✅ |
| `withoutLeadingFormula(rfc4180Quoted(value))` (composed the other way) | 2 issues | 2 issues / 2 tests ✅ |
| `csvField(decimalAmount(cents: event.expectedAmountCents))` (the control) | 8 issues | 8 issues / 1 test ✅ |
| `.task { prepareExport(.json); prepareExport(.chargesCSV) }` re-added to `ExportSection` | 3 issues, files back in `tmp` | 3 issues, and the failure text carries `…/data/tmp/Otto-Export-2026-08-12.json` and `Otto-Charges-2026-08-12.csv` ✅ |
| `withdrawPreparedExports()` deleted from `flowFinished()` | 2 issues | 2 issues, `importWithdrawsAPreparedExport` ✅ |
| `self?.withdrawPreparedExports()` deleted from the `onMutation` hook | 1 issue | 1 real issue (8 total incl. the 7 known) ✅ |
| **`prepare(kind)` deleted from the export `Button`'s action** | not attempted | **suite GREEN, `** TEST SUCCEEDED **`, rc=0** |
| **`onMutation` assignment re-wrapped in `if notifications != nil`** | not attempted | **suite GREEN, `** TEST SUCCEEDED **`, rc=0** |

The last two were applied together in one run; they touch disjoint tests, so a green run falsifies both.

### Probes I wrote against `AppModel` (host, `OttoStoresTests`, deleted with my worktree)

```
✘ PROBE A: saving a payment method leaves a prepared export offered
    model.preparedExport(.json) → file:///…/T/Otto-Export-2026-08-06.json   (expected nil)
✘ PROBE B: a withdraw during an in-flight prepare is overwritten when it lands
    model.preparedExport(.json) → file:///…/T/Otto-Export-2026-08-06.json   (expected nil)
```

## Findings

### 1 - P2. The export Button's wiring is verified by nothing, and it is now the only way to get an export

**Evidence.** `Packages/OttoUI/Sources/OttoUI/SettingsView.swift:205-207` is the sole path from a tap to `AppModel.prepareExport(_:)`.
Replacing `prepare(kind)` at `:206` with `_ = kind` - one occurrence, printed before mutating - and running the full simulator suite from `Packages/OttoUI/` gives `** TEST SUCCEEDED **`, rc 0, 117 / 72 / 40, the same 7 known issues, byte-identical in shape to the unmutated head.
All four new tests reach the model directly (`SettingsExportTests.swift:170`, `:196`, `:218-219`) or assert an absence; none renders a row and activates it.
`PROD-READINESS-4.md:148` records this as N4-1 but scopes it to "a future edit that routes the button somewhere else would not fail".

**Why this is P2 and not P3.** Before this stage the export was produced unconditionally, so a broken affordance was impossible. After it, a tap that does not reach `prepareExport` means the user can never produce a backup - the loss is the whole feature, not a stale copy - and every gate in the project stays green through it.
The ledger records no app launch, no Release build (ASSUMPTION 3), and no manual check of the new rows.
The scope exception was granted for exactly this navigation; taking it moved the feature's correctness into the one layer this run does not test.

**Why the builder missed it.** The defect being fixed lived at the model boundary, so the evidence was gathered there. The Button was treated as the permitted cost of the fix rather than as new behaviour that needs its own observer.

### 2 - P2. "Stops offering it once your data changes" is shipped to the user and is not true of at least four paths

**Evidence.** The new footer at `SettingsView.swift:187-189` tells the user: *"Otto builds a file only when you ask for it, and stops offering it once your data changes."*
`withdrawPreparedExports()` is called from exactly two places: `AppModel.swift:122` (`flowFinished()`) and `AppModel.swift:103` (`subscriptionsStore.onMutation`).

Uncovered paths that change data the export contains:

- **Payment methods.** `PaymentMethodsStore.save` and `.delete` (`PaymentMethodsStore.swift:33`, `:49`) have no mutation hook, and `paymentMethods` is a stored field of `OttoDataSnapshot` (`OttoDataSnapshot.swift:9`) and therefore of the JSON backup. Demonstrated by execution - PROBE A above: after `prepareExport(.json)`, a `paymentMethodsStore.save(...)` leaves `preparedExport(.json)` pointing at the pre-change file.
- **Cancellation evidence.** `AppModel.appendCancellationEvidence` (`:214`) and `updateCancellationEvidence` (`:222`) call only `subscriptionsStore.refresh()`, never `flowFinished()`. `evidenceNotes` is encoded in the export (`CancellationEpisode.swift:348`).
- **Notification actions.** The composition root builds `NotificationActionHandler` over `model.flows` directly (`Otto/App/OttoApp.swift:62-70`); the handler writes state changes at `NotificationActionHandler.swift:130`, `:134`, `:142`, `:151`, `:159`, and the only thing that comes back to the model is `requestedSubscriptionID` (`OttoApp.swift:86-97`). No withdraw.
- **Any scheduler pass that materializes the ledger.** `NotificationScheduler.swift:254` calls `billingEvents.materializeEvents(...)`, which creates `BillingEvent` rows - rows the CSV prints as `expected`.

**The comment that excuses the last one is false.** `AppModel.swift:106-107` says *"A notification-time change re-times every pending reminder. It changes no record, so it does not withdraw an export."*
`settings.onReminderTimeChange` calls `notifications.reschedule()` → `NotificationScheduler.reschedule` → `materializeEvents`. `AppModel`'s own doc comment at `:299` says the reschedule "also materializes the imported subscriptions' ledgers".
`PROD-READINESS-4.md:150` repeats the claim as the sole entry under "What this does NOT do"; the other three paths are not disclosed anywhere.

**Scope.** The *named* defect - R0-10(b), the `ShareLink` handing out the pre-import file - is genuinely closed, and I confirmed the guard bites. This finding is about the generalisation, which is asserted in the ledger, in the code comments, and in the app.

**Why the builder missed it.** The two hooks chosen are the two the import path travels, and the import is the path the finding named. Nothing enumerated the writers of `OttoDataSnapshot`'s five collections against the callers of `withdrawPreparedExports()`.

### 3 - P3. A withdraw that lands during an in-flight prepare is overwritten - the same staleness, relocated

**Evidence.** `AppModel.prepareExport(_:)` (`AppModel.swift:270-279`) awaits the export actor and then writes `prepared[kind] = url` at `:277` with no check that a withdraw happened during the suspension.
`AppModel` is `@MainActor`, so a `flowFinished()` or `onMutation` withdraw is free to run while `prepareExport` is suspended, and the assignment afterwards re-offers a file built from the older snapshot.
Demonstrated by execution - PROBE B above, using a gated `DataTransferRepository`: withdraw while suspended, release, and `preparedExport(.json)` is non-nil.

Reachable in the app: Export and Import are rows in the same `SettingsView`, so a large JSON export started and an import completed during it produces exactly this interleaving.

**Why the builder missed it.** Every test awaits `prepareExport` to completion before mutating, so the ordering the defect needs is never produced.

### 4 - P3. One recorded falsification count does not reproduce

**Evidence.** `PROD-READINESS-4.md:182` records, for item 2, "the neutralizer not called at all | 5 issues over 2 tests".
Replacing `csvField`'s body at `ChargesCSV.swift:67` with `rfc4180Quoted(value)` - one occurrence, printed - gives **7 issues over 2 tests**: six iterations of `formulaInjectionIsNeutralized` (the six hostile entries of the eight in its dictionary) plus `neutralizingComposesWithQuoting`.
Five is the count that the *five-name* reproduction quoted at `PROD-READINESS-4.md:160-166` would produce; the shipped test carries eight entries, which the same table's fourth row confirms by recording 8 for the amount-column control - a number that is only reachable with eight entries.
So the row was recorded against an earlier draft of the test and not re-run.

The other three rows for item 2 (5, 2, 8) and all three for item 1 (3, 2, 1) reproduce exactly.

**Why the builder missed it.** The falsification table was written as the mutations were run and the test grew afterwards; nothing re-derives the table from the shipped tests.

### 5 - P3. The test that claims to pin the unconditional `onMutation` wiring does not pin it

**Evidence.** `SettingsExportTests.swift:184-186`: *"This also pins the hook itself: `subscriptionsStore.onMutation` used to be installed only inside `if let notifications`, so 'the data changed' was observable only on a model that could schedule reminders."*
Every model the suite builds passes a non-nil `NotificationStatusStore` (`SettingsExportTests.swift:92-94`), so the branch the claim is about is never taken.
Executed: re-wrapping the assignment at `AppModel.swift:101-104` in `if notifications != nil { … }` - reinstating exactly the old conditional - leaves the full simulator suite green, `** TEST SUCCEEDED **`, rc 0.
`PROD-READINESS-4.md:129` presents the unconditional wiring as part of the fix. No gate holds it.

**Why the builder missed it.** The behaviour the test *does* pin (a delete withdraws) is real, and the wiring change is invisible from a model that always has notifications - which is every model in the suite and the only model in production.

### 6 - P3. `preparing` cannot represent two exports at once, and clearing it is unconditional

**Evidence.** `SettingsView.swift:145` declares `@State private var preparing: ExportKind?` - single-valued - and `:196-210` selects the row by it.
Tap JSON then CSV before the first finishes: `prepare(.chargesCSV)` sets `preparing = .chargesCSV` at `:214`, so the JSON row falls to the `else` branch and becomes a live `Button` again while its task is still running, inviting a duplicate export.
When the JSON task finishes it sets `preparing = nil` at `:222` unconditionally, wiping the CSV row's in-flight state mid-build.
`failure = nil` at `:218` likewise clears a failure recorded for the other kind.

Not user-visible as data loss - the file names are stable and dated, so a duplicate overwrites itself - but the affordance the stage introduced misreports its own state.

**Why the builder missed it.** No test renders the rows at all (finding 1), so no state machine of the section is exercised.

### 7 - P3. "There is no second, unrecorded writer" is a convention, not a constraint

**Evidence.** `PROD-READINESS-4.md:130`: *"`prepareExport(_:)` is the only path that writes an export file, so there is no second, unrecorded writer for the defect to come back through."*
`ExportService.exportJSONFile` and `exportChargesCSVFile` are still `public` (`ExportService.swift:91`, `:107`) and `AppModel.exports` is a `public let` (`AppModel.swift:53`), so any view holding the model can write an export without recording it.
A grep of the tree confirms the sentence is true of the code that exists today - the only non-test callers are `AppModel.swift:273` and `:275` - but nothing makes it true of the code that comes next, which is what the sentence claims. `ExportService.swift:77-79` states the same thing in a doc comment.

**Why the builder missed it.** Removing the two `AppModel` wrappers really did remove the second *caller*; the claim then over-reached from "no second caller" to "no second path".

### 8 - P3. `\n` is not a formula trigger, on the code's own stated rationale

**Evidence.** `ChargesCSV.swift:79` lists `["=", "+", "-", "@", "\t", "\r"]`, and `:76-78` justifies tab and carriage return because *"several importers strip a leading one and then evaluate what is behind it."*
A leading newline has the same property and is absent. Reachability is low - the name comes from a single-line field - which is why this is P3 and not higher; it is recorded because the rule the comment states is not the rule the set implements.

### 9 - P3, process. The reviewed head I was handed is not the head the reviewed tree records

**Evidence.** At `6ef51ee`, `PROD-READINESS-4.md:65` says stage 1's range is `` `2d8913c..a412a07` `` with reviewed head `` `a412a07` ``.
The row was rewritten to `` `2d8913c..6ef51ee` `` in `abef4a7`, which is outside the range I was given, together with the paragraph that defines the new rule ("A stage's reviewed head is the commit that RECORDS its measurements").
The ledger's own rule at `:61` is that every start is "recorded when the stage opens, not when its verdict lands".
The consequence is benign - `abef4a7` is documentation-only and falls inside stage 2's range, and the range I was issued is the wider of the two - but the artifact under review disagrees with the instruction its reviewer received, which is the class of bookkeeping drift rounds 2 and 3 were both rejected over.

## Explicit checks

- **Fabricated or unreproducible findings.** None. Item 1's `F8REPRO` block and item 2's five-name CSV block both describe behaviour I confirmed still exists in the pre-fix code (`.task { await regenerate() }` and the two view-`@State` URLs are visible in the `f1237cc` diff), and both fixes' guards fail when I break them. The one number that does not reproduce is finding 4.
- **Citations that do not say what they are claimed to say.** Three. Finding 2 (the `AppModel.swift:106-107` comment, contradicted by `AppModel.swift:299` and `NotificationScheduler.swift:254`), finding 5 (`SettingsExportTests.swift:184-186`), finding 7 (`PROD-READINESS-4.md:130`). I also checked the citations inside `reviews-4/BASELINE-4.md`'s reader table - `NotificationActionLogTests.swift:58,91,153,180`, `SchedulingLogTests.swift:66,115`, `BoundaryLogTests.swift:68`, `CorruptWatermarkTests.swift:57`, `MappingLogPrivacyTests.swift:85` - and every one is a read at the line given, and the quote it takes from `reviews-3/REVIEW-5.md:261` is verbatim. The corrected count of nine is right.
- **Severity inflation or deflation.** None found. F8 and R0-10(b) were P2 in round 1 and are treated as P2-weight work here; F9 was P2 and gets a domain-level fix with a whole-row assertion. The ledger does not restate severities, and does not claim more coverage for the CSV fix than "the cell, never the stored name", which is accurate.
- **Features smuggled past the no-features rule.** No. The scope exception was taken exactly as granted: two rows become `Button`s and the footer gains one sentence. No settings key (no new `UserDefaults` read or write anywhere in the diff), no unrelated screen, no dependency (`Package.swift` untouched in the range). `ExportKind` is new public API but is the fix's own vocabulary, not a feature.
- **Any SwiftData schema change.** None. `git diff --name-only 2d8913c..6ef51ee` touches eight files, none of them under `Packages/OttoPersistence/Sources/`. Schema stays frozen at V3.
- **Prohibited actions.** None observed. `git show-ref` puts `refs/remotes/origin/main` and `refs/heads/main` both at `406a5a6`, so nothing was pushed or merged; there are no tags; `6ef51ee` is still an ancestor of the branch tip, so no history was rewritten; `.github/workflows/ci.yml` is untouched; `.swiftlint.yml` is untouched, so no rule was relaxed, disabled, re-thresholded or excluded; `docs/next-wave.md` is untouched and no other narrative document was edited. No `OSLogStore` read was added - the tree still has the same nine, and the new simulator file reads no log.
- **Fixes that relocated a bug rather than removed it.** Finding 3 - the staleness the fix exists to remove is still reachable through `prepareExport`'s own suspension point. Finding 2 is the adjacent case: the bug was removed from the path it was reported on and left standing on four others.
- **Error handling that hides errors.** No new swallowing. `prepare(_:)` catches and surfaces `error.localizedDescription`, which is what the old `regenerate()` did. The one degradation is finding 6's `failure = nil` on a *different* kind's success. The `try?` I introduced in a mutation is mine, not the builder's.
- **Verification that does not exercise the changed path.** Finding 1, squarely. Also worth stating: `AppModel` has no host test anywhere in the tree, so item 1's fix is invisible to `scripts/verify.sh` and to three of the five CI jobs; it is held only by the simulator job, which the round's flake protocol never runs.
- **Tests that pass for the wrong reason.** Finding 5 is the one that does - it passes while asserting, in its own doc comment, something it cannot see. The other three new UI tests and both new domain tests fail when the thing they name is broken; I broke each and recorded the counts in the table above.
- **Flaky or environment-dependent tests.** None found. The new simulator tests use a bounded `settle` loop (`SettingsExportTests.swift:119-128`) whose timeout is a *named failure* - "no .task on this screen ever ran, so this test proves nothing" - not a silent pass, which is the right shape. Their absence assertions are made against populations the test owns (its own `CountingTransfer`, its own `AppModel`), not a shared log window, so round 3's UUID-substring trap is not repeated. 5 clean observations of the simulator suite and 12 of 12 on `swift test`.
- **Anything marked resolved without an artifact.** No. Items 1 and 2 are the only two marked RESOLVED; each names its commit, its reproduction, its falsifications and a five-dimension measurement table, and every number in that table reproduced except the one in finding 4.
- **Every commit in the range builds all three packages.** Yes - 12 of 12, table above.

## What I could not check, and why

- **That the export Button actually produces a file when a human taps it.** This is finding 1 and I did not close it either: confirming it needs the app driven on the simulator or a UI test, and a review that asserts a fix works because the reviewer also could not test it is worth nothing. What I established is the negative - that no gate in the project would notice if it did not.
- **Release configuration.** Debug only, as in every prior round. ASSUMPTION 3 carries.
- **A physical device**, and therefore the file protection class actually applied to the exports in `tmp` - which is the mitigation F8's P2 severity rests on (`PROD-READINESS.md:95`). Prohibited this run. Note that the frozen fix column for F8 was "generate on demand", which is done; the protection class was never in this item's scope.
- **The device calendar of the two real users.** Undeterminable without the device; ASSUMPTION 1 carries.
- **The `OSLogStore` readers on a CI runner.** Unchanged CANNOT ASSESS. This range adds no reader; the count stays at nine. All nine passed here, in `verify.sh`, and in all twelve flake runs, with no canary firing.
- **`aa92ca7`**, which the ledger correctly routes to its own reviewer and its own range. Not in mine.
- **Whether a spreadsheet actually refuses to evaluate `'=1+1`.** No spreadsheet was run. The apostrophe convention is asserted by the code comment and by F9's original write-up, not measured here; what I measured is that the exported bytes carry it and that the amount column does not.
- **The concurrent state of the branch.** The builder advanced `prod-readiness-4/2026-08-12` from `abef4a7` to `54bb611` (stages 2 and 3) while I was measuring, and the main tree carries uncommitted work. I read only; nothing I did can have disturbed it.
