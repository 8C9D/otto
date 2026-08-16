# REVIEW-5 - round 5, stage 4, items 8 and 9 (N2-1 + N3-5), the REVIEW-4 finding-2 strengthening, range `7b6df8c..ff554cf`

Reviewed head `ff554cf1dcff76ef819ed365290debebc4870168`, branch `prod-readiness-5/2026-08-15`.
The range contains six commits: `3c47505` (the R4 review artifact, `reviews-5/REVIEW-4.md` only, verified `--name-only`), `b99d8dc` (the stamping commit - `PROD-READINESS-5.md` only, verified `--name-only`: stage-3 terminal states, the item-5 DEFERRED record, the canary-census correction), `1f6b2f7` (item 8), `d8ac728` (item 9), `4e23288` (the REVIEW-4 finding-2 pin, one test file), `ff554cf` (the ledger sections plus the one-line `docs/next-wave.md` gap-card quote, the range's HEAD).
At review time `git status --porcelain` showed only the untracked `.claude/` directory, present before this session and not mine; `HEAD == ff554cf` before this file was added.
All mutation and probe work was done in one detached worktree at `ff554cf` under my own scratchpad; every mutated file was restored from a saved pristine copy and byte-compared with `cmp`, every probe file was deleted after recording, the worktree was `git status --porcelain` clean before removal, and the main working tree was never modified except to write this file.

verdict: PASS

## Summary

**Both closures are real, the 0/0/0 harness number is true and generalizes past the three locales it was measured on, and I could not catch a claim in a false number anywhere in the range.**
Item 8's harness figure reproduces exactly: exit 0 with 232 tests passing under all three declared locales, and - my own probe past the stage's evidence - under `he_IL@calendar=hebrew` and `fa_IR@calendar=persian` too, so the fix is the general requested-locale rule, not a shape fitted to the harness.
The decision's other half holds by execution: a temporary probe run under the Buddhist, Japanese and ar_SA processes shows the `.current` defaults still rendering the PROCESS calendar and numbering ("15 ส.ค. 2569", "令和8年8月15日", "٢ ربيع١، ١٤٤٨ هـ", "Every ٤٥ days", "٣ subscriptions") - device rendering is unchanged, only an explicit request is honored completely.
The pre-fix state reproduces at `7b6df8c` from the other side: 1 / 1 / 5 with the failing citations exactly `DisplayFormattingTests.swift:49/:59/:68/:69` and `NotificationReconciliationTests.swift:170`, so the five-citation attribution and the "nothing else changed state" sentence are both exact.
Item 9's copy matrix, retyped independently from ITEM 9's approved sentences rather than from the source, matches verbatim in all four branches, including the mixed composition with "Nothing was deleted." appearing exactly once; a real mixed pass through the real scheduler (two corrupt families, one transient, one healthy) lands exactly the right identifiers in each list with `implausibleDayFailures ⊆ ledgerFailures`, and the disclosed composition artifact (a mixed headline counting ALL failures above a "Their stored dates" that means only the corrupt subset) is stated honestly in the ledger.
The finding-2 pin bites from both ends: hardcoding `failedCount=\(0)` and `desired=\(0)` in the production diff line each fail exactly `everyFailedRungIsNamedAtTheCeiling` at the new assertion (`SchedulingLogTests.swift:151`), and the pin reuses the ceiling test's already-open window - the reader count re-enumerated by the baseline's method is still ten.
The five dimensions reproduce to the digit: verify.sh exit 0 at 265/127/232 = 624 from a clean clone, lint clean over 232 files, the simulator suite at 133/73/67 with 10 known issues and `** TEST SUCCEEDED **` on three consecutive full runs, the harness at 0/0/0, and every pristine host run green at 232.
The M10 rendering falsification reproduces on the simulator to the byte: with the whole wording rule reverted the pixel assertion fails on byte-identical **107,396-byte** captures - the ledger's exact figure - and the restored file passes with the one pre-declared known issue.

No findings. The two record-edge nits I chased hardest - the "227 of 227" figure in the pin's own comment, and the `:59`/`:68`/`:69` tests now requesting en_CA - both dismissed on execution and reading; they are in the attempted-refutations list.

## What I ran

All measurements at `ff554cf` unless stated.
Host: macOS 15.6.1 (Darwin 24.6.0), arm64, Xcode 26.3, SwiftLint 0.65.0, simulator `<simulator-udid>`.

### The five dimensions at the stage-4 head

| dimension | ledger claims | measured here | result |
|---|---|---|---|
| `./scripts/verify.sh` | exit 0, 265/127/232 = 624 | **exit 0; OttoDomain 265 / OttoPersistence 127 / OttoUI 232 = 624**, from a clean clone of the committed head | exact |
| `swiftlint --strict` | clean, 232 files | **0 violations, 0 serious in 232 files** | exact |
| simulator suite, full | 133/73/67, 10 known issues, `TEST SUCCEEDED` | **133 / 73 / 67, `with 10 known issues`, `** TEST SUCCEEDED **`** on all three full runs; the 10 = the 7 `EmptyStateTests` + the 2 in "The usage repair renders (N4-16)" + the 1 in "The coverage-gap card renders its corrupt-date copy (N3-5)" (`CoverageGapCardTests.swift:226`, the pre-declared rendering label half), by name in the logs | exact; the +1 is exactly the pre-declared issue |
| non-Gregorian harness | 0 / 0 / 0, exit 0, 232 tests per locale | **exit 0 under all three**: `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura`, 232 tests passing each; **also exit 0 under `he_IL@calendar=hebrew` and `fa_IR@calendar=persian`**, which the stage never ran | exact, and it generalizes |
| flake, twelve full host runs | 12 of 12 (232 tests per run) | **5 of 5 pristine full OttoUI runs green** (three dedicated on the main tree, verify.sh's, and the worktree's post-battery run), 232 tests each, plus the probe-augmented run green at 235; I did not re-run twelve | consistent; the 12/12 itself is unreplicated |

### The pre-fix state, reproduced at the range start

Worktree checked out at `7b6df8c`, rebuilt, all three harness locales run: **1 / 1 / 5** - `DisplayFormattingTests.swift:49` alone under Buddhist and Japanese; `:49`, `:59`, `:68`, `:69` and `NotificationReconciliationTests.swift:170` under ar_SA.
Exactly the five citations, nothing else red, which pins both the stage-start claim and "nothing other than the five citations changed state under the harness".

### The decision's second half, executed

A temporary probe test (deleted after recording) asserting on the `.current` DEFAULTS - `displayText()`, `cycleText(_:)`, `subscriptionCountText(_:)` with no locale passed - run under all three harness processes at the head:

```
th_TH@calendar=buddhist   displayText() = "15 ส.ค. 2569"        (Buddhist year through .current)
ja_JP@calendar=japanese   displayText() = "令和8年8月15日"       (Reiwa 8)
ar_SA@calendar=islamic    displayText() = "٢ ربيع١، ١٤٤٨ هـ"     cycleText = "Every ٤٥ days"   count = "٣ subscriptions"
```

Device rendering follows the process calendar and numbering after the fix; only an explicitly passed locale is honored completely.
On the Gregorian host the same probe reads "Aug 15, 2026" / "Every 45 days" / "3 subscriptions".

### The copy matrix, executed against the ledger's own sentences

A second probe retyped the approved copy FROM `PROD-READINESS-5.md` ITEM 9 (not from the source file) and compared all four branches by string equality: whole-pass (`failureCount: 0`), transient-only, corrupt-only, mixed.
All four match verbatim; the mixed detail is exactly the transient paragraph + one space + the corruption sentences with "Nothing was deleted." absent, and `components(separatedBy: "Nothing was deleted")` confirms it appears once.
Green on the Gregorian host and under all three harness locales (the count phrase interpolated, so ar_SA renders "٢ subscriptions with unusable dates" - English template, process numerals, the pre-existing base-table behaviour).

### The subset, executed through the real scheduler

A third probe: one pass over a Buddhist-written anchor (2569-08-06), an Indian-written anchor (1948-08-06), a transient materialization failure (the `failMaterialize` knob), and a healthy control.
Measured: `ledgerFailures = {buddhist, indian, transient}`, `implausibleDayFailures = {buddhist, indian}`, subset relation holds, `canClaimCoverage == false`, and the healthy control still scheduled.
Every corrupt family in, no transient leaking in, and the knob itself lives only on `FakeBillingEventRepository` in the test target - nothing production-reachable.

### Falsifications - the stage's reproduced, plus mine

Each mutation applied by a script asserting the target text occurs exactly once, in the worktree, restored from a pristine copy verified with `cmp`; every host run is a FULL run with no `--filter`, and the harness runs are full 232-test helper runs.
M10 alone ran simulator-scoped (`-only-testing:OttoUITests/CoverageGapRenderingTests`, the test the claim is about), mutated and restored both.

The stage's battery, reproduced:

| ledger mutant | exact change I applied | ledger says | measured |
|---|---|---|---|
| item 8 M1 | `displayText`'s style rebuilt as `Date.FormatStyle(date: style).locale(locale)` | `requestedLocaleIsHonoredCompletely`, 1/1/1 | **the same one test, 1 / 1 / 1** on three full host runs |
| item 8 M4 | `NotificationContent.displayDate` drops `calendar: locale.calendar` | `changedContentReplacesInPlace` under the ar_SA harness, 1/1/1 | **exact**: "a changed spec is replaced by add-over-the-top, never removed first" (the `:170` test), 1 / 1 / 1, three helper runs, exit 1 each |
| item 9 M5 | the headline's corrupt-only condition `==` swapped to `!=` | `aPartialFailureNamesTheCount`, `aCorruptOnlyPassGetsTheCorruptionCopy`, `aMixedPassCarriesBothHalves`, 7/7/7 | **the same three tests, 7 issues** (one full host run) |
| item 9 M9 | `implausibleDayFailures.append` deleted from the ledger loop | `coverageIsNotClaimed`, `transientFailureIsNotMarkedImplausible`, 2/2/2 | **the same two tests, 2 / 2 / 2** on three full host runs |
| item 9 M10 | the whole wording rule reverted - headline corrupt branch, detail corrupt-only branch, mixed append, applied together | the pixel assertion fails on byte-identical 107,396-byte captures; restored, passes with the one known issue | **exact to the byte**: `Expectation failed: (corruptPixels → 107396 bytes) != (transientPixels → 107396 bytes)` at `CoverageGapCardTests.swift:216`, `** TEST FAILED **`; restored file passes with exactly 1 known issue, `** TEST SUCCEEDED **` |

Mine, beyond the stage's:

| # | what I broke | result |
|---|---|---|
| P1 | `failedCount=\(failures.count, privacy: .public)` hardcoded to `failedCount=\(0, ...)` - REVIEW-4 finding 2's surviving mutant | **killed**: `everyFailedRungIsNamedAtTheCeiling` fails at the new pin (`SchedulingLogTests.swift:151`, "the diff line does not carry the real failedCount at the ceiling"), 1 issue, full 232-test run |
| P2 | `desired=\(specs.count, ...)` hardcoded to `desired=\(0, ...)` - the pin's other half | **killed**: the same test at the same assertion, 1 issue; the same-line `desired=64` match is load-bearing, not decoration |
| 4th/5th locale | full suite under `he_IL@calendar=hebrew` and `fa_IR@calendar=persian`, which the stage never measured | **0 issues each** - the fix is not shaped to the three harness locales |

The pristine re-run on the restored files was green (232 of 232), every restored file byte-compared identical, and the worktree was porcelain-clean before removal.

## Findings

None.
The attempted refutations below record what was chased and why each died.

## Explicit checks

- **Test integrity on the five citations, against the never-weaken rule.** `NotificationReconciliationTests.swift` is untouched in the range (`--name-only`), `:170`'s expected string `"FoodApp charges $15.99 on Aug 25."` intact. `DisplayFormattingTests.swift:49` is untouched entirely. `:59`/`:68`/`:69` keep their expected strings byte-for-byte ("Every 45 days", "1 subscription", "3 subscriptions") and now pass en_CA explicitly; the old assertions asserted the same English/ASCII strings against the process default, an assertion satisfiable only on a Gregorian-latin host, so no assertion a host could make was deleted - and the file GAINS `requestedLocaleIsHonoredCompletely`, the Gregorian-host guard the fix never had. The markup-residue loop keeps `.current` on purpose and still runs. Nothing loosened, no tolerance added.
- **The `CalendarEraTests.swift` header rewrite.** The rewritten paragraph claims the command exits 0 under all three locales; executed true at the head, and the pre-fix paragraph's content (1/1/5, the same citation split) reproduced at `7b6df8c`. The two instant-comparison tests keep instant-comparison form with the expected side built through the same locale-honoring style - the conversion pin is intact.
- **The reader count, re-enumerated by the baseline's method.** `actionLogLines` 4, `schedulingLogLines` 2, `boundaryLines` 1, `OttoLogProbe.persistenceLines` 3 - **ten**. The finding-2 pin asserts on the `lines` the ceiling test already fetched; no query added anywhere in the range.
- **ITEM 7's census correction, against my own enumeration.** Emission sites by grep: `NotificationActionLogTests` 4, `BoundaryLogTests` 2, `SchedulingLogTests` 2, OttoPersistence 3 = **eleven**; `requireDelivered` call sites: 8 in OttoUI + 3 in OttoPersistence = **eleven**. The corrected sentences in ITEM 7 match exactly, including the parenthetical (ten `requireDelivered` at the range start; `BoundaryLogTests`' one check became two).
- **ITEM 3's REVIEW-4 finding-2 remediation sentence.** The pin is a same-line `desired=64 ` + `failedCount=64` match inside `everyFailedRungIsNamedAtTheCeiling`'s existing window, exactly as the sentence says; P1/P2 above execute both halves. The "227 of 227 green before the edit" figure locates at the stage-4 start (`7b6df8c`, a 227-test suite), consistent with REVIEW-4's mutant C.
- **ITEM 5's DEFERRED record.** The defect is unchanged in this range: `SettingsView.swift:214` still holds the sole `model.requestExport(kind)` call, no Settings file is touched by R5, `SettingsExportTests.swift` carries exactly the eight model-level tests the record cites, and `project.yml` declares one application target and no UI-testing bundle - the named dependency is real and nothing smaller exists in the tree. The decision and dependency are both named in the section. The round-4 green-deletion measurement itself I did not re-execute; surface unchanged, corroborated by the round-4 artifacts.
- **Scope and hygiene.** Six commits, all inside the declared R5; the union of R0-R5's rows covers all 30 commits since `9e73378` with none outside every range. Every message one short sentence, no body, no trailer. No `Package.swift`, `project.yml`, `.swiftlint.yml`, workflow, target or dependency change anywhere in the range. The two new files are genuine file-length splits: `TodayView.swift` was 367 lines at `7b6df8c` and the copy matrix adds ~45, past SwiftLint's 400 cap; `TodaySectionPlanTests.swift` was 345 and the new suites add ~170; post-split they sit at 312/100 and 306/235.
- **The card's plumbing and trigger set.** `TodaySectionPlan.swift` is untouched (the trigger-set-unchanged claim holds by diff); the `TodayView` call site passes both counts from the outcome; the view-body untestability disclosure matches R4-1's pre-existing shape at the same call site.
- **The arithmetic.** Host 227 -> 232 = +1 (item 8) +4 (item 9: +3 copy tests net of the move, `transientFailureIsNotMarkedImplausible`); sim 132/72/63 -> 133/73/67 with the rendering test and the two Dynamic Type wordings inside existing tests; lint 230 -> 232 = the two split files. All reconcile exactly.
- **Fabricated or unreproducible numbers.** None found. Every count I re-measured - 624, 232 files, 133/73/67, 10 known issues, 0/0/0, 1/1/5 at the range start, 1/1/1 and 2/2/2 and 7-issue mutant samples - landed on the ledger's number.

## Attempted refutations that did not become findings

- **A fourth locale breaking the harness.** `he_IL@calendar=hebrew` and `fa_IR@calendar=persian`: 232 of 232 green under both. The fix generalizes; 0/0/0 is not an artifact of the three measured locales.
- **A default that changed behaviour.** The probe above: every `.current` default still renders the process calendar and numbering under all three harness processes. The user's device-rendering-unchanged constraint holds by execution, not by reading the defaults.
- **The `:59`/`:68`/`:69` en_CA request as a weakening.** Chased against never-weaken: the old assertions pinned the same strings against `.current` and could only ever pass on a Gregorian-latin host - they were host-environment assertions wearing test clothing, red under the harness since round 2. The new form keeps every expected string, adds the explicit-locale semantics the fix defines, and the new completeness test makes a revert visible on every host, which the old shape never did. Strictly stronger; dismissed.
- **The "227 of 227" in the pin's comment as a wrong number.** At the stage-4 head the suite is 232, but the re-measurement the comment records was made before the item-8/9 commits, at the 227-test range start - the same figure REVIEW-4's mutant C measured at `7b6df8c`. Consistent once located; dismissed.
- **Transient copy borrowing the corruption copy, or the reverse.** M5's three-test kill set matches the ledger; the probe's four-branch equality check pins every branch to the approved sentence; `aPartialFailureNamesTheCount`'s new negative assertions ("unusable dates" and "on purpose" absent) execute the transient side.
- **The subset lying under a mixed pass.** The two-corrupt-families-plus-transient probe: exact membership both lists, subset relation, healthy control unaffected. M9's deletion is killed by two tests on all three runs.
- **The mixed composition artifact being undisclosed.** ITEM 9's "Disclosed:" bullet states the headline-counts-all/pronoun-means-subset artifact plainly; the probe confirmed the rendered composition is exactly as recorded. Disclosed and true; nothing to find.
- **The pin satisfiable by a sibling's line.** The match requires `desired=64 ` and `failedCount=64` on ONE line inside the ceiling test's own window; no other test drives 64 failures at the ceiling, and P2 shows the `desired=64` half is enforced (a truthful `failedCount=64` on a line with the wrong `desired` would not pass).
- **`failMaterialize` reaching production.** The knob is on `FakeBillingEventRepository` in `Tests/OttoServicesTests`; the production `BillingEventRepository` protocol and implementations are untouched by the range.
- **The corrupt-only headline rendering a stale count.** The corrupt branch interpolates `implausibleCount`, which in that branch equals `failureCount`; no branch can render a zero or mismatched count (`implausibleCount > failureCount` is unconstructible from the scheduler, whose subset is appended in lockstep with `failures`).

## What I could not check, and why

- **The 12-of-12 flake dimension.** Six pristine full host runs, all green at 232; twelve were not re-run, so the ledger's flake figure is sampled, not replicated - the same caveat REVIEW-4 recorded.
- **Item 8's M2/M3 and item 9's M6/M7 mutant rows.** Not re-run (M1/M4/M5/M9/M10 were, plus both pin mutants); their claimed kill sets are the same test families my reproductions exercised from adjacent directions.
- **The round-4 export-deletion green run behind ITEM 5's "unchanged" sentence.** Verified unchanged by surface (call site, test census, target list) rather than by re-deleting; the original execution is `PROD-READINESS-4.md`'s and was reviewed there.
- **CI-runner delivery, release configuration, a physical device.** Standing CANNOT ASSESS, as every prior round.
