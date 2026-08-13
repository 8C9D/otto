# REVIEW-5 - adversarial review of stage 5

Range `05ff987..1a1d23b`, branch `prod-readiness-4/2026-08-12`, reviewed head `1a1d23b`.
Items 6 (N3-3 + N3-4) and 7 (R4-3).

verdict: PASS-WITH-FINDINGS

## Summary

The code in this range is small, correct, and does what the ledger says it does in production.
Four commits, two of them code: `5bdcd20` adds the missing canary to `MappingLogPrivacyTests` and deletes that file's duplicate `OSLogStore` helper in favour of the shared one; `8a62c0c` lifts the `pass end` line's fields into `OttoLog.passEndFields` and adds `truncatedAfter` to them.
No SwiftData schema file is touched, no lint rule is touched, no workflow is touched, no assertion is removed, nothing is disabled, and the range adds **zero** new `OSLogStore` readers - it net-removes one duplicate query helper.
All five baseline dimensions reproduce at `1a1d23b` exactly as the ledger's verification table records them, and every commit in the range builds all three packages.

Item 6 is genuinely closed, and I confirmed it the hard way rather than on the ledger's word: under `OS_ACTIVITY_MODE=disable` all three of OttoPersistence's log-reading tests now fail at `requireDelivered` with the environment message instead of the misdiagnosis, and deleting the production `Skipping unmappable record` **statement** fails `MappingLogPrivacyTests.swift:104` with exactly the quoted message.
That is the check this stage was set up to be judged on, and it passes.

What is not sound is the other half of that pairing.
**The new observer for `truncatedAfter` observes a string builder, not the log.** `OttoLog.passEndFields` is reached in production - `NotificationCoordinator`, `NotificationActionHandler` and `NotificationStatusStore` all route through the trigger-tagged `reschedule`, and I measured the composed line actually reaching the unified log with the new field in it. But nothing asserts that. I restored the exact pre-fix line at the call site, leaving `passEndFields` intact and correct, and all 209 OttoUI host tests passed: the whole of R4-3 can be put back in production with the ⛔-marked guard green.
The builder disclosed this as N4-5, but justified it with a cost - "a tenth reader for one field is not a trade worth making" - that is not the cost on the table. `SchedulingLogTests` already holds a `scheduling`-category window open in two tests that already drive a scheduler pass. I closed N4-5 inside that existing window with **zero** additional `OSLogStore` reads; it is green at head and it catches the regression.

One recorded falsification does not reproduce. The ledger's row "the canary emission deleted → fails at `requireDelivered`" is true only under a `--filter` the ledger does not mention; in the suite as shipped, a **sibling test's** canary sits in the window and the full run stays green. The conclusion the row supports is nevertheless true, verified independently above. This is the same class of defect `reviews-4/REVIEW-1.md` finding 4 recorded at stage 1, recurring after it was flagged.

The remaining findings are record defects at the reviewed head: an artifact cited that does not exist, a ranges table that violates the ledger's own recording rule (repaired by later work), a work list whose terminal-state column still reads `pending` for items its own body declares RESOLVED, and one shipped source comment that overstates its finding.

No P1. Nothing in this range hides an error, relocates a bug, smuggles a feature, or weakens a test.

## What I ran

All mutation work was done in three detached worktrees I created under my scratchpad (`rev5/wt-head`, `rev5/wt-mut`, `rev5/wt-sweep`), all at `1a1d23b`. No command's `--package-path` pointed into the main tree. No network call, no commit, no push, no `git checkout --` in the main tree, no device.

### The five baseline dimensions, re-measured at `1a1d23b`

**1. `./scripts/verify.sh` - exit 0.**

```
== VERIFIED: 1a1d23b4bd624055e6f09bddfa4afd270fd68c2a builds, tests, and lints from a clean clone
   OttoDomain: 261
   OttoPersistence: 127
   OttoUI: 209
   total: 597 tests
```

Ledger's stage-5 column: `exit 0, 261 / 127 / 209 = 597`. **Exact match.**

**2. `swiftlint --strict` - clean.**

```
Done linting! Found 0 violations, 0 serious in 224 files.
```

Ledger: `clean, 224`. **Exact match.**

**3. Simulator suite**, run from `rev5/wt-head/Packages/OttoUI`, `-destination "id=<simulator-udid>"` - exit 0.

```
✔ Test run with 119 tests in 22 suites passed after 8.266 seconds.
✔ Test run with  72 tests in 12 suites passed after 0.100 seconds.
✘ Test run with  48 tests in  8 suites passed after 3.222 seconds with 7 known issues.
** TEST SUCCEEDED **
```

Ledger: `119 / 72 / 48 = 239, 7 known issues, ** TEST SUCCEEDED **`. **Exact match.** The 7 known issues are the same `EmptyStateTests` accessibility-label assertions the baseline records; this host vends no AX tree.

**4. Non-Gregorian harness** - bundle path absolute, run from the worktree root, per `CalendarEraTests.swift`'s header. **1 / 1 / 5, the same five citations.**

```
th_TH@calendar=buddhist   1 issue   DisplayFormattingTests.swift:49  ("Aug 15, 2569 BE")   == "Aug 15, 2026"
ja_JP@calendar=japanese   1 issue   DisplayFormattingTests.swift:49  ("Aug 15, Reiwa 8")   == "Aug 15, 2026"
ar_SA@calendar=islamic-umalqura  5 issues
    DisplayFormattingTests.swift:49   ("Rab. I 2, 1448 AH") == "Aug 15, 2026"
    DisplayFormattingTests.swift:59   ("Every ٤٥ days")     == "Every 45 days"
    DisplayFormattingTests.swift:68   ("١ subscription")    == "1 subscription"
    DisplayFormattingTests.swift:69   ("٣ subscriptions")   == "3 subscriptions"
    NotificationReconciliationTests.swift:170  ("FoodApp charges $15.99 on Rab. I 12.") == "... on Aug 25."
```

Each run reports `Test run with 209 tests in 38 suites failed`. **Exact match** with the ledger and with `reviews-4/BASELINE-4.md`.

**5. Flake rate** - `swift test --package-path Packages/OttoUI`, twelve consecutive runs in a clean worktree at `1a1d23b`:

```
FLAKE_OTTOUI_PLACEHOLDER
```

`swift test --package-path Packages/OttoPersistence`, six runs, because this range touches a log-reading test in that target:

```
FLAKE_PERSIST_PLACEHOLDER
```

### Per-commit build sweep - all four commits, all three packages

```
OK   5bdcd20 OttoDomain      OK   5bdcd20 OttoPersistence      OK   5bdcd20 OttoUI
OK   8a62c0c OttoDomain      OK   8a62c0c OttoPersistence      OK   8a62c0c OttoUI
OK   2082b69 OttoDomain      OK   2082b69 OttoPersistence      OK   2082b69 OttoUI
OK   1a1d23b OttoDomain      OK   1a1d23b OttoPersistence      OK   1a1d23b OttoUI
```

`swift build --build-tests --package-path Packages/<pkg>` in `rev5/wt-sweep`, detaching onto each commit in turn. 12 / 12 clean.

### Falsifications

Every mutation was applied by a script that printed the exact lines it removed and asserted the occurrence count was 1 before writing.

| # | what I broke | result |
|---|---|---|
| M1 | `OttoLogProbe.emitCanary()` deleted from `MappingLogPrivacyTests.swift:83` | **full suite GREEN**, 127/127 - see finding 2 |
| M1' | same, run as `--filter "MappingLogPrivacyTests"` | fails at `:97` with the environment message |
| M2 | production statement `OttoStore.swift:169-171` deleted, canary intact | fails at `:104` with *"the store logged nothing for the record it skipped"* - **the ledger's quoted message, verbatim**; 1 issue, and no other test in the tree notices |
| E1 | nothing broken; `OS_ACTIVITY_MODE=disable` on the unmutated head | all three persistence readers fail at `requireDelivered` (`CorruptWatermarkTests:58`, `MappingLogPrivacyTests:98`, `UnreportableInvalidationTests:153`) with the environment message |
| M3 | the `pass end` emission `OttoLog.swift:174-176` deleted | **209/209 GREEN** - confirms N4-5 |
| M4 | `truncatedAfter=` dropped from `passEndFields` | 3 issues at `SchedulingLogTests.swift:60,61,62`; both lines render byte-identically as the ledger quotes them |
| M5 | `passEndFields` left intact but the call site reverted to the exact pre-fix line | **209/209 GREEN** - the whole finding restored in production, guard green. See finding 1 |
| D1 | my own 4-line guard installed in `SchedulingLogTests`' existing window, then M5 applied | fails: `(passEnd → "pass end trigger=foreground permission=authorized scheduled=0 coveredThrough=2026-11-09 ledgerFailures=1").contains("truncatedAfter=")` |

M4's two lines, verbatim, confirming the ledger's quoted evidence for item 7:

```
pass end trigger=foreground permission=authorized scheduled=64 coveredThrough=2026-09-01 ledgerFailures=0
```

### The window dump that explains M1

Under M1, printing the whole window `MappingLogPrivacyTests` opens at `since`:

```
REV5-WINDOW count=10 since=2026-08-13 01:05:29 +0000
REV5-LINE otto.test.canary
REV5-LINE watermark unreadable: id=00000000-0000-0000-0000-000000000001 stored=20260230
REV5-LINE watermark unreadable: id=00000000-0000-0000-0000-000000000003 stored=0
REV5-LINE watermark unreadable: id=00000000-0000-0000-0000-000000000006 stored=0
REV5-LINE Skipping unmappable record: StoredSubscription.status is missing
   ... (3 more)
REV5-LINE Skipping unmappable record: StoredSubscription.cycleStartDay holds an invalid value
```

The canary is `CorruptWatermarkTests.swift:45`'s, and that test's own three `watermark unreadable` lines follow it.

## Findings

### 1 - P2. The R4-3 guard never touches the production path, and the stated reason it cannot is false

**Evidence.**
`Packages/OttoUI/Sources/OttoServices/OttoLog.swift:174-176` is the only production emission of the composed line.
`Packages/OttoUI/Tests/OttoServicesTests/SchedulingLogTests.swift:45-72` is its only guard, and it calls `OttoLog.passEndFields` directly - it never reads a log.

M5: leave `passEndFields` intact and correct, and revert the call site to the exact pre-fix interpolation with no `truncatedAfter`:

```
✔ Test run with 209 tests in 38 suites passed after 36.244 seconds.
```

That is the entire finding R4-3 reintroduced in production - the line that "carried every OTHER field of the outcome and not that one" - with the ⛔-marked test green.
M3, deleting the emission altogether, is also green (209/209), which is the narrower gap the builder disclosed.

The disclosed reason, `OttoLog.swift:96-99`:

> Composed here rather than interpolated at the call site so a test can read the line without opening `OSLogStore` - the tree already blocks on that daemon nine times, and a tenth reader for one field is not a trade worth making.

and `PROD-READINESS-4.md` item 7: *"The tree already blocks on that daemon nine times and this run adds a tenth for item 5; an eleventh for one field is not a trade worth making."*

**A new reader was never required.** `SchedulingLogTests.swift:179-190` already defines a `scheduling`-category `OSLogStore` query, used at `:106` and `:155` by two tests that already drive a full scheduler pass and already call `requireDelivered` on the window.
`NotificationScheduler` conforms to `ReminderScheduling` (`NotificationScheduler.swift:11`), so the trigger-tagged entry point is available on `fixture.scheduler`.
I changed `theEmittedSkipLineNamesTheDays` (`:149-153`) to pass `trigger: .foreground` and added a `#require` for the pass-end line **in the window it already reads** - zero additional `OSLogStore` reads, no new query, no new test:

```swift
let passEnd = try #require(
    lines.last { $0.hasPrefix("pass end trigger=foreground") },
    "the pass emitted no pass-end line"
)
#expect(passEnd.contains("truncatedAfter="))
```

Green at `1a1d23b` (`✔ Test run with 5 tests in 1 suite passed`), and under M5 it fails with the line quoted in the falsification table above.
That also independently proves the good half of the item: the composed line, with the new field, does reach the unified log in a real pass.

**Why the builder missed it.** It priced the wrong thing. The question it asked was "what does a tenth `OSLogStore` reader cost", and the answer is correctly "too much"; the question it never asked was whether a window on that category was already open in the same file. The prompt's constraint is phrased as *"why a shared query would not do"* - and here a shared query does.

**Severity.** P2, not P1: `truncatedAfter` genuinely reaches the log at `1a1d23b`, so the finding is closed in production today. What is absent is anything that keeps it closed, on a field whose entire defect was that no one was looking at it.

### 2 - P3. Item 6's first recorded falsification does not reproduce in the suite as shipped

**Evidence.** `PROD-READINESS-4.md`, item 6:

> | the canary emission deleted | fails at `requireDelivered`: *"The unified log delivered NOTHING for this process ..."* |

Measured. Removing `OttoLogProbe.emitCanary()` from `MappingLogPrivacyTests.swift:83` (1 occurrence, printed):

```
✔ Test run with 127 tests in 26 suites passed after 45.266 seconds.
```

The full OttoPersistence suite stays green. The window dump above shows why: `requireDelivered` scans `persistenceLines(since:)`, which is the whole `persistence` category for the process, and `CorruptWatermarkTests`' canary is inside it. The row reproduces only under `--filter "MappingLogPrivacyTests"`, a condition the ledger does not state.

**The conclusion the row supports is nevertheless true**, which I verified without relying on it: `OS_ACTIVITY_MODE=disable` at the unmutated head fails all three persistence readers at `requireDelivered` with the environment message, `MappingLogPrivacyTests.swift:98` among them. And the second row reproduces exactly - deleting the production statement fails at `:104` with the quoted message. **N3-3 is closed.**

**Consequence beyond the record.** `MappingLogPrivacyTests`' own `emitCanary()` call is redundant in any full-suite run; it can be deleted and every gate in this contract stays green, which is precisely the kind of line a future refactor removes.

**Why the builder missed it.** The falsification table is written while the mutations are being run, in whatever run mode was convenient at the time, and is never re-derived against the shipped suite. `reviews-4/REVIEW-1.md` finding 4 recorded this same defect at stage 1 - "the row was recorded against an earlier draft of the test and not re-run" - and it recurred at stage 5.

### 3 - P3. The "~80 ms" window figure is wrong, and it is the number every contamination judgement in the tree is made against

**Evidence.** `MappingLogPrivacyTests.swift:91-93`, inside this range's own diff context:

> `OSLogStore.position(date:)` is approximate: it reaches ~80 ms behind `since`

The same figure appears at `SchedulingLogTests.swift:89`, `BoundaryLogTests.swift:77` and `:108`, and `UnreportableInvalidationTests.swift:131`.
Measured: the window this test opens at `since` contained an entire preceding test's emissions - `CorruptWatermarkTests`' canary plus its three `watermark unreadable` lines. It reaches back at least one whole test, not ~80 ms.

The range's own new code handles this correctly (`:99` filters, `:103` discriminates on `cycleStartDay`), so this is not a defect introduced here. It is flagged because it is load-bearing: it is the stated basis for item 5's decision to pin on subscription index 7011, and for every "the window legitimately contains lines from tests that ran just before this one" comment in the tree, and it understates the exposure by orders of magnitude.

**Why the builder missed it.** The figure is inherited from round 2 and has been copied forward through three rounds without being re-measured; this range copied the sentence into its new comment rather than checking it.

### 4 - P3. Two artifact claims in item 6 point at things that do not exist at the reviewed head

**Evidence.**

```
$ git ls-tree --name-only 1a1d23b reviews-4/
reviews-4/BASELINE-4.md
reviews-4/REVIEW-1.md
```

The ledger at `1a1d23b` says of item 6: *"**Second half is the review itself**, `reviews-4/REVIEW-AA92CA7.md`"*, and *"`aa92ca7` ... is re-derived in `reviews-4/BASELINE-4.md` and reviewed by its own fresh reviewer on its own range ... **Its verdict is in the REVIEW RANGES table**."*
The file is absent, and that table's `aa92ca7` verdict cell is empty. The sentence is written in the perfect tense about work with no artifact. It is still absent at `d2b9c85`.

Separately, the REVIEW RANGES table at `1a1d23b` records **no range and no reviewed head at all** for stages 2, 3, 4 and 5, and no verdict for stage 1 - although `reviews-4/REVIEW-1.md` exists at that very commit carrying `verdict: PASS-WITH-FINDINGS`, and the ledger's own rule at `:61` is that "every start is recorded **when the stage opens**, not when its verdict lands". `1a1d23b` is itself the commit titled "Record the five-dimension verification at every stage head", and it names heads (`a412a07`, `b054506`, `8a62c0c`) that the ranges table does not carry.

**Later work repaired half of this, outside my range.** `d609790` "Open the remaining review ranges" fills every row of the table, including `05ff987..1a1d23b` for stage 5. That commit is after my reviewed head; nothing in it touches code (`git diff --name-only 1a1d23b d2b9c85` → `PROD-READINESS-4.md` only).

**Third, and this one is introduced by my range.** Commit `2082b69` creates N4-5 and N4-6, and `1a1d23b` has no section that collects them: `git show 1a1d23b:PROD-READINESS-4.md | grep '^## '` lists no NEXT ROUND, and the three carried items of this run (N4-3, N4-5, N4-6) exist only as bold labels inside item bodies. Rounds 1-3 each carried a NEXT ROUND section, and `PROD-READINESS-4.md:42` relies on one existing ("Everything else in rounds 1, 2 and 3's NEXT ROUND stays in NEXT ROUND"). At `d2b9c85` the ledger gains NOT DEFECTS and DEFERRED sections and still none of the three appears in either. N4-5 is the gap finding 1 is about, and the only place a round-5 reader will find it is the last paragraph of item 7.

**Why the builder missed it.** The ranges table is maintained by hand and the recording rule it states is stricter than the practice; the `aa92ca7` sentence describes the plan for N3-4 rather than its state.

### 5 - P3. The frozen work list still reads `pending` for both of this stage's items

**Evidence.** `git show 1a1d23b:PROD-READINESS-4.md`, work list:

```
| 6 | **N3-3 + N3-4** | `MappingLogPrivacyTests` reads `OSLogStore` with no canary; ... | pending |
| 7 | **R4-3** | `ScheduleOutcome.truncatedAfter` has no consumer anywhere | pending |
```

while the item bodies read "**First half RESOLVED**, stage 5, commit `5bdcd20`" and "**RESOLVED**, stage 5, commit `8a62c0c`", and the contract two lines under that table reads: *"Terminal states are **RESOLVED** (with artifact evidence), **DEFERRED** (with reason), or **REJECTED TWICE** (reverted, objection recorded). There are no others."*
All seven rows still read `pending` at the current branch head `d2b9c85`.

**Why the builder missed it.** The per-item sections are the surface it writes; the summary table is the surface a later reader checks, and nothing reconciles them.

### 6 - P3. A shipped source comment overstates the finding it documents

**Evidence.** `SchedulingLogTests.swift:34-36`:

> `ScheduleOutcome.truncatedAfter` reached nothing at all - the scheduler set it, `coveredThrough` was derived from the same local, and **no reader anywhere** asked the outcome for it.

At `05ff987`, two tests already read it:

```
NotificationSchedulerTests.swift:72   let truncatedAfter = try #require(outcome.truncatedAfter)
CatchUpDeliveryTests.swift:241        #expect(outcome.truncatedAfter != nil)
```

The ledger's own prose is correctly qualified - *"no reader anywhere - production, UI or store"* - and so is `OttoLog.swift:88-90`. Only the test's comment drops the qualifier, and it is the version a future reader meets first.

**Why the builder missed it.** The comment was compressed from the ledger paragraph and lost the clause that made it true.

## Explicit checks

**Fabricated or unreproducible findings; verbatim failure messages reproduced.**
Reproduced. Item 6's second row (production statement deleted → `:104`, *"the store logged nothing for the record it skipped"*) reproduces exactly. Item 7's quoted byte-identical `pass end` line reproduces exactly under M4. Item 6's **first** row does not reproduce in the shipped suite - finding 2. The environment message itself is real and I triggered it three ways.

**Citations that do not say what they are claimed to say.**
Two. `reviews-4/REVIEW-AA92CA7.md` and the REVIEW RANGES verdict cell (finding 4); `SchedulingLogTests.swift:36`'s "no reader anywhere" (finding 6).

The `PROD-READINESS-2.md` citation underpinning N3-3 - that it "recorded the remedy as applying to all four log-reading tests when it applied to three" - I checked and it **holds exactly**. `PROD-READINESS-2.md:87` names the four dependent tests, `MappingLogPrivacyTests.theEmittedLineIsRedacted` first among them, and says "the canary tells you which failure it is ... for those four tests"; `:301` claims "**Each** log-reading test now emits a canary line on the category it is about to read and checks for it in the **same** query", which was untrue of exactly one of them. At `05ff987` `OttoLogProbe.persistenceLines` and `requireDelivered` already existed and `CorruptWatermarkTests:45` already emitted a canary, while `MappingLogPrivacyTests` did not. The item found a real gap in a real prior claim.

**Severity inflation or deflation.**
None found. Item 6 is correctly scoped as a test-infrastructure fix, not a production fix. Item 7's ledger is unusually honest: N4-5 (emission unguarded) and N4-6 (no user-facing consumer) are both stated plainly rather than glossed. My finding 1 is not that the gap was hidden - it is that the reason given for it is wrong and a free remedy existed.

N4-6's deferral in particular is correctly scoped, and I checked it rather than assuming. `ScheduleOutcome` is published whole through `NotificationStatusStore.outcome` (`NotificationStatusStore.swift:18`, `public private(set)` on an `@Observable` class), so `truncatedAfter` is already in the UI's hands with no plumbing to add - the only missing piece really is user-facing copy, which this run's scope forbids outside the export item. Deferring it is the right call, not an evasion.

**Features smuggled past the no-features rule.**
None. The range touches one production file, `OttoLog.swift`, and the only production behaviour change is one extra field in one diagnostic log line. No user-facing copy, no navigation, no new surface. `docs/next-wave.md` is not touched. The export item's granted exception is not used here.

**Any SwiftData schema change.**
None. `git diff --name-only 05ff987 1a1d23b` returns five files, none under `Schema/`, none matching `Stored*`, `*Migration*` or `OttoSchemaV*`. The schema remains frozen at V3.

**Prohibited actions.**
None observed in the range: no `.github/workflows/` change, no `.swiftlint.yml` change, no `Package.swift` or `project.yml` change, no new dependency, no new config key, no Swift language mode or SDK change. No reformatting or reorganisation - the only file movement is the deletion of a duplicated private helper in favour of an existing shared one, which is the item's own remedy.

**Fixes that relocated a bug rather than removed it.**
No. Item 6 removes a duplicate `OSLogStore` query rather than moving it. Item 7 moves string composition from the call site into a named function; the emitted text is unchanged apart from the added field, which I confirmed by reading the real emitted line in both shapes.

**Error handling that hides errors.**
Nothing in this range catches, discards or downgrades an error. `requireDelivered` is a `#require` that throws and stops the test with a diagnostic, which is the opposite failure mode.

**Verification that does not exercise the changed path.**
Yes, for item 7 - finding 1. The changed production path is `OttoLog.swift:174-176`, and no test reaches it. Item 6's verification does exercise its changed path: M2 proves the production statement is load-bearing for the test.

**Tests that pass for the wrong reason.**
One, and it is the shipped-test half of finding 2: `MappingLogPrivacyTests`' own canary emission is satisfied by a sibling's canary in a full-suite run, so that specific call is not load-bearing. The assertion it guards (`requireDelivered`) still fires correctly when the daemon is actually silent, verified under `OS_ACTIVITY_MODE=disable`. The new `SchedulingLogTests` test does not pass for the wrong reason - M4 breaks it - it simply guards less than its title suggests.

**Flaky or environment-dependent tests, especially over a shared log window.**
No flake observed: see the flake numbers above. Both tests touched by this range assert over shared log windows, and both are correctly discriminated - `MappingLogPrivacyTests` filters on `cycleStartDay`, which is unique to the record it corrupts. `:115`'s `skipped.allSatisfy { !$0.contains("<private>") }` does assert over other tests' lines, but it is pre-existing, is disclosed in its own comment as the weaker claim, and cannot fire because every skip line in the target routes through `mappingLogSummary`. The window's true reach is wider than the tree believes - finding 3.

**No test weakened to force green.**
Confirmed mechanically: `git diff 05ff987 1a1d23b -- Packages/ | grep '^-' | grep -E '#expect|#require'` returns nothing. Nine assertions added, zero removed, and no `.disabled`, `withKnownIssue` or `XCTSkip` introduced.

**No lint rule weakened.**
`.swiftlint.yml` is not in the diff. `swiftlint --strict` is clean over 224 files at the head, up from 220 at the baseline as files were added by earlier stages.

**No further `OSLogStore`-reading test added.**
Confirmed, and this is the constraint the range respects best. Counted at `1a1d23b` by enumerating call sites of every store-opening helper: OttoUI 7 (`NotificationActionLogTests` 4, `SchedulingLogTests` 2, `BoundaryLogTests` 1), OttoPersistence 3 (`CorruptWatermarkTests`, `MappingLogPrivacyTests`, `UnreportableInvalidationTests`) = **10**, which is `reviews-4/BASELINE-4.md`'s 9 plus the one item 5 added in stage 4, outside my range. **This range adds none and removes one duplicate query helper.** Item 7 explicitly declined to add one - correctly as to the count, incorrectly as to the conclusion, since an existing shared query would have done (finding 1).

**Anything marked resolved without an artifact.**
Item 6's second half - finding 4. Item 6's first half and item 7 both carry commits and reproducible falsifications.

**Every commit in the range builds all three packages.**
Swept: 4 commits × 3 packages = 12 clean builds. See "What I ran".

**A falsification must break the thing the finding is about.**
M2 breaks the production log statement, M5 breaks the production call site, M3 breaks the production emission, M1 breaks the canary emission, M4 breaks the composed field - each is the line a future refactor would touch, not a proxy. Every mutation printed the removed text and asserted `count == 1` before writing.

**A test that asserts an absence must be checked against a population I control.**
The absence assertions here are `#expect(!line.contains("20260230"))`, `!contains("<private>")` and `wholeLine.contains("truncatedAfter=none")`. I checked the first two against a population I controlled by dumping the entire window (above): 10 lines, every one accounted for, and the `cycleStartDay` line present exactly once. The third is a presence assertion on a value I constructed in the test.

**Did later work break anything in this range?**
No. `git diff --name-only 1a1d23b d2b9c85` returns `PROD-READINESS-4.md` only - no Swift file is touched after my head. `d609790` repairs the ranges table flagged in finding 4; `d2b9c85` adds NOT DEFECTS / DEFERRED sections. Neither regresses this range.

## What I could not check, and why

- **Release configuration.** Debug only. `verify.sh` builds the app target unsigned for a generic simulator destination; no Release build was produced, so nothing here says how `os_log` privacy annotations or the composed `.public` string behave under optimisation.
- **A physical device.** Prohibited. Everything is simulator or macOS host, so the claim that `truncatedAfter` will be readable in a `log collect --device` archive is inferred from a host-process `OSLogStore` read, not observed on a phone.
- **A CI runner.** The standing `OSLogStore` risk stays CANNOT ASSESS for CI. I established the *shape* of the environment failure locally with `OS_ACTIVITY_MODE=disable`, which is the closest available proxy and is what the canary was written against, but no actual CI runner was exercised.
- **The exact reach of `OSLogStore.position(date:)` in milliseconds.** I established it spans at least one whole preceding test by dumping the window, which is enough to show "~80 ms" is wrong (finding 3), but I did not instrument entry timestamps to produce a number - doing so needs a full-suite run, and I did not want to add load to the twelve-run flake measurement.
- **`reviews-4/REVIEW-AA92CA7.md`.** It does not exist, so I could not judge whether N3-4 is closed on its merits - only that it is not closed by an artifact at this head. `aa92ca7` itself is outside my range and belongs to its own reviewer.
- **Stages 2, 3 and 4's own measurements.** The ledger discloses that they were taken jointly at `b054506` rather than at three heads. I re-ran all five dimensions at `1a1d23b` only; whether the intermediate heads each measured clean is for `REVIEW-2` through `REVIEW-4`.
- **The `.build` contamination the ledger reports.** `PROD-READINESS-4.md` records `ZZReviewProbeTests`-style artifacts under the main tree's `.build`. I did not inspect or touch the main tree's build directories, and all of my own builds ran under `--package-path` paths inside my own worktrees, so I can confirm I did not add to it but cannot say who did.
- **Concurrency of this measurement.** Another reviewer's `verify.sh` was running on this host for part of my run, and the main tree's HEAD advanced twice while I worked (`d609790`, then `d2b9c85`). Wall times below are therefore not comparable to the baseline's; pass/fail counts are.
