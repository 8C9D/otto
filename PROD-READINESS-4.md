# PROD-READINESS-4 - Otto, round 4

Bounded remediation of a frozen list, 2026-08-12, branch `prod-readiness-4/2026-08-12`, from commit `2d8913c` on `prod-readiness-3/2026-08-11`.

Baseline artifact: `reviews-4/BASELINE-4.md`.
Review trail: `reviews-4/`.

**This is not a discovery sweep.**
Every item below was found, evidenced and adversarially reviewed in the three runs that produced `PROD-READINESS.md` / `reviews/`, `PROD-READINESS-2.md` / `reviews-2/`, and `PROD-READINESS-3.md` / `reviews-3/`.
Round 4's only job is to close a named subset honestly and to say plainly what it could not close.
No prior record is edited by this run.

Rounds 1, 2 and 3's terminal states and scope constraints still bind, except where the round-4 prompt overrules them explicitly - it does so twice, and both are recorded under ASSUMPTIONS.

---

## Baseline

`scripts/verify.sh` at `2d8913c`, from a clean clone: **exit 0 - OttoDomain 258, OttoPersistence 124, OttoUI 207, total 589**, `swiftlint --strict` clean over 220 files.
Simulator suite from `Packages/OttoUI/`: exit 0, `** TEST SUCCEEDED **`, **117 / 72 / 36 tests, 7 known issues**.
Non-Gregorian harness: **1 / 1 / 5** issues under `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura`.
**Flake rate, new this round: 12 of 12 clean full `swift test --package-path Packages/OttoUI` runs.**

All five reproduce the round-4 prompt's prediction exactly, and the fifth is established here for the first time.
Full output, provenance and the environment table are in `reviews-4/BASELINE-4.md`.

**The standing risk was checked before any edit.**
Every `OSLogStore(scope: .currentProcessIdentifier)` test passes at HEAD, inside `verify.sh` and inside all twelve flake runs, with no canary assertion and no target-line `#require` firing - so the log daemon is delivering here and the production log statements are intact.
It stays in CANNOT ASSESS for CI runners only.

**The reader count in the prompt is wrong, and the corrected figure is in the baseline.**
The prompt says "There are six"; `reviews-3/REVIEW-5.md` says six in OttoUI and one in OttoPersistence.
Measured by enumerating the call sites of every store-opening helper: **seven in OttoUI and two in OttoPersistence, nine in the tree.**
`NotificationActionLogTests` performs four reads, not one, and `NotificationActionTests` matches a `grep` for `OSLogStore` while performing none - the string is in a doc comment.
The "do not add a seventh" rule is applied to nine in this run.

---

## THE WORK LIST - frozen by the round-4 prompt

Seven items, in the order given.
Everything else in rounds 1, 2 and 3's NEXT ROUND stays in NEXT ROUND.

| # | id | what | terminal state |
|---|---|---|---|
| 1 | **F8 + R0-10(b)** | Both exports written to `tmp` on every appearance of Settings, unrequested; `ShareLink` hands out the pre-import file after an import | **RESOLVED** - stage 1 |
| 2 | **F9** | `csvField` does not neutralize a leading `=`, `+`, `-` or `@` | **RESOLVED** - stage 1 |
| 3 | **N3-1 / N3-2** | Ethiopic (+8y) and Indian/Saka (-78y) defeat round 3's plausibility rule | **RESOLVED for Indian/Saka, DEFERRED for Ethiopic** - stage 2; the `createdAt` cross-check is declined on a measurement |
| 4 | **F10** | `rescheduleSoon` spawns an unstructured `Task` per trigger with no coalescing | **RESOLVED** - stage 3 |
| 5 | **R0-11** | `invalidateOutdatedUpcomingEvents` can leave uncommitted soft-deletes while reporting "nothing invalidated" | **RESOLVED** - stage 4 |
| 6 | **N3-3 + N3-4** | `MappingLogPrivacyTests` reads `OSLogStore` with no canary; `aa92ca7` has never been inside any review range | **RESOLVED** - stage 5 for the canary, `reviews-4/REVIEW-AA92CA7.md` for the range |
| 7 | **R4-3** | `ScheduleOutcome.truncatedAfter` has no consumer anywhere | **RESOLVED** - stage 5 |

**No item was rejected twice, and none was reverted.**
Item 3 is the only split verdict, and the split is a property of the problem rather than of the work: Indian/Saka is reachable by a threshold and Ethiopic is not.

Terminal states are **RESOLVED** (with artifact evidence), **DEFERRED** (with reason), or **REJECTED TWICE** (reverted, objection recorded).
There are no others.

## REVIEW RANGES

**This run's FIRST range starts at the branch point, `2d8913c`**, which is the wording round 3's rule was missing and the reason `aa92ca7` escaped three rounds.
Each later stage's range starts at the previous stage's **reviewed head**, and every start is recorded **when the stage opens**, not when its verdict lands.

| stage | range passed to the reviewer | reviewed head | verdict |
|---|---|---|---|
| 0 | - (baseline only) | - | no review; its commit is inside stage 1's range |
| 1 - items 1 + 2 | `2d8913c..6ef51ee` | `6ef51ee` | **PASS-WITH-FINDINGS** (`reviews-4/REVIEW-1.md`) |
| 2 - item 3 | `6ef51ee..00cb0f1` | `00cb0f1` | (`reviews-4/REVIEW-2.md`) |
| 3 - item 4 | `00cb0f1..54bb611` | `54bb611` | (`reviews-4/REVIEW-3.md`) |
| 4 - item 5 + stage 1's remediation | `54bb611..05ff987` | `05ff987` | (`reviews-4/REVIEW-4.md`) |
| 5 - items 6 + 7 | `05ff987..1a1d23b` | `1a1d23b` | **PASS-WITH-FINDINGS** (`reviews-4/REVIEW-5.md`) |
| aa92ca7 | `aa92ca7^..aa92ca7` | `aa92ca7` | **REJECT** (`reviews-4/REVIEW-AA92CA7.md`) - an inherited commit; see its own section |
| 6 - every remediation | `1a1d23b..<final>` | | (`reviews-4/REVIEW-6.md`) |

**Stage 6 exists because all five stage reviewers and the `aa92ca7` reviewer were dispatched before their findings could be routed.** Four of the six returned findings that needed code, and every one of those fixes therefore lands after the last range this run had issued. Leaving them outside a range would reproduce N3-4 - the defect this run was sent to close - inside the run that closed it. So the remediations get a range and a fresh reviewer of their own.

That is a consequence of dispatching reviewers in parallel to save wall time, and it is the honest cost of having done so: a serial run would have folded each remediation into the next stage's range, which is what rounds 2 and 3 did.

Stage 4's range carries stage 1's remediation, which is the disclosed one-stage lag: a remediation lands after the head it remediates and is therefore read by the next stage's reviewer.

**Two stages group two items each, disclosed rather than left to be noticed** (process rule 7).
Stage 1 groups items 1 and 2: both are the export path, and the two questions are the same question asked twice - *what* a complete financial record contains, and *when* one gets written.
Stage 5 groups items 6 and 7: both are a claim with no observer - a log read with no canary, an outcome field with no reader, and a diff no reviewer has read - and all three are closed by making an existing observer observe something it currently does not, at no new query cost.
**One commit per item still holds** in both, and the ranges chain, so no commit falls outside a review.

**`aa92ca7` gets its own reviewer and its own range**, because closing N3-4 means issuing a review of a commit that is not in any of this run's stage ranges. Mixing it into a stage range would hand a reviewer two unrelated diffs and let either hide in the other.

Stage 0's commit is deliberately inside stage 1's range rather than treated as a reviewed parent, so no commit in this run is a range boundary that nobody read - rounds 2 and 3's arrangement, kept.
Each stage's remediation commits land after its reviewed head and are therefore inside the next stage's range - also kept.

**A stage's reviewed head is the commit that RECORDS its measurements, not its last code commit**, so the numbers a reviewer is asked to check are inside the range it is given rather than only in the tree it is standing on.
The one-line commit that writes the head into this table necessarily lands after it, and is therefore in the next stage's range; that is the same one-commit lag rounds 2 and 3 disclosed for their remediations, and it never leaves a **code** commit outside a range.

---

## ASSUMPTIONS

Recorded as they are made; this list is complete at the end of the run.

1. **The device calendar is Gregorian for both real users.**
   Undeterminable without touching the device, which is prohibited.
   Carried forward unchanged from rounds 1, 2 and 3.
2. **Round 2's ASSUMPTION 2 stays overruled**, as round 3 recorded: `.swiftlint.yml` may gain `custom_rules` entries; no existing rule may be relaxed, disabled, or re-thresholded, and no `excluded:` path may be added to make an existing violation go away.
3. **Release configuration behaves as Debug** except where a finding says otherwise.
   No Release build was produced this run.
4. **`2d8913c` is the intended starting point** and no prior branch is to be merged, rebased or pushed by this run.
5. **The `createdAt` cross-check is evaluated against two definitions of a detector round 3 never wrote down** - the fixed-reading form and the any-`D`-within-`K` form, both measured under ITEM 3. Round 3 recorded a sweep and not the rule that produced it, so any figure quoted for it, including this run's, is a figure about a reconstruction.
6. **Every concurrency figure in this run is Debug, on this host, against a fake scheduler.** Peak-concurrency counts are properties of the executor and of how many suspension points the pass has; only the pass COUNTS are properties of the code. Nothing here is a claim about a device.
7. **The seven known simulator issues stay known.** All seven are `EmptyStateTests` accessibility assertions and this host vends no accessibility tree; nothing in this run changes that, and no measurement here treats them as passes.

## ITEM 1 - F8 + R0-10(b), the complete financial record nobody asked for

**RESOLVED**, stage 1, commit `f1237cc`.

### Reconfirmed at HEAD by executing the defect

Not by reading round 1's citation. `SettingsView` was rendered in a real `UIWindow` on the simulator and its `.task` modifiers were allowed to run:

```
F8REPRO permissionCalls=1            <- the control
F8REPRO completeSnapshotCalls=2
F8REPRO jsonExists=true
F8REPRO csvExists=true
F8REPRO fileSubscriptionsBeforeImport=0
F8REPRO fileStillOfferedAfterImport=0 subscriptions
F8REPRO importedSubscriptions=1
```

**F8**: arriving on Settings performed two `completeSnapshot()` reads and left `Otto-Export-2026-08-12.json` and `Otto-Charges-2026-08-12.csv` in the temporary directory. Nothing was asked for and nothing was shared.

**R0-10(b)**: the file at the exact path the `ShareLink` holds contained **0 subscriptions before an import and 0 after one that restored 1**. The share sheet went on offering the pre-import copy.

`permissionCalls=1` is the control and it is load-bearing: `NotificationPermissionSection` has its own `.task`, so a non-zero count proves the screen's tasks ran. Without it, "no export happened" would be equally true of a view that never appeared.
`UIHostingController.sizeThatFits` - what `DynamicTypeTests` uses - runs a layout pass and no `.task` at all, which is why three rounds of view tests never saw this.

### What changed

- **`ExportSection` loses its `.task`.** Each row is a `Button` until an export exists for that kind, then a `ShareLink`.
- **"Which exports were asked for" moves onto `AppModel`** as `prepared: [ExportKind: URL]`, with `preparedExport(_:)` to read and `withdrawPreparedExports()` to drop. A view's `@State` is reachable from nothing that knows an import happened, which is precisely why the stale file survived.
- **`withdrawPreparedExports()` is called from `flowFinished()`** - every §5.4 flow and the import - **and from `subscriptionsStore.onMutation`** - create, edit, delete.
- **That hook is now wired unconditionally.** It used to be installed only inside `if let notifications`, so "the data changed" was observable only on a model that could schedule reminders.
- **`AppModel.exportJSONFile()` and `exportChargesCSVFile()` are gone.** `prepareExport(_:)` is the only caller in `OttoStores` that writes an export file. It is **not** a constraint: `ExportService`'s two methods are `public` and have to be, because `OttoStores` is a different module, so a future view holding `model.exports` could write one without recording it. An earlier version of this line claimed there was "no second, unrecorded writer", which is a claim about code that does not exist yet (`reviews-4/REVIEW-1.md` finding 7).
- **`ExportKind`** is new public API in `OttoServices`, beside `ImportPickerOutcome`.

**The scope exception was taken and is bounded.** The two rows become buttons - navigation the prompt's item-1 allowance explicitly permits - and the footer gains one sentence: *"Otto builds a file only when you ask for it, and stops offering it once your data changes - a backup is a complete copy of your finances, and a stale one is worse than none."* No settings key, no new screen, no dependency.

### Falsified four ways, at the call site each time

Each mutation printed the text it removed and asserted exactly one occurrence before running (process rule 2).

Every count below is **re-derived against the shipped tests** after the stage-1 remediation, not carried from the run that produced it. `reviews-4/REVIEW-1.md` finding 4 caught one of these eight numbers being stale; all of them were, because the tables were written as the mutations ran and the tests grew afterwards.

| what was broken | result |
|---|---|
| an appearance-time `prepareExport` pair re-added to `ExportSection` | **3 issues / 1 test** - `snapshotCalls == 0` fails, both `preparedExport(...) == nil` fail, and the two files are back in the simulator's `tmp` |
| `withdrawPreparedExports()` deleted from `flowFinished()` | **2 issues / 1 test** - the import withdraws neither export |
| `withdrawPreparedExports()` deleted from the `onMutation` hook | **2 issues / 2 tests** |
| `prepareExport` stops recording the URL | **7 issues / 6 tests** |
| the hook re-wrapped in `if notifications != nil` (the reviewer's own mutation) | **1 issue** - it left the whole suite green before the remediation |
| `PaymentMethodsStore`'s `onMutation` call removed | **1 issue** |
| the generation guard removed from `prepareExport` | **2 issues** |

### What this does NOT do

- **`ExportSection`'s own button wiring has no test.** The four tests pin the model and the appearance; a future edit that routes the button somewhere else would not fail. Nothing in the tree renders `SettingsView` for behaviour - this run adds the first test that renders it at all, and it renders it to prove an *absence*. Recorded as **N4-1**.
- **The file is not deleted, only withdrawn.** A prepared export stays in the temporary directory until the system reclaims it. Deleting a file the share sheet may already be reading is a worse failure than leaving one behind, and the answer to "a complete record sits in `tmp`" is to stop writing it unasked, which is what this does.
- **A notification-time change does not withdraw.** It changes no record. Stated in the code.

## ITEM 2 - F9, a name a spreadsheet would run as a formula

**RESOLVED**, stage 1, commit `a412a07`.

### Reconfirmed at HEAD by executing the defect

A snapshot of five hostile subscription names, exported and read back at `2d8913c`:

```
2026-01-15,	=1+1,charged,10.99,,CAD
2026-01-15,+1234567890,charged,10.99,,CAD
2026-01-15,-2+3+cmd|' /C calc'!A0,charged,10.99,,CAD
2026-01-15,=1+1,charged,10.99,,CAD
2026-01-15,@SUM(1+1)*cmd|' /C calc'!A0,charged,10.99,,CAD
```

Every one byte-for-byte. `-2+3+cmd|' /C calc'!A0` is the DDE shape that asks the spreadsheet to run a program, and `\t=1+1` is the leading-tab variant several importers strip before evaluating what is behind it.

### What changed

`csvField` becomes **neutralize, then quote**. The triggers are `=`, `+`, `-`, `@`, TAB and CR; the neutralizer is a leading apostrophe, which every spreadsheet reads as "the rest of this cell is text".

**Applied to the cell, never to the stored name.** Nothing about the subscription changes and the JSON export - the one that round-trips - still carries the exact name. This file is already documented as lossy and one-way, so a display-level apostrophe in a file meant for reading is the cheap side of the trade.

**Amounts deliberately do not go through it.** `decimalAmount` writes `-10.99` for a negative amount, and a leading minus in front of a number is a number to every spreadsheet; neutralizing that column would corrupt the figures the export exists to let someone add up. That is why the guard asserts the **whole row** rather than the name cell.

### Falsified four ways

Re-derived against the shipped tests, as above.

| what was broken | result |
|---|---|
| the neutralizer not called at all | **8 issues / 2 tests** |
| the four triggers the finding names removed, TAB / CR / LF kept | **5 issues / 2 tests** |
| neutralize **after** quoting instead of before | **3 issues / 2 tests** - the apostrophe lands outside the quotes |
| the neutralizer applied to the **amount** column | **9 issues / 1 test** - the control, and the reason the row is asserted whole |

### Baseline at the end of STAGE 1 (`a412a07`) - all five, measured

| measurement | `reviews-4/BASELINE-4.md` | at `a412a07` | verdict |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 258 / 124 / 207 = 589 | exit 0, **260 / 124 / 207 = 591** | +2, item 2's two domain tests |
| `swiftlint --strict` | clean, 220 files | clean, **221 files** | unchanged; the new file is the simulator test |
| simulator suite | 117 / 72 / 36, 7 known issues | **117 / 72 / 40**, 7 known issues, `** TEST SUCCEEDED **` | +4, item 1's four tests |
| non-Gregorian harness | 1 / 1 / 5 | 1 / 1 / 5, same five citations | unchanged |
| flake rate | 12 of 12 | **12 of 12**, 13.9 s - 16.4 s | unchanged |

Item 1's four tests are UIKit-hosted, so they land in the simulator's third bucket (36 → 40) and not in `verify.sh`'s total.
Item 2's two tests are domain tests and land in both.

## ITEM 3 - N3-1 / N3-2, the two calendars round 3 could not reach

**HALF RESOLVED**, stage 2, commit `2afde29`: **Indian/Saka is closed, Ethiopic is not and cannot be.**
The `createdAt` cross-check is **declined**, on a measurement rather than an argument.
The V3 schema freeze is untouched - nothing here needs a schema at all.

### Reconfirmed at HEAD by executing the defect

The real `NotificationScheduler` was driven over the day a pre-F1 build stored on each device for Gregorian 2026-08-06, with `today` at 2026-08-11:

```
indian(-78)   anchor=1948-05-15 scheduled=4 ledgerFailures=0 canClaimCoverage=true
              fireDays=[2026-8-12, 2026-9-12, 2026-9-23, 2026-10-12]
ethiopic(-8)  anchor=2018-11-30 scheduled=4 ledgerFailures=0 canClaimCoverage=true
              fireDays=[2026-8-27, 2026-9-27, 2026-10-19, 2026-10-27]
healthy       anchor=2026-08-06 scheduled=4 ledgerFailures=0 canClaimCoverage=true
              fireDays=[2026-9-3, 2026-10-3, 2026-11-3, 2026-11-4]
buddhist      anchor=2569-08-06 scheduled=0 ledgerFailures=1 canClaimCoverage=false
```

Four reminders on the 12th or the 27th instead of the 3rd, with the pass reporting itself healthy on every field Today reads. The Buddhist control shows round 3's guard working.

### The decision: the `createdAt` cross-check is declined

Re-derived independently, from a standalone Foundation script that imports no Otto code.

**The K sweep reproduces, with one correction.**

| K(days) | this run | `reviews-4/REVIEW-2.md` | round 3's ledger | `reviews-3/REVIEW-3.md` |
|---|---|---|---|---|
| 1 | 3 / 4001 (0.07%) | 3 | 3 | 2 |
| 3 | 7 / 4001 (0.17%) | 7 | 7 | - |
| 7 | 15 / 4001 (0.37%) | 15 | 15 | 14 |
| 31 | **63** / 4001 (1.57%) | **64** | **64** | **63** |

**That conviction is withdrawn.** `reviews-4/REVIEW-2.md` finding 1 measured 64 and showed why the 2K+1 argument fails, and it is right about the argument: the Ethiopic band is **not** contiguous. Measured here, the Ethiopic readings of `createdAt ± 31 days` are **63 distinct days spanning 2018-10-29 to 2019-01-01**, a 65-day span with gaps, because Ethiopic's thirteenth month is five or six days long and the offset flips between −7 and −8 inside the window. So "a ±K window contains exactly 2K+1 days" is false here, and I convicted three documents on it.

My scan still returns 63, under **both** readings of a detector round 3 never wrote down:

```
DEFINITION A  |stored - C(createdAt)| <= K, one fixed reading per calendar
              K=1 -> 3    K=3 -> 7    K=7 -> 15    K=31 -> 63
DEFINITION B  stored is C(D) for SOME D with |D - createdAt| <= K
              K=1 -> 3    K=3 -> 7    K=7 -> 15    K=31 -> 63   (band 630 days)
```

So the disagreement is one anchor wide and lives in the **scan window and the detector's definition**, not in anyone's arithmetic. The honest statement is: at K=31 the false-positive count is **63 or 64 depending on how the detector and the scanned anchor range are defined**, round 3 never defined either, and the figure decides nothing here - the rule is declined for the reasons in the sensitivity table, where the numbers differ by two orders of magnitude rather than by one anchor.

**The premise the sweep hides, measured.** "Sensitivity 13/13" is measured with the stored day *equal to the creation day*. A real stored day is a date the user picked, which is not the day they added the record. Sensitivity against that gap:

```
gap(days) | K=1   | K=3   | K=7   | K=31    (of the 13 calendars that can corrupt)
        0 | 13/13 | 13/13 | 13/13 | 13/13
        1 | 13/13 | 13/13 | 13/13 | 13/13
        3 |  1/13 | 13/13 | 13/13 | 13/13
        7 |  0/13 |  0/13 | 13/13 | 13/13
       14 |  0/13 |  0/13 |  0/13 | 13/13
       30 |  0/13 |  0/13 |  0/13 | 13/13
       60 |  0/13 |  0/13 |  0/13 |  0/13
      365 |  0/13 |  0/13 |  0/13 |  0/13
```

The rule detects a corrupted day only when the user picked a date within K days of creating the record. The prompt says "Sensitivity does not decay as the window narrows," which is true and is not the axis that matters: it does not decay with K, it collapses with the gap, and the sweep held the gap at zero.

**`lastUsedDate` and a distant `pauseEndsOn`, which the prompt requires characterising and round 3 did not.** At the most generous window tested, K=31:

| what is stored | Ethiopic | Indian |
|---|---|---|
| `lastUsedDate` recorded the day the record was created | caught | caught |
| `lastUsedDate` recorded 6 months after creation | **MISSED** | **MISSED** |
| `lastUsedDate` recorded 5 years after creation | **MISSED** | **MISSED** |
| `pauseEndsOn` 3 months out, record created today | **MISSED** | **MISSED** |
| `pauseEndsOn` 1 year out, record created today | **MISSED** | **MISSED** |
| `pauseEndsOn` 1 year out, record created 4 years ago | **MISSED** | **MISSED** |

`createdAt` is the wrong reference instant for both fields, structurally and not by tuning. `lastUsedDate` is written when the user records a use; `pauseEndsOn` is a future date chosen at pause time; and `cycleStartDay` is `let` but replaced wholesale at trial conversion, with `createdAt` preserved. The one instant the rule can compare against is the one instant none of them was written at.

**Declined**, therefore: it detects a corrupted anchor only in the narrow case where the user's billing date is the day they added the subscription, it detects a corrupted `lastUsedDate` or `pauseEndsOn` essentially never, and it costs a false positive that silences a working subscription's reminders. That trade is worse at every K than not having it.

### What was adopted instead, and why the prompt's premise is wrong

**The prompt says no distance threshold can reach either calendar. That is false for Indian/Saka, and round 3's own doc comment contains the refutation** - it justified a century as *"forty years beyond the oldest plausible billing anchor"*, which is a statement that sixty years is already beyond it.

Round 3's rule was **symmetric**; the corruption is not. Measured over every day of a year against Foundation:

```
buddhist            [ +543,  +543]      hebrew   [+3760, +3761]     <- ahead
indian              [  -79,   -78]      islamic{,Civil,Tabular,UmmAlQura} [-579, -578]
japanese            [-2018, -2018]      persian  [ -622,  -621]
coptic              [ -284,  -283]      minguo   [-1911, -1911]
chinese             [-1984, -1983]                                  <- behind
ethiopicAmeteMihret [   -8,    -7]                         <- still unreachable
```

So the window becomes **70 years behind, 100 ahead**.

- **Indian/Saka is caught**, in every month and for every one of the five checked fields, with eight years of margin against its 78-79 year offset. Measured field by field: an anchor at creation, an anchor a month out, an anchor a year out, an anchor ten years in the past, a trial start, a `lastUsedDate` five years old and a `pauseEndsOn` a year out are all caught. The single miss is a `pauseEndsOn` **eight** years out, and a subscription with one of those has an anchor that is caught anyway.
- **Ethiopic is not, and no threshold reaches it.** Seven to eight years behind is an ordinary anchor for a subscription somebody has held since 2018.
- **The cost is measured, not asserted.** The oldest accepted stored day moves from 1926-01-01 to 1956-01-01. Every day from 1900 to 2126 was swept: the rule newly rejects only 1900-01-01 to 1955-12-31, it rejects nothing in the forward direction that the old rule accepted, and the only stored days any of the five fields can carry are a cycle origin, a trial start, a derived conversion date, a pause resume and a last use - none of which can sensibly precede 1956. The Unix epoch survives with fourteen years of room.

**The only pre-1956 fixtures in the tree are `DateEngineEdgeCaseTests.swift:52-54`** (1896, 1900, 1904), which call `billingDate(occurrence:anchor:cycle:)` directly and never reach a scheduler or `implausibleStoredDays`. Re-derived here rather than carried from round 3's claim about the ±100 rule.

### An assertion was changed, and it is the mechanism working rather than being weakened

`StoredDayPlausibilityTests.knownUncatchable` loses `indian`. Round 3 wrote that set as a **positive** assertion precisely so that catching one of its members would fail the test and force the record to be updated - its own comment says *"the right response is to update this set and the ledger, not to delete the assertion."* That is what happened. `realDatesSurvive` loses `1926-08-11`, which is a century old and is now correctly rejected; `windowEdges` gains the second bound and the assertion that the two differ.

### Falsified four ways

**Re-derived after `reviews-4/REVIEW-2.md` finding 2**, which measured three of the four counts below wrong. The originals were taken from a filtered view of the output; these are whole-suite counts.

| what was broken | result |
|---|---|
| back to round 3's symmetric century | **15 domain issues / 3 tests, and 2 in OttoUI / 1 test** - Indian escapes both |
| backward bound set to **78**, Indian's exact offset | **16 domain issues / 3 tests, and 2 in OttoUI / 1 test**; pins that the eight-year margin is load-bearing and 70 is not padding |
| both bounds set to 70 (asymmetry removed the other way) | **5 domain issues / 2 tests** - a far-future prepaid term is rejected, which is the other half of why it is asymmetric |
| the scheduler stops calling `implausibleStoredDays` | **8 OttoUI issues / 5 tests** (and none in the domain, which is right - the wiring is not domain code) |

That is the second time in this run a falsification table was recorded from a partial view of the output, after `reviews-4/REVIEW-1.md` finding 4, and the ledger claimed to have swept the class. It had swept items 1 and 2 and not this one.

### What a user on those two calendars is actually left with

**Indian/Saka**, as of this run: the same position as the other eleven. Reminders are still scheduled and still on the wrong days (see N4-2), Today no longer claims coverage, the gap card appears, the log names the exact days, the list shows the wrong dates in plain sight, and `docs/next-wave.md` now tells them how to repair it.

**Ethiopic**: unchanged and undetectable. No card, no log line, no signal of any kind from Otto. Four reminders arrive on the wrong days of the month while Today states full coverage. The only thing that is visibly wrong is the date on the subscription list, which is off by eight years and is the one thing a user might notice unaided. `docs/next-wave.md` now says so explicitly, which is the whole of what this run can do for them.

Live exposure for both remains nil under ASSUMPTION 1, and no locale defaults to either calendar.

### Remediation after `reviews-4/REVIEW-1.md`

Verdict **PASS-WITH-FINDINGS** over two P2s and seven P3s. Both P2s are defects in this stage's own work and are fixed here (`b054506`); the remediation commit lands after the reviewed head and is therefore inside stage 4's range.

- **Finding 2 (P2) - a false promise, shipped to the user.**
  The footer said *"stops offering it once your data changes"* and `withdrawPreparedExports()` was reachable from **two** of at least **six** paths that change exported data. The reviewer demonstrated by execution that saving a payment method leaves the stale JSON backup on offer.
  Fixed on both sides. `PaymentMethodsStore` gains the `onMutation` hook it never had - `paymentMethods` is a stored collection of `OttoDataSnapshot` - and both cancellation-evidence editors withdraw, because `evidenceNotes` are encoded in the export. The copy now says only what is true.
  **A code comment of mine was measured false and is corrected**: it claimed a notification-time change "changes no record", and the reschedule it triggers calls `materializeEvents`, which writes ledger rows the CSV prints. That path withdraws now.
  `NotificationActionHandler` and a bare scheduling pass still do not withdraw - **N4-4**, disclosed rather than claimed closed.
- **Finding 1 (P2) - shrunk, not closed.** Deleting the Button's action left every gate in the project green, and after this stage a mis-wired button means backups become *impossible* rather than stale. The whole state machine moved onto `AppModel`, where eight tests reach it, and the view is now one call with no logic in it. What no test in this project can reach is that single closure. Carried at the reviewer's severity as **N4-1**.
- **Findings 3, 5, 6 (P3) - fixed, each with a guard that bites.** A withdrawal landing during an in-flight build was overwritten by it (a generation counter now refuses to install a file built from a superseded snapshot); the test that claimed to pin the unconditional `onMutation` wiring could not see it, because every model in the suite had a notification store (there is now one without); `preparing` and `failure` were single-valued and cleared unconditionally across kinds (both are per-kind).
- **Finding 8 (P3)** - `\n` was covered by the trigger set's own stated rationale and absent from the set. Added, with its case.
- **Finding 4 (P3) - it found one stale falsification count; all eight were stale.** Every number in both tables above is re-derived against the shipped tests.
- **Finding 7 (P3)** - "no second, unrecorded writer" was a claim about code that does not exist yet. Reworded above.
- **Finding 9 (P3, process) - the reviewed head I handed the reviewer disagreed with the ledger at that commit.** True and inherent to the rule this run introduced: a head that is the measurement commit cannot be written into the table before it exists. The range issued was the wider of the two and the drift is documentation-only, but the rule is worth restating: **the START is recorded when the stage opens, the HEAD when it closes, and the one-line commit that writes the head is in the next range.**

**One process defect of this run, recorded rather than hidden.**
`reviews-4/REVIEW-1.md` was swept into item 5's commit (`12024ab`) by `git add -A`, because the reviewer writes its verdict into the main tree while the builder is working in it. The contract requires each review to be its own commit. History is not rewritten to hide it; explicit paths are used from here.

## ITEM 4 - F10, five triggers and five passes

**RESOLVED**, stage 3, commit `54bb611`.

### Reconfirmed at HEAD by executing the defect

Five triggers fired with no `await` between them, with the pass count and the peak concurrency measured inside the scheduler:

```
five triggers                  passes=5  peakConcurrency=3
a trigger during a pass        passes=4  peakConcurrency=3
```

Five simultaneous full reschedules, each loading every subscription, reconciling every ledger and writing every watermark, racing on the same rows.
**The peak is 3, not the 5 predicted** - 3 is what the executor actually interleaved, and the number recorded is the measured one.
This is not a contrived burst: a foreground open fires `.foreground` while a delivered notification fires `.notificationDelivered`, and a timezone change arrives beside a significant-time change.

### What changed

`rescheduleSoon` holds one in-flight `Task` and at most one queued trigger.
A trigger arriving while a pass runs leaves exactly one follow-up behind it, however many arrive: the pass is idempotent and recomputes the whole plan from current state, so N triggers need at most one more run - **but they do need that one**, because a trigger that lands after the in-flight pass has read the store describes a change that pass cannot have seen.
`queued` is cleared **before** the pass, never after, or that follow-up is swallowed.
The returned `Task` is the whole chain, so awaiting it awaits every pass the caller's trigger caused.

### Falsified four ways

| what was broken | result |
|---|---|
| the exact pre-F10 shape | **5 issues** - passes 5, peak 3, published 5 |
| coalescing turned into dropping | **1 issue** - the follow-up swallowed |
| `queued` cleared **after** the pass | **2 issues** - a spurious second pass |
| the gate never reopens | **1 issue** - later triggers do nothing |

### One claim was written, deleted as unreproducible, and was in fact true

`handleBackgroundRefresh` is outside the gate - it owns the completion latch and the expiration race and builds its own `Task`.
I wrote the assertion `peakConcurrency == 2`, saw it fail on **one** run, and recorded that it "does not reproduce".
**It reproduces 18-41 % of the time.** `reviews-4/REVIEW-3.md` finding 1 measured 45 of 240 iterations; re-measured independently here with a spy that suspends six times to model the real pass, **74 of 180**. `NotificationScheduler` is an actor whose `reschedule` suspends repeatedly before it writes, so it interleaves passes rather than serialising them.
The test asserts only that the background pass is not coalesced, because an assertion true 18 % of the time is a flaky test rather than a guard - but the overlap is real, it is F10 still live on a second path, and there is a **third** ungated entry point beside it (`NotificationStatusStore.reschedule()`, 33 of 240). Carried as **N4-3 at P2** and **N4-7**.

### Two splits rather than a relaxed rule

`SpyState` moved to file scope, because `nesting` allows one level and the spy is already one deep; the stubs moved to `NotificationCoordinatorStubs.swift` when the file passed the 400-line `file_length`. The move was diffed after stripping comments and the `private` keyword and is otherwise byte-identical.

## ITEM 5 - R0-11, the soft-delete nobody was told about

**RESOLVED**, stage 4, commit `12024ab`.

### Reconfirmed at HEAD by executing the defect

Two future-dated `.upcoming` rows whose `createdAt` a partial sync had left nil - a shape `toDomain()` rejects and the method's own guards (a future date, a readable packed day, an amount) do not:

```
reported=0 ("nothing invalidated" is true)
committedTombstonesRightAfter=0
committedTombstonesAfterAnUnrelatedSave=2
```

Both rows soft-deleted in memory, the caller told nothing had happened, no save run - and **the next unrelated `save()` on this actor's shared context flushing both tombstones in a transaction that had nothing to do with them.**

### What changed

The method asked two different questions and used one answer for both: it mutated a row, then decided whether to **save** by asking whether the row could be **described** back to the caller. Mutations are counted separately and the save is keyed on that; the conversion failure is logged instead of swallowed by `try?`.

**The row is tombstoned rather than skipped, and that is the load-bearing choice.** `materializeEvents`' dedup reads the **raw** `expectedDate` column of every live row and never maps it, so an unmappable phantom left alive silently blocks its own date forever and the correct replacement row is never written - a missing ledger row, which is F6's family. Measured under the mutation that skips instead: `rematerialized == []` against the two dates.

**The return value still undercounts, by construction** - there is no `BillingEvent` to hand back for a row that will not map - and the log line is the only place that says so, which is why it is guarded rather than left as an artifact.

### Falsified three ways

| what was broken | result |
|---|---|
| save keyed on `invalidated` again (the pre-fix shape) | **1 issue** - 0 tombstones committed |
| the log statement deleted | **3 issues** - the two rows unnamed |
| skip instead of tombstone | **4 issues**, the load-bearing one being `rematerialized == []`. Its first failure is an artifact of the mutation converting before mutating, not of the fix |

### The log test asserts over a window it does not own, and is pinned

Its two sibling tests drive the same production path, and `OSLogStore.position(date:)` reaches ~80 ms behind `since` - **measured as six matches where this test controls two**. It is pinned to its own subscription index 7011. Round 3's flake, one file over, caught before it shipped.

### Cost, stated as the prompt requires

This is a **tenth** `OSLogStore` read in the tree and a third in OttoPersistence, ~9-11 s. A shared query would not do: the two existing persistence readers assert about the watermark path and the mapping-privacy path over their own windows, and folding a third subject into either makes a failure ambiguous between unrelated causes - the misdiagnosis the canary exists to prevent, reintroduced one level up.

## ITEM 6 - N3-3 + N3-4, a read with no canary and a diff nobody read

**First half RESOLVED**, stage 5, commit `5bdcd20`. **Second half is the review itself**, `reviews-4/REVIEW-AA92CA7.md`.

### N3-3, the missing canary

The one log-reading test in the tree without a canary, so on a runner where the store is **readable but empty** it failed at `#expect(!ours.isEmpty, "the store logged nothing for the record it skipped")` - a message meaning "the production log statement is gone", which is precisely the misdiagnosis the canary exists to prevent. `PROD-READINESS-2.md` recorded the canary as covering all four log-reading tests; it covered three.

The canary rides in the window this test already opens and `requireDelivered` runs before any assertion about content, so **no query and no reader was added**. The file's duplicate `persistenceLogLines` helper is gone in favour of `OttoLogProbe.persistenceLines`, which is the same read.

**Falsified both ways, which is the whole point of a canary - the two causes must fail DIFFERENTLY:**

| what was broken | result |
|---|---|
| the canary emission deleted, **under `--filter`** | fails at `requireDelivered`: *"The unified log delivered NOTHING for this process ... This is an environment failure ... Do not fix it by deleting the assertions it guards."* |
| the canary emission deleted, **in the suite as shipped** | **green** - a sibling test's canary is in the shared window, and that is the canary answering its own question correctly: the subsystem *did* deliver |
| the **production** skip statement deleted, canary intact | fails at the target line: *"the store logged nothing for the record it skipped"* |
| the whole target run under `OS_ACTIVITY_MODE=disable` | all three OttoPersistence log-reading tests fail at `requireDelivered` with the environment message |

**Before this change the last row produced the third row's message**, which is the misdiagnosis.
The first row as originally written **did not reproduce in the full suite**, and the ledger did not say it was measured under a filter - `reviews-4/REVIEW-5.md` finding 2. That is the third falsification row in this run recorded from a narrower scope than the one it was quoted at. The substance is unaffected and is now demonstrated the way that actually distinguishes the two causes: by suppressing the subsystem.

### N3-4, the commit outside every review range

`aa92ca7` is re-derived in `reviews-4/BASELINE-4.md` and reviewed by its own fresh reviewer on its own range, `aa92ca7^..aa92ca7`. Mixing it into a stage range would hand a reviewer two unrelated diffs and let either hide in the other. Its verdict is in the REVIEW RANGES table.

## ITEM 7 - R4-3, the outcome field nothing read

**RESOLVED**, stage 5, commit `8a62c0c`.

### Reconfirmed at HEAD

`ScheduleOutcome.truncatedAfter` reached nothing at all: `NotificationScheduler` set it, `coveredThrough` was computed from the same **local variable** rather than from the field, and no reader anywhere - production, UI or store - ever asked the outcome for it. `TodayView` renders `coveredThrough`; `NotificationStatusStore` republishes the outcome; neither touches the truncation. The `pass end` line carried every **other** field of the outcome and not that one.

### The discriminating case is the finding itself

A pass that dropped rungs past the 64-slot budget and a pass that dropped none log identically whenever their `coveredThrough` agrees - **and it agrees exactly when the distinction matters**, because a truncated pass's covered day *is* its truncation point. Measured under the mutation that removes the field, both lines are

```
pass end trigger=foreground permission=authorized scheduled=64 coveredThrough=2026-09-01 ledgerFailures=0
```

byte-identical, for a pass that silently dropped rungs and one that did not.

### What changed, and what it deliberately does not do

The line's fields are composed in `OttoLog.passEndFields` so a test can read them **without opening `OSLogStore`**. The tree already blocks on that daemon nine times and this run adds a tenth for item 5; an eleventh for one field is not a trade worth making.

**The emission is guarded too, and my reason for not guarding it was wrong.**
I declined on the grounds that it would cost a tenth `OSLogStore` reader. `reviews-4/REVIEW-5.md` measured what that decision was worth - restoring the pre-fix interpolation at the call site leaves the composer correct, its unit test green, and **all 209 host tests passing**, so the whole of R4-3 could be put back in production behind a green ⛔ guard - and then closed it at **zero** additional reads, inside a `scheduling`-category window `SchedulingLogTests` already holds open.
Done here the same way: that test's pass now goes through the trigger-tagged entry point every production caller uses, and asserts the `pass end` line carries `truncatedAfter=`. Falsified with the reviewer's own mutation: **1 issue**, where it was green before. **N4-5 is closed**, and the cost I quoted for it was never the cost on the table.

**A user-facing consumer is still absent**, and adding one is new copy this run may not write: the person whose annual renewals were dropped past the budget learns it only from an earlier date in "Reminders scheduled through …". **N4-6.**

## EVERY UNVERIFIED FIX, AND WHY

The prompt asks for these by name. A fix is listed here when something about it rests on reading rather than on running.

| fix | what is unverified | why |
|---|---|---|
| item 1's export **button** | that a tap reaches `AppModel.requestExport` | Nothing in this project renders a view for behaviour. This run added the first test that renders one at all, and it renders `SettingsView` to prove an **absence**. `requestExport` itself is now guarded; the closure that calls it is not, and closing that needs a UI-test target - a dependency this run may not add. **N4-1.** |
| item 1's two cancellation-evidence withdrawals | that they fire | Both editors return early unless the subscription has an open cancellation episode, which needs multi-step state this test target does not build. **N4-9.** |
| item 3's asymmetric window, on a real device | that a device that was Indian/Saka now shows the gap card | No non-Gregorian device exists to test, and the harness offers Buddhist, Japanese and Islamic-umalqura only. What is verified is the detector and the scheduler pass, on a Gregorian host, where the corruption lives in the stored values and reproduces exactly. |
| item 4's coalescing, on a device | that the trigger bursts it merges are the bursts iOS actually delivers | The gate is proved against a fake scheduler on the simulator. `BGAppRefreshTask`'s real behaviour stays CANNOT ASSESS, as in every round. |
| item 5's log line, on a CI runner | that the tenth `OSLogStore` read is readable there | Unchanged CANNOT ASSESS. It passes here, in `verify.sh`, and in every flake batch. |
| everything, under **Release** | all of it | No Release build was produced this run (ASSUMPTION 3). |

Nothing else in this run is verified only by reading.

## ITEM 1, ANSWERED DIRECTLY: does a complete financial record still reach `tmp` unasked?

**No, and the "under what conditions" has two real answers rather than one.**

- **Opening Settings writes nothing.** Measured by rendering the screen in a window and letting its `.task` modifiers run, with a control proving they ran: `completeSnapshotCalls == 0`, no file on disk. Before the fix the same measurement gave 2 and two files.
- **A tap writes one file, into `tmp`, and leaves it there.** That is the point of the feature and it is what the user asked for. `withdrawPreparedExports()` stops Otto **offering** it; it does not delete it, because deleting a file the share sheet may already be reading is a worse failure than leaving one the system reclaims. So after a deliberate export, a complete unencrypted record does sit in the temporary directory until iOS clears it - as it did before, and now only when asked.
- **The file's protection class is not established.** F8's original P2 severity rested partly on it, and it needs a device this run may not touch. Unchanged from round 1, and out of this item's frozen scope.

## VERIFICATION - all five dimensions, at each measured commit

| measurement | `reviews-4/BASELINE-4.md` (`2d8913c`) | stage 1 (`a412a07`) | stages 2-4 (`b054506`) | stage 5 (`8a62c0c`) |
|---|---|---|---|---|
| `scripts/verify.sh` | exit 0, 258 / 124 / 207 = **589** | exit 0, 260 / 124 / 207 = **591** | exit 0, 261 / 127 / 208 = **596** | exit 0, **261 / 127 / 209 = 597** |
| `swiftlint --strict` | clean, 220 files | clean, 221 | clean, 224 | **clean, 224** |
| simulator suite | 117 / 72 / 36 = 225, 7 known issues | 117 / 72 / 40 = 229 | 118 / 72 / 48 = 238 | **119 / 72 / 48 = 239**, 7 known issues, `** TEST SUCCEEDED **` |
| non-Gregorian harness | 1 / 1 / 5 | 1 / 1 / 5 | 1 / 1 / 5 | **1 / 1 / 5**, same five citations |
| flake, twelve full runs | 12 of 12 | 12 of 12 | 12 of 12 | **12 of 12** |

**+8 host tests and +14 simulator tests against the baseline**, no lint rule relaxed, no test skipped or disabled, no new known issue, and the same five non-Gregorian citations throughout.

**Where the numbers land, since the split confuses every round.** Items 1 and 4 are UIKit-hosted and land only in the simulator's third bucket (36 → 48). Item 3 adds one test to `OttoServicesTests`, which is the simulator's first bucket **and** `verify.sh`'s OttoUI count (117 → 119 across two stages, 207 → 209). Items 2 and 5 are host tests and land in both.

**Two deviations from the per-stage measurement protocol, recorded rather than glossed.**

1. **Stages 2, 3 and 4 were measured jointly at `b054506`, not three times at three heads.** Build, host tests and lint were run at each item's own commit and were green each time; the non-Gregorian harness and the twelve-run flake were run once, after the three. The review trail restores the per-stage measurement, because each stage's reviewer re-runs all five at its own reviewed head independently.
2. **The flake protocol reads the WORKING TREE, not the committed head.** `swift test --package-path Packages/OttoUI` is not `verify.sh`; it compiles whatever is on disk. Twice in this run an edit for the next item was in progress when a gate started, and both times the edit was parked out of the tree and restored afterwards so the measurement was of the commit it names. The prompt specifies this command without saying the tree has to be clean, and a run that forgets is measuring something that has no commit.

## A process risk observed in this run's own review contract

`Packages/OttoPersistence/.build/` and `Packages/OttoUI/.build/` contain compiled artifacts named `ZZReviewProbeTests`, `ZZProbe2` and similar - probe files no commit in this repository has ever contained.
The contract requires every reviewer to do its mutation work in a detached worktree, and the **source** tree is clean (`git status --porcelain` empty at the end of every stage, and every flake run in every gate reported the same test counts as the clean-clone `verify.sh`), so nothing measured here is contaminated.
But a build cache under the main package path can only be written by a command whose `--package-path` pointed at the main tree.
**The worktree rule protects the source and says nothing about the build directory**, which is shared, and that is a real gap in the contract rather than in any one reviewer.

---

## NOT DEFECTS

A finding that no longer reproduced at HEAD would be here with its evidence rather than fixed.

**None.**
All seven work-list items were reconfirmed by **executing** the defect before being touched, never by reading the citation:

| item | how it was executed |
|---|---|
| F8 + R0-10(b) | rendered `SettingsView` in a real `UIWindow` - 2 `completeSnapshot()` calls and two files in `tmp` from an appearance alone; the offered file held 0 subscriptions after an import restored 1 |
| F9 | exported a snapshot of five hostile names - every one came back byte-for-byte, including `-2+3+cmd\|' /C calc'!A0` |
| N3-1 / N3-2 | drove the real scheduler over an Indian and an Ethiopic anchor - 4 reminders each, on the wrong days, `canClaimCoverage=true` |
| F10 | fired five triggers - **5 passes**, every run; the peak concurrency varied 2-5 across runs and is a property of the executor, not of the code |
| R0-11 | two unmappable future rows - reported 0, committed 0, then 2 committed by an unrelated `save()` |
| N3-3 | deleted the production skip statement - the test failed with the message that means "the log statement is gone", which is also what an empty window produced |
| R4-3 | removed the field - a truncated pass and a whole pass produce byte-identical lines |

## DEFERRED

- **R0-7's repair** - repairing calendar days already stored under a non-Gregorian device calendar. Unchanged from round 3, and for round 3's reason: the writing calendar was never recorded and cannot be recovered. Round 4 closed **detection** for one of the two calendars round 3 could not reach; the days stay wrong until a human fixes them, and `docs/next-wave.md` now tells that human how.
- **Ethiopic detection** - no distance threshold reaches 7-8 years, and the `createdAt` cross-check is declined on the measurement under ITEM 3. Nothing known closes it.
- **F7 - clock monotonicity in merge resolution.** Scoped to the CloudKit wave; prior analysis in `docs/sync-safety.md`. Untouched by all four rounds.

## WHAT IS WRONG OR UNDERSPECIFIED IN THE ROUND-4 PROMPT

Ten, measured rather than asserted. Rounds 1, 2 and 3 found six, six and eight.

1. **"There are six" `OSLogStore`-reading tests. There are nine.**
   Seven in OttoUI, two in OttoPersistence, counted by enumerating the call sites of every helper that opens a store: `NotificationActionLogTests` reads **four** times (58, 91, 153, 180), `SchedulingLogTests` twice, `BoundaryLogTests` once, plus `CorruptWatermarkTests` and `MappingLogPrivacyTests`. `NotificationActionTests` matches a `grep` for `OSLogStore` and reads nothing - the string is in a doc comment. Six is what a **file**-level count returns. The rule built on the number ("do not add a seventh") therefore names a threshold that was already passed before this run started.

2. **"no distance threshold can" reach Ethiopic or Indian is false for Indian/Saka**, and round 3's own doc comment contains the refutation.
   Round 3's rule was **symmetric**; the corruption is not. Indian is 78 or 79 years *behind* in every month and for every field, and round 3 justified its century as *"forty years beyond the oldest plausible billing anchor"* - which is a statement that sixty years is already beyond it. A backward bound of 70 catches Indian with eight years of margin, moves the oldest accepted stored day from 1926 to 1956, and touches no fixture in the tree that reaches a scheduler. The prompt froze a conclusion that one measurement overturns.

3. **The K-sweep table's K=31 figure cannot be checked, because the rule that produced it was never written down.** ~~A ±K window contains 2K+1 days, so 64 is wrong.~~ **Withdrawn** - measured, the Ethiopic band is not contiguous (63 distinct readings spanning 65 days), so that argument is refuted. Three independent measurements in this run returned **63** (mine, two definitions), **64** (`reviews-4/REVIEW-2.md`) and **62** (`reviews-4/REVIEW-6.md`, excluding anchors that are not valid Ethiopic dates). The prompt inherits a number from a sweep whose detector and scanned range round 3 never recorded, which is the defect - not the digit.

4. **"Sensitivity does not decay as the window narrows" is true and is not the axis that matters.**
   The 13/13 figure is measured with the stored day **equal to the creation day**. Measured against the gap between them, it is 13/13 at 0-1 days, 1/13 at 3 days for K=1, and **0/13 at 60 days for every K including 31**. For a `lastUsedDate` recorded six months after creation and for a `pauseEndsOn` three months out it is 0/13. The prompt presents a property of the fixture as a property of the rule, and asks the run to weigh a trade whose benefit side is mis-stated.

5. **"The only known route is the one round 3 measured and declined" is not the only route.**
   An asymmetric distance bound needs no new evidence source, no `createdAt`, no schema question, and closes half the residual. The prompt's framing made the `createdAt` cross-check look like a take-it-or-leave-it, which is the shape that produces a bad decision either way.

6. **The flake protocol names a command that does not read the commit.**
   `swift test --package-path Packages/OttoUI` compiles the **working tree**; `verify.sh` clones the committed head. The prompt requires twelve runs "at the end of every stage" without saying the tree must be clean, so a run with the next item's edit half-written measures a state that has no commit and no name. This bit twice in this run and was caught both times only because the edits were parked deliberately.

7. **"Commit each review as its own commit" is not achievable as specified.**
   Reviewers write their verdict into the **main** working tree while the builder is working in it, so a builder's `git add -A` sweeps it into whatever is being committed. That is exactly what happened to `reviews-4/REVIEW-1.md`, which is inside item 5's commit. Either the reviewer should write somewhere the builder does not stage, or the contract should say the builder must stage explicit paths.

8. **The worktree rule protects the source tree and not the build directory.**
   `Packages/*/.build/` in the main tree contains compiled artifacts named `ZZReviewProbeTests` and `ZZProbe2` - probe files no commit has ever contained. The source tree stayed clean and no measurement here is contaminated, but a `--package-path` pointing at the main tree writes to a cache the builder's own gates read. The rule needs to name the build directory.

9. **Item 1's scope exception grants navigation into the one layer this project cannot test.**
   Nothing in the tree renders a view for behaviour; this run added the first test that renders one at all, and it renders it to prove an *absence*. Turning an automatic behaviour into a button therefore moves the feature's correctness somewhere no gate reaches - `reviews-4/REVIEW-1.md` finding 1 measured it: deleting the button's action leaves every gate green. The exception is the right call and the prompt should have said what it costs.

10. **"Do not add a seventh `OSLogStore`-reading test without stating what it costs and why a shared query would not do" gives no way to decline the requirement.**
    Item 5's honest fix logs a row it cannot describe, and a log statement with no reader is the R5-2 shape this project has shipped three times. So the choice was a tenth reader or an unguarded statement. The rule is right to demand the cost be stated; it should also say which way to resolve the conflict, because "state the cost" is not a decision procedure.

**One thing the prompt gets conspicuously right**, recorded because the failures above are worth less without it: the flake dimension. Round 3's 3-in-12 defect passed every other gate, and requiring twelve runs at every stage is what makes "12 of 12" mean something. It cost roughly a third of this run's wall time and it is the cheapest of the five dimensions to justify.

## NEXT ROUND

Reconciled item by item against round 3's list, not summarised.

### Round 3's carried-forward list, item by item

| id | round 3's state | round 4's state |
|---|---|---|
| **R0-5** | CLOSED in round 3 | closed; untouched here |
| **R0-7** | HALF CLOSED - detection for 11 of 13, repair DEFERRED | **unchanged as a repair**, and detection improves to **12 of 13** - item 3 closes Indian/Saka. Ethiopic remains, and is now the whole of the residual |
| **R0-9** | CLOSED in round 3 | closed; untouched here |
| **R0-10(a)** | CLOSED in round 3 | closed; untouched here |
| **R0-10(b)** | still open, inside F8 | **CLOSED** - item 1. An import, a §5.4 flow, a subscription create/edit/delete, a payment-method write and a cancellation-evidence edit all withdraw a prepared export |
| **R0-11** | still open, untouched | **CLOSED** - item 5. The save is keyed on whether a row was mutated rather than on whether it could be described, and the row it cannot describe is named in the log |
| **F8** | still open, untouched | **CLOSED** - item 1. Nothing is written until the user asks; measured by rendering the real screen |
| **F9** | still open, untouched | **CLOSED** - item 2 |
| **F10** | still open, untouched | **CLOSED** - item 4 for `rescheduleSoon`. The background pass is deliberately outside the gate: **N4-3** |
| **F11** | mostly closed; N3-7 remains | unchanged. The trial, pause and usage flows are still unlogged |
| **R4-2** | CLOSED in round 3; residuals N3-6b | closed. Item 4 added four more simulator-hosted coordinator tests to the same file; `start()` and the delegate remain untestable |
| **R4-3** | still open, untouched | **CLOSED** - item 7, by giving the field a reader on the line that summarises the pass. A **user-facing** consumer is still absent: **N4-6** |
| **R5-1** | CLOSED in round 3 | closed; untouched here |
| **RF-1** | historical | historical; every round-4 reviewer verified `.git/FETCH_HEAD` absent and `origin/main` at `406a5a6` |
| **RF-2** | addressed; N3-3 records the gap | **N3-3 CLOSED** - item 6 |
| **RF-4** | corrected form recorded | used throughout; the absolute-bundle-path form is what every measurement in this run used |
| Round 0 §4: `SyncActivationService` wired into nothing | still open | **still open**, untouched |
| Round 0 §4: V2→V3 carry-over verified from the writing context | still open | **still open**, untouched |
| **N2-1** locale-sensitive tests | still open, P2 | **still open**, unmoved - the same five citations under `ar_SA`, `th_TH`, `ja_JP` at every stage head |
| **N2-2** | see R0-7 | see R0-7 |
| **N2-3** | withdrawn | remains withdrawn |
| **N2-4** | recorded as fixed in round 2 | **NOT fixed, and its closure was false.** `reviews-4/REVIEW-AA92CA7.md` finding 1 measured it: giving the failure list "its own entry" moved it to the *same* ~1024-byte per-entry budget, buying only the ~200 bytes of prefix. The list still truncates from six subscriptions upward and names **16 of 64** failed rungs at the device ceiling - measured at `aa92ca7` and at the tip. The false closure propagated into `PROD-READINESS-3.md` and into an earlier version of this table. **Reopened.** This run's own new lines are ~120 characters and are not at risk |
| **N3-1** | open, P2 - two calendars undetectable | **HALF CLOSED** - Indian/Saka is detected in every month and for every field. Ethiopic is not and no threshold reaches it |
| **N3-2** | open, P2 - the `createdAt` detector deserves a proper evaluation | **CLOSED as a decision.** Evaluated and **declined**, on the sensitivity-versus-gap table and the `lastUsedDate` / `pauseEndsOn` characterisation under ITEM 3, which differ by two orders of magnitude. Its K=31 false-positive figure is **not** corrected: three measurements in this run return 62, 63 and 64, and the rule that produced round 3's is unrecorded |
| **N3-3** | open, P2 - no canary on the persistence read | **CLOSED** - item 6, falsified both ways |
| **N3-4** | open, P2 - `aa92ca7` outside every review range | **CLOSED** - item 6, by `reviews-4/REVIEW-AA92CA7.md` on its own range. The wording that produced the gap is fixed in this run's REVIEW RANGES section |
| **N3-5** | open, P2 - the gap card's copy is false for the implausible-days case | **still open**, and now applies to Indian/Saka as well. Re-wording it is new user-facing copy, and this run's exception was granted for the export item only |
| **N3-6** | open, P2 - nothing tells a non-Gregorian user what to do | **CLOSED** - `docs/next-wave.md` now carries the affected calendars, how to tell, the log predicate that names the exact days, the repair, and the fact that Ethiopic gives no signal at all |
| **N3-6b** | open, P2 - `start()` and the delegate untested | **still open**, untouched. `BGTaskScheduler.register`, `UNUserNotificationCenter.current()`, `UNNotification` and `UNNotificationResponse` still have no test-safe construction |
| **N3-7** | open, P3 - trial, pause and usage flows unlogged | **still open**, untouched |
| **N3-8** | open, P3 - the `OSLogStore` readers' cost | **still open and worse**: the count is nine at baseline, not six, and this run adds a tenth. Re-measured spread at baseline: 15.5 s to 126.4 s across one batch of twelve |
| **N3-9** | open, P3 - `SettingsView`'s routing of a refused file has no test | **still open**. This run renders `SettingsView` for the first time, to prove an absence; the import-failure routing is still unexercised |
| **N3-10** | open, P3 - two slack points in item 1's guard | **still open**, untouched. `#expect(caught >= 10)` still has one slot of slack, and the YAML comment still names three of five files |
| **N3-11** | open, P3 - the snooze `deadlinePassed` branch has no test | **still open**, untouched |
| **N3-12** | open, P3 - three cancellation refusal lines unguarded | **still open**, untouched |

### Discovered by round 4

- **N4-1 (P2) - the export button's action is verified by nothing.**
  Deleting the sole call from tap to `AppModel.requestExport(_:)` leaves the whole simulator suite green. Before this run the export was produced unconditionally, so a broken affordance was impossible; after it, a tap that does not reach the model means the user can never produce a backup at all. The remediation shrank the untested surface to one closure with no logic in it and moved the entire state machine onto the model, where eight tests reach it - but the closure itself is unreachable by any test this project can run. Closing it needs a UI-test target, which is a dependency this run may not add.
- **N4-2 (P2) - "the harm is closed for 11 of 13" was measured on the one calendar where it looks best.**
  Round 3 measured Buddhist, whose stored year is *ahead*, so nothing is planned and `scheduledCount=0`. For every **negative**-offset calendar the planner still produces rungs from the corrupt anchor and the pass still schedules them. Measured at round 3's HEAD: Japanese, Minguo, Islamic and Persian each schedule **4 reminders on the wrong days**, with the coverage claim correctly withdrawn. Round 4 adds Indian to that set. So the state closed for those calendars is "wrong reminders, disclosed", not "no reminders" - better than silence and not what the ledger says. Whether to stop scheduling from an implausible anchor is a decision no round has taken.
- **N4-3 (P2) - the background pass is outside the coalescing gate, and the two DO overlap.**
  `handleBackgroundRefresh` owns the completion latch and the expiration race and builds its own `Task`, so a background wake-up landing during a foreground pass runs a second pass - and the two interleave in **45 of 240** iterations (`reviews-4/REVIEW-3.md`), re-measured here at **74 of 180** with a spy modelling the real pass's suspensions. That is F10 itself, still live. Raised from P3 after I recorded the opposite from a single run. Routing it through the chain changes what `expirationHandler` cancels, so the fix belongs with N4-7.
- **N4-4 (P3) - two writers still do not withdraw a prepared export.**
  `NotificationActionHandler` writes state through `model.flows` without passing through `AppModel`, and a bare scheduling pass materializes ledger rows the CSV prints. Both leave a prepared export on offer describing data that has changed. The user-facing copy no longer claims otherwise.
- **N4-5 - CLOSED in the stage-5 remediation**, at zero additional `OSLogStore` reads, inside a window `SchedulingLogTests` already holds open. Left here as a record of the reasoning that nearly shipped it open: the cost I declined to pay was not the cost the fix required.
- **N4-6 (P3) - no surface tells a user their reminders were truncated.**
  `truncatedAfter` now reaches an investigator through the log. The person whose annual renewals were dropped past the 64-slot budget still learns it only from an earlier date in "Reminders scheduled through …", which is honest and does not say why.
- **N4-7 (P2) - the reschedule gate is in the wrong class.**
  Three callers share one `NotificationScheduler`: the coordinator's `rescheduleSoon` (gated), `handleBackgroundRefresh` (not), and `NotificationStatusStore.reschedule()` (not, and the most frequent in ordinary use). Measured overlap with a coordinator pass: **45 of 240** for the background path and **33 of 240** for the store path, re-measured independently at **74 of 180** for the background path with a spy that models the real pass's suspensions. Closing it means putting the gate at the `ReminderScheduling` seam all three share, which is a larger change than F10 was scoped to and needs its own measurement of what `expirationHandler` then cancels.
- **N4-8 (P3) - a coalesced trigger leaves no log line.**
  The trigger name reaches the log only through the trigger-tagged wrapper, which a coalesced trigger never calls, and `queued` is an unconditional overwrite. A burst of five that produced five `pass begin` lines now produces one or two, tagged with whichever arrived last. Inherent to coalescing; a deliberate reduction in the investigative surface this codebase pays for elsewhere.
- **N4-9 (P3) - the two cancellation-evidence withdrawals are unguarded.**
  `appendCancellationEvidence` and `updateCancellationEvidence` withdraw a prepared export and nothing observes it: both return early unless the subscription has an open cancellation episode, so a guard needs a fixture that opens one through the real flow. Multi-step state this test target does not build - the same shape as N3-12.
- **N4-10 (P2) - the §6.2 reconcile diff line has no executable guard, and `aa92ca7`'s file split is what removed it.**
  Deleting that whole log statement is green at `aa92ca7` (196/196) and still green at the tip (209/209); the same deletion at `aa92ca7`'s parent fails. `reviews-4/REVIEW-AA92CA7.md` finding 2.
- **N4-11 (P2) - a sibling's canary masks a deleted canary, wherever tests share a log window.**
  Found twice independently in this run, in commits three rounds apart: `reviews-4/REVIEW-AA92CA7.md` on `NotificationActionLogTests`' `aFailedActionIsRecorded`, and `reviews-4/REVIEW-5.md` on this run's own item 6. `requireDelivered` answers "did the subsystem deliver for this process", which a sibling's canary answers correctly - so the guard is sound and the **falsification** of it is what breaks. Every canary falsification in this tree needs `--filter` or a suppressed subsystem, and none of them says so.
- **N4-13 (P3) - a pre-existing flake in `SyncActivationServiceTests`.**
  Seen once in 24 runs under concurrent load by `reviews-4/REVIEW-2.md`, and never in any of this run's five twelve-run flake batches or at baseline. Not this run's to fix and not this run's to ignore.
- **N4-14 (P3) - the cost quoted for the tenth `OSLogStore` read is one sample of a bimodal quantity.**
  The "~9-11 s" beside item 5's read was observed once. The suite's wall time varies 8x run to run on this host; a cost figure for a log read needs the same twelve-run treatment every other measurement in this run gets, and it did not get it.
- **N4-15 (P3) - the K=31 false-positive figure has three measurements and no definition.**
  62 (strict, excluding anchors that are not valid Ethiopic dates), 63 (this run, two detector definitions) and 64 (`reviews-4/REVIEW-2.md`). Round 3 recorded a sweep and not the rule that produced it. Whoever picks up N3-2 should define the detector before quoting a number for it.
- **N4-12 (P3) - the "~80 ms" window figure is wrong by about 180x and is load-bearing in five files.**
  `OSLogStore.position(date:)` reaches **15.30 / 12.66 / 15.12 seconds** behind `since`, measured. At fifteen seconds a window holds most of a suite, which is why every absence assertion over one has to be pinned to an identifier the test owns. Corrected where round 4 cites it; the four round-3 citations are untouched, because editing them is not this run's scope.

### Remediation after `reviews-4/REVIEW-3.md`

Verdict **PASS-WITH-FINDINGS**. The coalescing itself survived five falsifications including one of the reviewer's own; every finding is about **what the record says**, and three of them are wrong claims of mine.

- **Finding 1 (P2) - my one measured claim about what I did NOT fix was false, and I deleted a true assertion because of it.**
  I wrote that `peakConcurrency == 2` between a background and a foreground pass "does not reproduce: measured, the two passes run one after the other at peak 1." That was one run. The reviewer ran the same scenario 60 times per execution, four times, and measured overlap in **45 of 240 iterations**.
  **Re-measured independently here rather than accepted**, with a spy that suspends six times to model what the real scheduler does before its first write: **74 of 180** - `[(1,34),(2,26)]`, `[(1,39),(2,21)]`, `[(1,33),(2,27)]`. So the reviewer is right and understated it, and the rate is not fixed either: it rises with the number of suspension points the pass has.
  This is the twelve-run flake discipline failing from the other side. The protocol exists because a single green run says nothing about a 25 % event; I drew a conclusion from a single **red** run about an 18-41 % event.
  The claim is corrected in the source and here, and **N4-3 is raised from P3 to P2**: it is not a note about coalescing scope, it is F10 still live on a second path. No assertion is restored, because one that is true 18 % of the time is a flaky test rather than a guard.
- **Finding 2 (P2) - a third ungated entry point, named nowhere.**
  `NotificationStatusStore.reschedule()` calls the shared scheduler directly with `.stateChange`, and every create, edit, delete, §5.4 flow and reminder-time change goes through it. Measured overlapping a coordinator pass in **33 of 240** iterations. It is the most frequent trigger class in ordinary use and the one my record was silent about, while `rescheduleSoon`'s doc comment asserted "Coalesced, not dropped and not queued without bound" with no scope at all.
  **Aggravating, and fixed:** three of my tests fired `.stateChange` and `.backgroundRefresh` through `rescheduleSoon`, and **no production caller passes either value to it**. The suite depicted a gate covering trigger classes it does not cover. Those tests now fire only the five classes that really arrive there.
  The scope is now stated on `rescheduleSoon` itself with both measurements, and **N4-7** records that the fix belongs at the `ReminderScheduling` seam the three callers share rather than in the coordinator.
- **Finding 3 (P3) - `peakConcurrency=3` was one sample of a variable quantity**, presented as measurement discipline working. The reviewer measured 2, 5, 3, 3 - including the 5 my sentence said had not happened. The **pass counts** (5 and 4) are properties of the code and reproduce every time; the peak is a property of the executor. Only the pass count is recorded now.
- **Finding 4 (P3) - a coalesced trigger leaves no log line at all**, and the follow-up is tagged with whichever arrived last. A burst of five that produced five `pass begin` lines now produces one or two. That is an inherent cost of coalescing rather than a defect, and it was disclosed nowhere; it is on `rescheduleSoon` now and carried as **N4-8**.
- **Finding 5 (P3, process) - at the reviewed head the stage recorded no measurements and its work-list row still said "pending".** True, and it is the second stage in a row with this drift after `reviews-4/REVIEW-1.md` finding 9. The rule at the head of REVIEW RANGES says the start is recorded when the stage opens; I recorded stages 2 through 5's starts in one commit late in the run instead. The evidence was inside the range - `54bb611`'s commit message carries the same numbers word for word - which is luck rather than process.

**This remediation lands after every range this run has issued**, because all five stage reviewers and the `aa92ca7` reviewer were dispatched before it. It is therefore reviewed by a final range of its own rather than left outside one; see the REVIEW RANGES table.

### Remediation after `reviews-4/REVIEW-2.md` and `reviews-4/REVIEW-4.md`

Both verdicts are **PASS-WITH-FINDINGS**, and between them they overturn one of this run's own headline corrections and show that four of its new call sites had no observer.

**From `reviews-4/REVIEW-2.md` (stage 2, item 3):**

- **Finding 1 (P2) - my "63 is right, arithmetically" conviction is withdrawn.** The reviewer is right that the 2K+1 argument fails: measured here, the Ethiopic readings of `createdAt ± 31 days` are **63 distinct days spanning a 65-day range**, with gaps, because the thirteenth month is five or six days long and the offset flips between −7 and −8 inside the window. My scan still returns 63 under both plausible detector definitions and the reviewer's returns 64; the disagreement is one anchor wide and lives in a definition round 3 never wrote down. Convicting three documents of an arithmetic error on that basis was wrong, and the conviction is gone. The figure decides nothing either way - the rule is declined on the sensitivity table, where the numbers differ by two orders of magnitude.
- **Finding 2 (P2) - three of four falsification counts did not reproduce.** All four are re-derived above as whole-suite counts. **This is the second falsification table in this run recorded from a partial view of the output**, after `reviews-4/REVIEW-1.md` finding 4 - and the stage-1 remediation claimed to have swept the class when it had swept items 1 and 2 only.
- **Finding 3 (P2) - `docs/next-wave.md` told the user to do two impossible things.** It said to re-pick "the pause resume date, and the last-used date". Verified: `SubscriptionFormModel` touches neither, `lastUsedDate` is only ever written as *today* by `recordUsage`, and an already-paused subscription has no resume-date picker. The section is now a field-by-field table that says which dates have a picker, which needs a resume-and-re-pause, and which repairs only by answering the next usage check-in.
- **P3s routed**: the "round 3's own doc comment" attribution is corrected in the source to `PROD-READINESS-3.md` ITEM 1, where the phrase actually is.

**From `reviews-4/REVIEW-4.md` (stage 4, item 5 + stage 1's remediation):**

- **Finding 1 (P2) - the remediation's guards did not bite where the ledger said they did.** Eight edits applied together left `** TEST SUCCEEDED **`. Each is now guarded, and each was falsified individually rather than as a batch:

  | what was broken | result |
  |---|---|
  | `requestExport`'s body emptied | **2 issues** |
  | `PaymentMethodsStore.delete`'s hook removed | **1 issue** |
  | `preparing` restored to single-valued | **1 issue** - the two-kind test now starts **two** builds, which the first version never did |
  | `exportFailures.removeAll()` instead of per-kind | **1 issue** |
  | the reminder-time withdraw removed | **1 issue** |
  | both cancellation-evidence withdraws removed | **still green** - see below |

  The cancellation-evidence pair remains **unguarded**, and honestly so: `appendCancellationEvidence` returns early unless the subscription has an open cancellation episode, so a guard needs a fixture that opens one through the real flow, which is a multi-step state this test target does not build. Recorded as **N4-9** rather than claimed.
- **Finding 3 (P3) - the new log test's privacy assertion checked an amount the row cannot carry.** It asserted `!line.contains("1299")`, the *edited* amount; the rows carry **1099**, the original. A line leaking the row's own amount would have passed. Both are asserted now.
- **The generation guard covered the success branch and not `catch`.** A failure recorded against a database that has since changed is as stale as a file built from it. Fixed.
- **Finding 2 (P2), and `reviews-4/REVIEW-3.md` finding 5, and `reviews-4/REVIEW-1.md` finding 9 are the same finding, three times.** The reviewed head did not record the item the stage delivered. This is the run's worst process defect and it was restated twice without being fixed: the rule is written at the head of REVIEW RANGES, and the practice was to write the ledger section after the reviewer had already been dispatched.

**A file was split rather than a rule relaxed**, again: `SettingsExportTests.swift` passed both `file_length` and `type_body_length`, and the withdrawal tests moved to `SettingsExportWithdrawalTests.swift`. The spies lose `private` so both files share them.

### Remediation after `reviews-4/REVIEW-5.md`

Verdict **PASS-WITH-FINDINGS**. It confirmed item 6 the hard way - under `OS_ACTIVITY_MODE=disable` all three OttoPersistence log-reading tests fail at `requireDelivered` with the environment message instead of the misdiagnosis - and then found that item 7's guard guarded a string builder.

- **The `pass end` emission is now guarded, at zero cost, and my justification for leaving it open was wrong.** Restoring the pre-fix interpolation at the call site left the composer correct, its unit test green and **all 209 host tests passing** - R4-3 fully restorable behind a green guard. I had declined to close it "because a tenth `OSLogStore` reader is not a trade worth making"; the reviewer closed it inside a query `SchedulingLogTests` already opens, for **no additional reads at all**. Done the same way here, falsified with the reviewer's own mutation: 1 issue.
- **One falsification row was measured under a `--filter` the ledger did not mention.** In the suite as shipped, deleting one test's canary leaves a sibling's canary in the shared window and the run stays green - which is the canary answering its own question correctly, since the subsystem did deliver. The row is corrected above and the substance is now demonstrated the way that actually separates the two causes. **Third occurrence in this run of a falsification quoted at a wider scope than it was measured at**, after `reviews-4/REVIEW-1.md` finding 4 and `reviews-4/REVIEW-2.md` finding 2.

## THE `aa92ca7` REJECT, and what this run does about it

`reviews-4/REVIEW-AA92CA7.md` is the **only REJECT of this run**, and it is a verdict on an **inherited** commit from round 2 - the one N3-4 records as never having been inside any review range.

**N3-4 is closed by that review existing.** The finding was "its diff has been read by nobody in three rounds"; it has now been read, adversarially, in a range of its own. That is what item 6's second half asked for.

**The contract's REJECT cycle does not apply to it, and pretending otherwise would be worse than saying so.** "REJECT → remediate, then a different fresh reviewer re-reviews" is written for a stage this run produced. `aa92ca7` is three rounds old; remediating it means either rewriting history, which is prohibited, or opening round 2's work, which is not on the frozen list. So its three P2s are carried, with their measurements, and the run does not claim to have closed them:

1. **N2-4's closure was false, and this run repeated it.** Splitting the failure list onto "its own entry" moved it to the *same* ~1024-byte per-entry budget. The list still truncates from six subscriptions upward and names **16 of 64** failed rungs at the device ceiling - measured at `aa92ca7` and at the current tip. `aa92ca7`'s own criterion (*"a rung that fails and is then not named is exactly the loss RF-3 exists to repair"*) is still violated. **N2-4 is reopened** in the carried-forward table above.
2. **The `NotificationScheduler+Reconcile.swift` split removed the only executable guard on the §6.2 diff line.** Deleting that whole log statement is green at `aa92ca7` (196/196) and still green at the tip (209/209); the same deletion at `aa92ca7`'s parent fails. The commit's own falsification only proved the *new* line was guarded. **N4-10.**
3. **"the canary covers all four log-reading tests" was false when written.** This run closed it as item 6, independently, before the review landed.

Plus five P3s, one of which is a test that passes for the wrong reason - removing `emitCanary` from `aFailedActionIsRecorded` alone leaves the suite green, because a sibling's canary is in the shared window. **That is the same mechanism `reviews-4/REVIEW-5.md` finding 2 found in this run's own item 6**, arrived at independently from a commit three rounds apart, which is the strongest evidence in this run that the shared-window pattern is a systemic hazard rather than a series of individual slips. **N4-11.**

## A second process risk in the review contract, observed rather than inferred

`reviews-4/REVIEW-5.md` reports catching **a concurrent reviewer doing mutation work in the main working tree** - modified Swift sources with a live process cwd'd at the repo root - which is hard rule 1, and the stronger form of the `.build` contamination this ledger could only infer earlier.

Nothing measured in this run is affected: every gate's `verify.sh` runs from a clean clone of a committed sha, `git status --porcelain` was checked and empty before each measurement, and every flake batch reported test counts identical to the clean-clone run. But the contract cannot detect this by itself, and a builder who did not happen to look would not know.
**The rule needs an enforcement, not a sentence**: reviewers should be given a worktree rather than told to make one.

## FINAL VERIFICATION AT HEAD (`8a56e52`) - all five, measured

| measurement | `reviews-4/BASELINE-4.md` (`2d8913c`) | at HEAD | verdict |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 258 / 124 / 207 = **589** | exit 0, **261 / 127 / 209 = 597** | **+8**, this run's new host tests |
| `swiftlint --strict` | clean, 220 files | **clean, 225 files** | unchanged; five new files, no rule touched |
| simulator suite | 117 / 72 / 36 = 225, 7 known issues | **119 / 72 / 52 = 243**, 7 known issues, `** TEST SUCCEEDED **` | **+18** since baseline |
| non-Gregorian harness | 1 / 1 / 5 | **1 / 1 / 5**, same five citations | unchanged |
| flake, twelve full runs | 12 of 12 | **12 of 12** | unchanged |

Against `reviews-4/BASELINE-4.md`: **+8 host tests, +18 simulator tests, no lint rule relaxed, no test skipped or disabled, no new known issue, and the same five non-Gregorian citations.**

**Five files were split rather than a length rule relaxed**: `NotificationCoordinatorStubs.swift`, `UnreportableInvalidationTests.swift`, `AppModel+Export.swift`, `SettingsExportWithdrawalTests.swift`, and `SpyState` to file scope. Each split was forced by a measured violation, and the two that moved production code were checked for behaviour preservation.

**Assertions changed, and which direction each went:**

- `StoredDayPlausibilityTests.knownUncatchable` loses `indian` - a **strengthening**, and the mechanism round 3 built working: the set exists so that catching one of its members fails the test and forces the record to be updated.
- `realDatesSurvive` loses `1926-08-11` - a **strengthening**: a century-old stored day is now correctly rejected.
- `windowEdges` gains the second bound and the assertion that the two differ - a **strengthening**.
- `aHandledActionIsRecorded` and the rest are untouched.
- Three coordinator tests changed which triggers they fire - **neither**; it is a correction, because the triggers they used never reach that entry point in production.

**No assertion was weakened anywhere in this run**, and that sentence is worth less than the six falsification tables it sits under, all of which were re-derived at least once after a reviewer measured one wrong.

## THE FULL-BRANCH BUILD SWEEP

**Every one of this run's 30 commits builds all three packages** with `--build-tests`, swept in a detached worktree at the end of the run:

```
SWEEP: 30 building, 0 non-building, 30 commits
```

Round 2 shipped a commit that does not compile and recorded it; rounds 3 and 4 have none, and the sweep is the artifact rather than the claim.

## Remediation after `reviews-4/REVIEW-6.md` - the one REJECT of this run's own work

Verdict **REJECT**, on four P2s. It is a fair verdict: the range's one job was that a finding recorded closed is closed, and two were not.

- **Finding 1 (P2) - `docs/next-wave.md` was rewritten to remove an unperformable step and shipped with another one.**
  The new `lastUsedDate` row said the repair was "answering 'Yes - still using it' on a usage check-in". **Verified against the planner rather than argued**: `usageCheckInReminders` counts from `reference = subscription.lastUsedDate ?? billingAnchor(asOf:)`, so a `lastUsedDate` of 2569 schedules the check-in in 2569 and the subscription is planned **zero** of them where a healthy one is planned one. The corruption suppresses the only notification the document named as its repair.
  The control that works is **"I used this today"**, in the Usage section of the subscription's detail screen (`PauseFlowView.swift:171`), and it was named nowhere. The row now names it, says explicitly not to wait for a notification, and the section closes with the general form: **every repair here is something you do in the app on purpose, because a subscription with any corrupt day schedules no reminders at all.**
- **Finding 2 (P2) - the range's only production behaviour change had no observer.** The `catch`-branch generation guard could be deleted with the whole simulator suite green, and the ledger recorded it as "Fixed." beside a table where every other row carried an issue count. Guarded now, and falsified: **1 issue**, `(.failed(...)) == .notPrepared`.
- **Finding 3 (P2) - three announced corrections were never swept into the surfaces a later round reads.** A commit titled "Correct the concurrency claims the stage-3 review measured false" left ITEM 4's body saying the overlap "does not reproduce", a `NOT DEFECTS` row saying "peak concurrency 3", and N4-3 still at P3 saying overlap was "not established"; a commit titled "Withdraw a wrong correction" left the withdrawn 2K+1 conviction verbatim in the prompt-defects section. All four are corrected in place. **The cause is structural and worth naming: this ledger is appended to, so a correction lands in a new section while the sentence it corrects stays where a reader meets it first.**
- **Finding 4 (P2) - findings from three reviews were neither fixed nor carried.** The disposition table below now accounts for **every one of the 56 findings across all seven reviews**, which is the only form of that claim worth making.
- **P3s routed**: the R4-3 emission assertion is pinned to `.significantTimeChange`, a trigger no other test in that target uses, plus an `allSatisfy` over every pass-end line in the window (the reviewer made an unpinned version pass on a sibling's line); `OttoLog.swift`'s doc comment loses the withdrawn cost justification; `indianIsCaughtByTheAsymmetry`'s first assertion was two literals and could not fail - it now applies round 3's rule as a function to the same constants and checks the two verdicts agree everywhere the change was not aimed; the month loop now varies **both** Saka offsets rather than only a month the rule never reads; the concatenated doc comment in `AppModel+Export.swift` is split; and `BillingEventRepository`'s protocol contract now states that the return value is short by one per unmappable row, which is the meaning R0-11's fix changed.

### Every finding, and what happened to it

Seven reviews, 56 findings. **Fixed** means a guard bites; **carried** means it is in NEXT ROUND with its measurement; **declined** means it is answered and not acted on.

| review | findings | fixed | carried | declined / process |
|---|---|---|---|---|
| REVIEW-1 (stage 1) | 9 | 2, 3, 4, 5, 6, 7, 8 | 1 → N4-1 | 9, process, restated in the rule |
| REVIEW-2 (stage 2) | 10 | 2, 3, 4, 7, 8, 9 | 10 → N4-13 | 1 **withdrawn correction**; 5, 6, process |
| REVIEW-3 (stage 3) | 5 | 1, 3 | 2 → N4-7, 4 → N4-8 | 5, process |
| REVIEW-4 (stage 4) | 10 | 1 (five of six), 3, 4, 8, 10 | 1's evidence path → N4-9, 9 → N4-14 | 2, 5, 6, 7, process/record |
| REVIEW-5 (stage 5) | 6 | 1, 2, 5, 6 | 3 → N4-12 | 4, process |
| REVIEW-AA92CA7 | 8 | 3 (by item 6) | 1 → **N2-4 reopened**, 2 → N4-10, 4, 5, 8 → N4-11 | 6, 7, record |
| REVIEW-6 (remediations) | 9 | 1, 2, 3, 7, 8 | 5, 6 → N4-15 | 4 = this table; 9, sweep count restated |

**The two findings this run declines to act on, and why:**

- **REVIEW-4 finding 9** - the tenth `OSLogStore` read costs more than the number stated beside it. True; the figure came from one observation of a bimodal quantity, which is the same error as the peak-concurrency one. The read stays, because the alternative is an unguarded log statement, and the corrected cost is carried as **N4-14** rather than restated from another single sample.
- **REVIEW-2 finding 10** - a pre-existing flake in `SyncActivationServiceTests`, seen once in 24 runs under load and never at baseline. Untouched by this run and not this run's to fix; **N4-13**.
