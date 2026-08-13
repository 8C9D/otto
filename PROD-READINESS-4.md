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
| 1 - items 1 + 2 | `2d8913c..6ef51ee` | `6ef51ee` | **PASS-WITH-FINDINGS** (`reviews-4/REVIEW-1.md`) |
| 2 - item 3 | `6ef51ee..00cb0f1` | `00cb0f1` | (`reviews-4/REVIEW-2.md`) |
| 3 - item 4 | `00cb0f1..54bb611` | `54bb611` | (`reviews-4/REVIEW-3.md`) |
| 4 - item 5 + stage 1's remediation | `54bb611..05ff987` | `05ff987` | (`reviews-4/REVIEW-4.md`) |
| 5 - items 6 + 7 | `05ff987..1a1d23b` | `1a1d23b` | (`reviews-4/REVIEW-5.md`) |
| aa92ca7 | `aa92ca7^..aa92ca7` | `aa92ca7` | (`reviews-4/REVIEW-AA92CA7.md`) |

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

### One claim was written, measured, and deleted rather than shipped

`handleBackgroundRefresh` is outside the gate - it owns the completion latch and the expiration race and builds its own `Task`.
The obvious assertion, `peakConcurrency == 2`, **does not reproduce**: measured, the two passes run one after the other at peak 1.
The test asserts only that the background pass is not coalesced, which is true of every run, and the source says no claim is made about overlap.
Carried as **N4-3**.

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
| the canary emission deleted | fails at `requireDelivered`: *"The unified log delivered NOTHING for this process ... This is an environment failure ... Do not fix it by deleting the assertions it guards."* |
| the **production** skip statement deleted, canary intact | fails at the target line: *"the store logged nothing for the record it skipped"* |

**Before this change both produced the second message.**

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

**What that does not guard is the emission itself.** Deleting the `OttoLog.scheduling.notice` call leaves the composition test green. That line was already unguarded before this run - no test read it - so this does not make it worse, and it is not closed either. **N4-5.**

**A user-facing consumer is still absent**, and adding one is new copy this run may not write: the person whose annual renewals were dropped past the budget learns it only from an earlier date in "Reminders scheduled through …". **N4-6.**

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
