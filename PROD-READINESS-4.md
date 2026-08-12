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
| 1 - items 1 + 2 | `2d8913c..a412a07` | `a412a07` | |
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
