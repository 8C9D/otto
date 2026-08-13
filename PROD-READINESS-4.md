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
| 1 | **F8 + R0-10(b)** | Both exports written to `tmp` on every appearance of Settings, unrequested; `ShareLink` hands out the pre-import file after an import | pending |
| 2 | **F9** | `csvField` does not neutralize a leading `=`, `+`, `-` or `@` | pending |
| 3 | **N3-1 / N3-2** | Ethiopic (+8y) and Indian/Saka (-78y) defeat round 3's plausibility rule | pending |
| 4 | **F10** | `rescheduleSoon` spawns an unstructured `Task` per trigger with no coalescing | pending |
| 5 | **R0-11** | `invalidateOutdatedUpcomingEvents` can leave uncommitted soft-deletes while reporting "nothing invalidated" | pending |
| 6 | **N3-3 + N3-4** | `MappingLogPrivacyTests` reads `OSLogStore` with no canary; `aa92ca7` has never been inside any review range | pending |
| 7 | **R4-3** | `ScheduleOutcome.truncatedAfter` has no consumer anywhere | pending |

Terminal states are **RESOLVED** (with artifact evidence), **DEFERRED** (with reason), or **REJECTED TWICE** (reverted, objection recorded).
There are no others.

## REVIEW RANGES

**This run's FIRST range starts at the branch point, `2d8913c`**, which is the wording round 3's rule was missing and the reason `aa92ca7` escaped three rounds.
Each later stage's range starts at the previous stage's **reviewed head**, and every start is recorded **when the stage opens**, not when its verdict lands.

| stage | range passed to the reviewer | reviewed head | verdict |
|---|---|---|---|
| 0 | - (baseline only) | - | no review; its commit is inside stage 1's range |
| 1 - items 1 + 2 | `2d8913c..6ef51ee` | `6ef51ee` | |
| 2 - item 3 | | | |
| 3 - item 4 | | | |
| 4 - item 5 | | | |
| 5 - items 6 + 7 | | | |
| aa92ca7 | `aa92ca7^..aa92ca7` | `aa92ca7` | |

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
- **`AppModel.exportJSONFile()` and `exportChargesCSVFile()` are gone.** `prepareExport(_:)` is the only path that writes an export file, so there is no second, unrecorded writer for the defect to come back through.
- **`ExportKind`** is new public API in `OttoServices`, beside `ImportPickerOutcome`.

**The scope exception was taken and is bounded.** The two rows become buttons - navigation the prompt's item-1 allowance explicitly permits - and the footer gains one sentence: *"Otto builds a file only when you ask for it, and stops offering it once your data changes - a backup is a complete copy of your finances, and a stale one is worse than none."* No settings key, no new screen, no dependency.

### Falsified four ways, at the call site each time

Each mutation printed the text it removed and asserted exactly one occurrence before running (process rule 2).

| what was broken | result |
|---|---|
| an appearance-time `prepareExport` pair re-added to `ExportSection` | **3 issues** - `snapshotCalls == 0` fails, both `preparedExport(...) == nil` fail, and the two files are back in the simulator's `tmp` |
| `withdrawPreparedExports()` deleted from `flowFinished()` | **2 issues** - the import withdraws neither export |
| `withdrawPreparedExports()` deleted from the `onMutation` hook | **1 issue** - a delete no longer withdraws |
| `prepareExport` stops recording the URL | **4 issues across 3 tests** |

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

| what was broken | result |
|---|---|
| the neutralizer not called at all | 5 issues over 2 tests |
| the four triggers the finding names removed, TAB and CR kept | 5 issues over 2 tests |
| neutralize **after** quoting instead of before | 2 issues - the apostrophe lands outside the quotes |
| the neutralizer applied to the **amount** column | 8 issues - the control, and the reason the row is asserted whole |

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

| K(days) | this run | round 3's ledger | `reviews-3/REVIEW-3.md` |
|---|---|---|---|
| 1 | 3 / 4001 (0.07%) | 3 | 2 |
| 3 | 7 / 4001 (0.17%) | 7 | - |
| 7 | 15 / 4001 (0.37%) | 15 | 14 |
| 31 | **63** / 4001 (1.57%) | **64** | **63** |

**64 is wrong and 63 is right, arithmetically**: a window of ±K days over a single collision point contains exactly 2K+1 days, and 3, 7, 15, 63 is that sequence. Round 3's ledger overrode `reviews-3/REVIEW-3.md`'s correct 63 with 64, and `reviews-3/REVIEW-4.md` recorded that it "re-derived it to the digit". Three documents agreed on a number that 2K+1 refutes.

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

| what was broken | result |
|---|---|
| back to round 3's symmetric century | 6 domain issues **and 2 through the real scheduler** - Indian escapes both |
| backward bound set to **78**, Indian's exact offset | the same 6 + 2; pins that the eight-year margin is load-bearing and 70 is not padding |
| both bounds set to 70 (asymmetry removed the other way) | 5 issues - a far-future prepaid term is rejected, which is the other half of why it is asymmetric |
| the scheduler stops calling `implausibleStoredDays` | 6 issues over 4 tests |

### What a user on those two calendars is actually left with

**Indian/Saka**, as of this run: the same position as the other eleven. Reminders are still scheduled and still on the wrong days (see N4-2), Today no longer claims coverage, the gap card appears, the log names the exact days, the list shows the wrong dates in plain sight, and `docs/next-wave.md` now tells them how to repair it.

**Ethiopic**: unchanged and undetectable. No card, no log line, no signal of any kind from Otto. Four reminders arrive on the wrong days of the month while Today states full coverage. The only thing that is visibly wrong is the date on the subscription list, which is off by eight years and is the one thing a user might notice unaided. `docs/next-wave.md` now says so explicitly, which is the whole of what this run can do for them.

Live exposure for both remains nil under ASSUMPTION 1, and no locale defaults to either calendar.
