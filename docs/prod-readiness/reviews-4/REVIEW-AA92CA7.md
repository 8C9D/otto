# Adversarial review of the inherited commit `aa92ca7`

verdict: REJECT

Range `aa92ca7^..aa92ca7` (parent `70f3f19`), ledger `PROD-READINESS-4.md`, baseline `reviews-4/BASELINE-4.md`.
This commit is round 2's remediation of `reviews-2/REVIEW-6.md` and has never been inside a review range.
Everything below is re-derived in three detached worktrees under the session scratchpad; nothing is read from the builder's account.

## Summary

The commit does five things.
It moves `reconcile` and `isTodaysAnnouncement` out of `NotificationScheduler.swift` into a new `NotificationScheduler+Reconcile.swift` and drops `private` from `client` so the extension can reach it.
It splits the `reconcile` log statement in two: the `notice` diff line now carries `failedCount=` and the failure identifiers move to their own `error` entry.
It adds `OttoLogProbe`, a canary the three OttoUI log-reading tests emit and check inside their existing `OSLogStore` query, so a host that delivers no logs fails at a different assertion than a deleted log statement.
It rewrites `SchedulingLogTests` to target the new entry.
And it rewrites six sections of `PROD-READINESS-2.md`.

Most of it holds, and holds precisely.
Every measured number in the commit message and the new `VERIFICATION AT HEAD` section reproduces exactly on this host: 251 / 118 / 196 host tests, `swiftlint --strict` clean across 212 files, simulator `108 / 70 / 31` with the same 7 known issues and `** TEST SUCCEEDED **`.
The lint claim that reads like hand-waving is true and I confirmed it by construction: applying this change without the file split trips `file_length` at 415 lines **and** `type_body_length` at 253 lines, both of them.
The canary works in both directions for the three tests that have it.
The `Bank` correction and the two corrected citation line numbers are right.

It is rejected for three things, all still live at the branch tip.

The commit declares `N2-4` **FIXED** and deletes it from the carry-forward list.
It is not fixed.
Giving the failure list "its own budget" buys about 200 bytes, which is the size of the prefix that moved off the line.
The list still truncates, now at six subscriptions instead of five, and at the 64-rung device ceiling the entry still names **16 of 64** failed rungs.
The commit's own stated criterion is "a rung that fails and is then not named is exactly the loss RF-3 exists to repair", and by that criterion the defect survives the fix.
This is the same failure `reviews-2/REVIEW-6.md` finding 2 was about, moved one subscription outward: the fix was verified in the regime the review complained about and nowhere past it.

Re-pointing `SchedulingLogTests` at the new entry left the `notice` diff line with no reader at all.
Deleting that whole log statement is green at `aa92ca7` and still green at the tip; the same deletion at the parent fails the test.
The line whose own comment calls it "the evidence that this is a diff and not the old remove-all" now has none.

And the ledger sentence this commit wrote says the canary covers all four log-reading tests when it covers three.
`OttoLogProbe` exists only in the OttoUI test target; `MappingLogPrivacyTests` in OttoPersistence still fails with the ambiguous empty-read signature under suppressed logging.
Round 3 or 4 found this independently and fixed it, and the fix's own comment in the tree says so: *"`PROD-READINESS-2.md` recorded the canary as covering all four log-reading tests; it covered three."*

## What I ran

Three detached worktrees: `wt-aa92ca7` at `aa92ca7`, `wt-parent` at `70f3f19`, `wt-tip` at `80eeb97` (`prod-readiness-4/2026-08-12` when I read it).

**Builds at `aa92ca7`, all three packages, `swift build --build-tests --package-path Packages/<pkg>`:**

```
OttoDomain       Build complete! (18.09s)   exit=0
OttoPersistence  Build complete! (26.82s)   exit=0
OttoUI           Build complete! (31.48s)   exit=0
```

**Host suites at `aa92ca7`:**

```
OttoDomain       ✔ 251 tests in 56 suites passed after 0.068 s
OttoPersistence  ✔ 118 tests in 24 suites passed after 30.4 / 14.1 / 9.6 / 13.7 s
OttoUI           ✔ 196 tests in 36 suites passed after 23.5 / 35.5 / 40.6 / 48.3 s
```

**Lint:**

```
aa92ca7   Done linting! Found 0 violations, 0 serious in 212 files.
70f3f19   Done linting! Found 0 violations, 0 serious in 210 files.
```

**Simulator at `aa92ca7`,** `xcodebuild test -scheme OttoUI-Package -destination id=<simulator-udid>` from `Packages/OttoUI/`:

```
✔ Test run with 108 tests in 20 suites passed after 6.298 seconds.
✔ Test run with  70 tests in 12 suites passed after 0.102 seconds.
✘ Test run with  31 tests in  6 suites passed after 2.540 seconds with 7 known issues.
** TEST SUCCEEDED **   exit 0
```

**The lint claim, by construction.**
Parent `NotificationScheduler.swift` is exactly 400 lines and lints clean.
Applying this commit's `reconcile` edit in place, with no file split:

```
NotificationScheduler.swift:415:1: error: File Length Violation: File should contain 400 lines
  or less: currently contains 415 (file_length)
NotificationScheduler.swift:11:8: error: Type Body Length Violation: Actor body should span 250
  lines or less excluding comments and whitespace: currently spans 253 lines (type_body_length)
Found 2 violations, 2 serious in 210 files.
```

**Truncation probe.** Fresh `SchedulerFixture`, N subscriptions at indices 900+, `refuseAdds(after: 0)` so every rung fails, reading the process's own `scheduling` category. `named` counts identifiers actually present in the emitted `failed=[…]` field.

| commit | subs | rungs failed | entry length | state | named |
|---|---|---|---|---|---|
| `70f3f19` (pre-fix, one line) | 64 | 64 | 1050 | TRUNCATED | tail lost |
| `aa92ca7` (fix, own entry) | 4 | 12 | 822 | complete | 12 of 12 |
| `aa92ca7` | 6 | 18 | 1037 | **TRUNCATED** | **16 of 18** |
| `aa92ca7` | 20 | 60 | 1037 | **TRUNCATED** | **16 of 60** |
| `aa92ca7` | 64 | 64 | 1037 | **TRUNCATED** | **16 of 64** |
| `80eeb97` (tip) | 20 | 60 | 1037 | **TRUNCATED** | **16 of 60** |
| `80eeb97` (tip) | 64 | 64 | 1037 | **TRUNCATED** | **16 of 64** |

Truncated tail at 64 rungs, at the tip: `…000000000914|2026-08-22|renewal=AddRefused 00000000-0<…>]`.

**The same probe with `refuseAdds(after: 3)`, the shape `reviews-2/REVIEW-6.md` finding 2 used,** which is the honest before/after because it keeps a non-empty `added=` list on the diff line:

| subs | failures | `70f3f19` (pre-fix) | `aa92ca7` (post-fix) |
|---|---|---|---|
| 4 | 9 | 846 complete, 9 named | 621 complete, 9 named |
| 5 | 12 | 1047 complete, 12 named | 822 complete, 12 named |
| 6 | 15 | **1050 TRUNCATED, 12 of 15** | 1023 complete, 15 of 15 |

So the fix is real and it buys exactly one subscription of headroom in this shape, and about 200 bytes overall.
The `1050`-character cap the commit message quotes reproduces exactly.

**Falsifications.** Every patch was applied by script that printed the removed text and asserted its occurrence count first.

| what I broke | where | result |
|---|---|---|
| merged `failed=[…]` back into the diff line and deleted the `error` entry | `NotificationScheduler+Reconcile.swift:65,77-81` | `✘ SchedulingLogTests.swift:70` `lines.last { $0.hasPrefix("reconcile failed=[") … } → nil`. The commit's own claimed falsification, confirmed |
| deleted the whole `notice` diff line at `aa92ca7` | `NotificationScheduler+Reconcile.swift:60-66` | `✔ Test run with 196 tests in 36 suites passed` - **nothing fails** |
| deleted the same line at the parent | `NotificationScheduler.swift:195-201` | `✘ SchedulingLogTests.swift:65`, 1 issue - **it was guarded before this commit** |
| deleted the same line at the tip | `NotificationScheduler+Reconcile.swift` | `✔ Test run with 209 tests in 38 suites passed` - **still unguarded** |
| `OS_ACTIVITY_MODE=disable`, the three OttoUI tests | - | 3 issues, all `lines.contains { $0.contains(canary) }`, at `SchedulingLogTests.swift:67`, `NotificationActionLogTests.swift:59` and `:92` |
| deleted both `OttoLog.actions` statements, logging healthy | `NotificationActionHandler.swift:68,74` | 2 issues, both `lines.last { $0.contains(identifier) } → nil`, at `NotificationActionLogTests.swift:60` and `:93` |
| `OS_ACTIVITY_MODE=disable`, `MappingLogPrivacyTests` | - | `✘ MappingLogPrivacyTests.swift:91` `!((ours → []).isEmpty → true → true)` - **the ambiguous signature, unchanged** |
| removed `emitCanary` from `aFailedActionIsRecorded` only | `NotificationActionLogTests.swift:49` | `✔ 2 tests passed`, 3 runs of 3 - **satisfied by the sibling test's canary** |
| removed both `emitCanary` calls | `NotificationActionLogTests.swift:49,84` | 2 issues at `:58` and `:90`, confirming the mechanism is sibling cross-talk |

**Record checks.**
`git grep -c "Bank" 7a3cf54 -- '*.swift'` returns ten files, three of them production sources (`PaymentMethod.swift`, `PaymentMethodFormModel.swift`, `PaymentMethodsView.swift`) - the correction is exact.
`DataTransferTests.swift:282` and `RestoreIntoEmptyStoreTests.swift:166` at `aa92ca7` both open the `materializationWatermark(…) == day(2026, 3, 1)` assertions the falsification claims, and OttoPersistence is `118 tests in 24 suites` - all three corrections are exact.
`git show --name-only aa92ca7` touches six files: the ledger and five under `Packages/OttoUI/`.

## Findings

### 1. P2 - `N2-4` is recorded FIXED and deleted from the carry-forward list; the truncation still reproduces from six subscriptions upward and drops 48 of 64 rungs at the device ceiling

**evidence.** `PROD-READINESS-2.md:400`, written by this commit:

> **N2-4 (P2, from stage 6) — FIXED in stage 6's remediation, not carried forward.** … The failure list now gets its own log entry with its own budget

`NotificationScheduler+Reconcile.swift:70-76`, also written by this commit, names the 64-rung case as the motivation:

> at sixty-four rungs the whole field came back as `<decode: missing data>`. A rung that fails and is then not named is the exact loss this is meant to repair, so the failure list is given a budget of its own.

Measured at `aa92ca7` and again at the tip, the "budget of its own" is the same `os_log` per-entry budget of roughly 1024 bytes:

```
aa92ca7   subs=6  rungsFailed=18  FAILENTRY len=1037 TRUNCATED named=16
aa92ca7   subs=20 rungsFailed=60  FAILENTRY len=1037 TRUNCATED named=16
aa92ca7   subs=64 rungsFailed=64  FAILENTRY len=1037 TRUNCATED named=16
80eeb97   subs=64 rungsFailed=64  FAILENTRY len=1037 TRUNCATED named=16
```

The commit's severity argument for not deferring this was "**Four subscriptions is a real user**".
Six is a real user by the same argument, and 64 is the `UNUserNotificationCenter` pending ceiling this codebase already reasons about.
The gain is genuine but small and should have been stated as a threshold move, not a closure: at `refuseAdds(after: 3)` the pre-fix line lost 3 of 15 identifiers at six subscriptions and the post-fix entry keeps all 15, but at 18 failures it starts losing them again.

There is one real mitigation the commit added and did not claim: `failedCount=` on the diff line means an investigator can now *detect* the loss (`failedCount=64` against 16 names) where before a truncated `failed=` list gave no count at all.
That improves detectability, not the identities `RF-3` exists to preserve.

Nothing in the tree exercises the new line at any count where it truncates.
`SchedulingLogTests` deliberately uses one subscription, and its `#expect(identifiers.allSatisfy { $0.contains("=") })` at `:86` would in fact catch a truncated tail - the fixture is just never large enough to reach one.

The false closure has propagated: `PROD-READINESS-3.md:811` and `PROD-READINESS-4.md:592` both carry `N2-4` as "fixed in round 2".

**why it was missed.** The commit remediated the exact regime `reviews-2/REVIEW-6.md` measured (four subscriptions) and re-verified only there and at the guard's one-subscription fixture.
"Its own budget" reads as though a separate entry were unbounded; the per-entry budget is a constant, so moving a field to a new entry buys only the bytes of the prefix left behind.
It is one probe away from being a measurement, which is verbatim the criticism the commit was answering.

### 2. P2 - the split removed the only executable guard on the §6.2 reconcile diff line, and it is still unguarded at the tip

**evidence.** Before this commit, `SchedulingLogTests` selected on `$0.hasPrefix("reconcile ")`, which is the diff line.
After it, `SchedulingLogTests.swift:71` selects on `$0.hasPrefix("reconcile failed=[")`, which is the new error entry.
Deleting the entire `notice` statement at `NotificationScheduler+Reconcile.swift:60-66`:

```
aa92ca7   ✔ Test run with 196 tests in 36 suites passed after 13.210 seconds.
80eeb97   ✔ Test run with 209 tests in 38 suites passed after 42.222 seconds.
```

The same deletion at the parent:

```
✘ SchedulingLogTests.swift:65:24: Expectation failed: Self.schedulingLogLines(since: since)
✘ Test run with 196 tests in 36 suites failed after 13.252 seconds with 1 issue.
```

`git grep 'reconcile ' 80eeb97 -- 'Packages/*/Tests/*.swift'` finds only the `failed=[` selector, and `failedCount` appears in exactly one place in the whole tree - the production source.
So `pending=`, `desired=`, `snoozesSpared=`, `removed=`, `added=` and `failedCount=` are all unread by any test.

The reconcile *behaviour* is still guarded independently, by `NotificationReconciliationTests` through the fake client's `addCalls` / `removeCalls`, so this is a loss of diagnosability coverage rather than of behavioural coverage.
That is still the exact failure mode `R5-2` exists for, and the round's own words for it are "a fix whose only evidence rots the moment someone edits the file".
The comment on the deleted line calls it "the evidence that this is a diff and not the old remove-all".

The commit does not disclose the trade, and its falsification section exercises only the new entry.

**why it was missed.** The commit's falsification was "merge it back into the diff line", which fails as expected and looks like proof the guard is intact.
It proves the *new* line is guarded.
Nobody asked the complementary question - what still fails if the *old* line goes - because the test was rewritten in the same change and the rewrite reads as a narrowing of an existing assertion rather than as a re-targeting.

### 3. P2 - the ledger states the canary covers all four log-reading tests; it covers three

**evidence.** `PROD-READINESS-2.md:301`, written by this commit:

> Each log-reading test now emits a canary line on the category it is about to read and checks for it in the **same** query, so the two causes fail at different assertions with different messages.

and `:87`, in a bullet that has just finished insisting the population is four:

> **Four** tests depend on it … **If CI goes red**, the canary tells you which failure it is … the remedy is to gate those four tests on the canary rather than delete them

`OttoLogProbe` is added only at `Packages/OttoUI/Tests/OttoServicesTests/OttoLogProbe.swift`.
`grep -rn canary` over the whole tree at `aa92ca7` returns four hits, all in OttoUI.
`MappingLogPrivacyTests` lives in the OttoPersistence test target and has no canary, so under the very condition the paragraph is about:

```
$ OS_ACTIVITY_MODE=disable swift test --package-path Packages/OttoPersistence \
    --filter MappingLogPrivacyTests
✘ MappingLogPrivacyTests.swift:91: Expectation failed: !((ours → []).isEmpty → true → true)
```

That is an empty read reported as "the store logged nothing for the record it skipped" - the misdiagnosis the whole remedy exists to prevent, on one of the four tests the same paragraph names.

Later work found this independently and fixed it; the fix's comment in the tree at `80eeb97`, `MappingLogPrivacyTests.swift:73-79`, records the finding as `N3-3` and states the conclusion in the same terms: *"`PROD-READINESS-2.md` recorded the canary as covering all four log-reading tests; it covered three."*

**why it was missed.** `reviews-2/REVIEW-6.md` finding 1 was headed "the **three new tests**", and the code change tracked that heading exactly.
The ledger prose was written against the four-test population the same commit had just corrected `CANNOT ASSESS` to state, and the two counts were never reconciled against each other.
The three OttoUI tests were then falsified both ways, which produced a real "verified both ways" line and made the fourth test invisible.

### 4. P3 - half the canary wiring is not falsifiable at its own call site

**evidence.** `NotificationActionLogTests` is `@Suite(…)` with no `.serialized`, so its two tests run concurrently in one process, both emit the same literal `otto.test.canary` to the same `actions` category, and both read a `since`-anchored window that `OSLogStore.position(date:)` reaches about 80 ms behind.
Removing the `emitCanary` call from `aFailedActionIsRecorded` only (`NotificationActionLogTests.swift:49`):

```
✔ Test run with 2 tests in 1 suite passed after 43.789 seconds.
✔ Test run with 2 tests in 1 suite passed after 17.064 seconds.
✔ Test run with 2 tests in 1 suite passed after 32.015 seconds.
```

Removing both confirms the mechanism is sibling cross-talk rather than something else:

```
✘ NotificationActionLogTests.swift:58: lines.contains { $0.contains(canary) }
✘ NotificationActionLogTests.swift:90: lines.contains { $0.contains(canary) }
```

The guard still does its job in the case it was built for - a host delivering nothing has no canary from any sibling, and all three tests fail on it, which I measured.
What it does not do is pin its own wiring: a refactor can delete one of the two `emitCanary` calls and the suite stays green, and the "same query" discipline the probe's docstring insists on is not enforced per test.

**why it was missed.** The commit falsified the canary by suppressing the whole subsystem, which removes every canary at once and therefore cannot distinguish "this test emits one" from "some test emits one".
The per-call-site falsification was never run.

### 5. P3 - the canary is emitted at a lower level than the line it vouches for, and its failure message overstates what it knows

**evidence.** `OttoLogProbe.swift:23` emits at `notice`.
The line `SchedulingLogTests` then asserts on is emitted at `error` (`NotificationScheduler+Reconcile.swift:78`).
The probe's message, `OttoLogProbe.swift:33-42`, asserts a fact it has not established:

> The unified log delivered NOTHING for this process, so nothing here is evidence about Otto's code.

Its own docstring lists "a runner that drops notice-level entries" among the causes it catches.
On exactly that runner the canary is gone while the `error` entry under test is delivered, and the test reports that nothing was delivered.
That is a milder version of the misdiagnosis the probe exists to prevent, pointed the other way.
Later work appears to have reached the same conclusion by a different route: the OttoPersistence probe added by round 3 or 4 emits its canary with `mappingLogger.error(…)` while OttoUI's still uses `notice`.

I did not attempt to reproduce this; changing the host's log level configuration requires root and modifies system state outside the repository.
It rests on reading the two levels off the source, which is why it is P3.

**why it was missed.** The single environment lever available (`OS_ACTIVITY_MODE=disable`) suppresses every level at once, so the level asymmetry cannot surface under the only falsification that was run.

### 6. P3 - "four deliberate file splits" is followed by five file names

**evidence.** `PROD-READINESS-2.md:32`, a sentence this commit wrote:

> `.swiftlint.yml` is untouched, which cost four deliberate file splits — `TodaySectionPlan.swift`, `OttoStore+Watermarks.swift`, `RestoreIntoEmptyStoreTests.swift`, `PreviewRepository.swift`, `NotificationScheduler+Reconcile.swift`.

Five names.
The fifth is the split this commit itself performed, which is the one added last.

**why it was missed.** The count was carried from the sentence's earlier state and the new file was appended to the list without re-counting - the same class of defect as the citation drift this commit is correcting four sections further down.

### 7. P3 - the carry-forward reconciliation this commit wrote is still short by one item, in the shape of the finding it was closing

**evidence.** `reviews-2/REVIEW-6.md` finding 3 was that the ledger promised a reconciliation of round 1's carry-forward list and contained none, and finding 8 was that `N2-3` vanished from the record with no note.
This commit answers both: it writes the table at `PROD-READINESS-2.md:366-387` and adds a `### Withdrawn` subsection for `N2-3`.

`R0-2` is in neither.
Round 1 records it twice as an unfixed P2 carried forward - `PROD-READINESS.md:159` ("P2 findings (F8, F9, F10, F11, **R0-2**..R0-11) are documented and **not fixed**") and the carry-forward row at `:255`.
`grep -rn "R0-2\b"` over `PROD-READINESS-2.md`, `PROD-READINESS-3.md`, `PROD-READINESS-4.md`, `reviews-2/`, `reviews-3/` and `reviews-4/` returns nothing.

There is a defensible reason it is absent - `R0-2` is described at `PROD-READINESS.md:62` as an amendment to `F1`'s record, and `F1` was resolved in round 2, so its substance may be moot.
That is exactly what the `## NOT DEFECTS` section is for, and this commit filled that section in with "**None.**"
So the item is in no terminal state at all, which is the shape of finding 8 reproduced for a different identifier by the commit that closed finding 8.

**why it was missed.** The table was built from round 1's `## NEXT ROUND` prose section, where `R0-2` does not appear; it appears only in round 1's findings table and its P2 summary row.
`reviews-2/REVIEW-6.md` finding 3 enumerated the missing items from the same prose section and also omitted `R0-2`, so the commit reconciled against the review's list rather than against round 1's own record - which the run's standard forbids, and which is the same inheritance error this commit corrects for the `Bank` sentence three paragraphs earlier.

### 8. P3 - a tautological assertion in the rewritten test

**evidence.** `SchedulingLogTests.swift:71` selects the line with `$0.hasPrefix("reconcile failed=[")`.
`SchedulingLogTests.swift:78` then asserts `#expect(line.contains("failed=["))`.
The second cannot fail given the first.
Before the rewrite it was a real check, because the selector was `hasPrefix("reconcile ")` and the line might have carried no `failed=` field.

Harmless on its own, and I note it only because it is the assertion a reader would take as the guard on the field's name.
The load-bearing assertions in that test are `:79` (`=AddRefused`) and `:86` (`allSatisfy { $0.contains("=") }`), and both survive.

## Explicit checks

**What the commit actually changed, from the diff.**
Six files.
`NotificationScheduler+Reconcile.swift` is new and holds `reconcile` and `isTodaysAnnouncement` moved verbatim from `NotificationScheduler.swift`, with two changes: `failed=[…]` on the `notice` line becomes `failedCount=`, and a new `if !failures.isEmpty` block emits `reconcile failed=[…]` at `error`.
`NotificationScheduler.swift` loses those two methods and `client` loses `private`.
`OttoLogProbe.swift` is new: a canary string, an emitter, and `requireDelivered`.
`SchedulingLogTests.swift` gains a canary emit and a `requireDelivered`, re-targets its selector from the diff line to the new entry, and un-privates `schedulingLogLines`.
`NotificationActionLogTests.swift` gains a canary emit and a `requireDelivered` in each of its two tests, hoisting the single log read into a local.
`PROD-READINESS-2.md` gains a `VERIFICATION AT HEAD` section, a filled `NOT DEFECTS`, a filled `DEFERRED`, a carry-forward table, a `Withdrawn` subsection for `N2-3`, and five corrections.

**Fabricated or unreproducible claims in the commit message.**
Every measured claim reproduces except the closure claim in finding 1.
`OttoUI 196` - exact.
`swiftlint --strict clean across 212 files` - exact, and the parent is 210.
"NotificationScheduler.swift passed BOTH `file_length` and `type_body_length`" - true, and I reproduced it by applying the change without the split: 415 lines and a 253-line actor body, two serious violations.
"the 1050-character cap" - exact; my pre-fix probe hits 1050 to the character.
"Verified both ways: suppressed logging fails on the canary, deleted log statements fail on the target line" - true for the three OttoUI tests, and false for the fourth log-reading test the ledger names (finding 3).
"on an identical four-subscription pass the pre-fix line is complete at 991 characters" - I could not reproduce `991` because the fixture's exact parameters are not recorded, and my four-subscription fixture yields fewer rungs; the mechanism, the cap and the direction all reproduce.
"the first version doubled them and took the pair to 63 s" - a claim about a draft that was never committed; unfalsifiable, and not a defect.
The one number I could not confirm is `OttoPersistence from ~1.4 s to ~7 s` (`PROD-READINESS-2.md:32`): I measure 9.6-14.1 s over four runs at `aa92ca7`.
That is host-dependent enough that I am not filing it, but it is the only new figure in the commit that does not land inside its stated range on this machine.

**Citations that do not say what they are claimed to say.**
Checked all five corrections.
`DataTransferTests.swift:282` and `RestoreIntoEmptyStoreTests.swift:166` each open the `materializationWatermark(…) == day(2026, 3, 1)` assertion claimed, and `118 tests in 24 suites` is exact.
`Bank` is in ten `.swift` files at `7a3cf54`, three of them production sources, exactly as stated.
The `N2-3` withdrawal narrative matches `reviews-2/REVIEW-4.md` finding 1.
The four-jobs claim matches `.github/workflows/ci.yml`.
The one citation defect is finding 3: `:87` and `:301` describe a canary population of four where the code has three.

**Any SwiftData schema change.** None.
`git show --name-only aa92ca7` touches nothing under `Packages/OttoPersistence/`, no `Stored*` model, no `OttoSchemaV*`, no `OttoMigrationPlan`.
The V3 freeze holds.

**Prohibited actions.** None.
`.swiftlint.yml` is not in the diff and I confirmed it is byte-identical at parent and commit; the file has no `disabled_rules`, no `excluded:` beyond the pre-existing `Packages/*/.build` glob, and neither `file_length` nor `type_body_length` is configured, so both run at SwiftLint's defaults - which is what made the counterfactual violate.
`.github/workflows/`, `project.yml`, every `Package.swift`, `PROD-READINESS.md`, `reviews/`, `DECISIONS.md` and `docs/` are all absent from the diff.
No new dependency and no new public API: `client`, `reconcile` and `OttoLogProbe` are all `internal`, and members of a `public actor` without a modifier do not become public.

**Features smuggled past the no-features rule.** None.
The new `error` entry is diagnostics on a path `RF-3` already owns; the file split is mechanical and the moved code is byte-identical apart from the two logging changes; no user-facing copy, view, setting, navigation or persisted state.

**Fixes that relocated a bug rather than removed it.** Yes, twice, and both are findings.
The truncation moved from the diff line to the failure entry and the threshold moved by one subscription (finding 1).
The test's coverage moved from the diff line to the failure entry, leaving the diff line unread (finding 2).

**Error handling that hides errors.** No.
`failures` is still collected for every rung, the rethrow is unchanged (`if let first = failures.first { throw first.error }`), and the log statements still precede the throw.
The `if !failures.isEmpty` guard on the new entry only suppresses an entry that would read `failed=[-]`.
The residual hiding is finding 1's: identities past the sixteenth are dropped by `os_log`, not by the code, and `failedCount=` now makes that drop visible even though it does not prevent it.

**Tests that pass for the wrong reason.** One, finding 4: `aFailedActionIsRecorded`'s `requireDelivered` is satisfied by its sibling's canary, so the call site is green with its own wiring removed, three runs of three.
Everything else I tried to break, broke.
`SchedulingLogTests` fails when the entry is merged back, when the entry is deleted, and when the canary is suppressed, each at a different line.
Both `NotificationActionLogTests` fail at the target line when the production statements go and at the canary when logging is suppressed.

**Flaky or environment-dependent tests.**
The three tests are `OSLogStore`-dependent by design and disclosed as such.
The commit adds a second environmental dependency to each: the canary must be delivered into the same window, at `notice`, for the test to reach its real assertion (finding 5).
Timing is the other half.
The OttoUI suite ran 23.5 / 35.5 / 40.6 / 48.3 s here against the `10.8-12.1 s quiescent` the ledger records, so the cost is at least twice what the corrected figure says on a second host, and these three tests are the whole of it.
I saw no failure in any unmodified run - roughly a dozen executions of the affected suites, plus one simulator run - so this is cost and environment sensitivity, not flake.

**Does the commit build all three packages at that commit.** Yes, all three, exit 0, output above.

**Does what it introduced still stand at the tip.**
The structure stands and has been built on.
`NotificationScheduler+Reconcile.swift` is still there, `failedCount=` is still on the diff line at `:65` and the `error` entry at `:78-79`, and `OttoLogProbe` has been copied into the OttoPersistence test target and adopted by at least five more tests (`BoundaryLogTests`, `CorruptWatermarkTests`, `UnreportableInvalidationTests`, `MappingLogPrivacyTests` and both `NotificationActionLogTests`).
Nothing was reverted.
Two of the three findings above are unrepaired at the tip and I measured both there: the failure list still truncates at 1037 characters naming 16 of 64 rungs, and deleting the diff line is still green across 209 tests.
The third was repaired: `MappingLogPrivacyTests` now has a canary, filed as `N3-3`.
`N2-4` is still carried as "fixed in round 2" at `PROD-READINESS-4.md:592`.

## What I could not check, and why

- **The `991`-character pre-RF-3 figure.** `reviews-2/REVIEW-6.md` finding 2 does not record the fixture's parameters beyond "same fixture family, same seed, `refuseAdds(after: 3)`, four subscriptions", and my four-subscription fixture produces 9 failed rungs where theirs evidently produced more. The cap, the direction, the mechanism and the `1050` figure all reproduce; the specific `991` does not, and I cannot tell whether that is a different fixture or a wrong number.
- **The notice-vs-error level asymmetry in finding 5.** Confirming it requires reconfiguring the host's unified-log level for the subsystem, which needs root and changes system state outside the repository. The finding rests on reading the two levels off the source and is rated P3 for that reason.
- **CI behaviour on GitHub-hosted runners.** Network calls are prohibited, so the question the canary exists to answer stays open, exactly as `CANNOT ASSESS` says.
- **Whether the seven-item carry-forward table's other rows are still accurate.** I spot-checked `R0-2` (finding 7) and `R4-3`, which was accurate at `aa92ca7` and has since been addressed at the tip. The remaining fifteen rows I did not re-derive against round 1's evidence; they are outside this commit's diff except as text it wrote.
- **Real notification delivery, Focus behaviour, release configuration, accessibility rendering.** Hardware or an AX client; the physical device is prohibited and the run's own `CANNOT ASSESS` already covers these.
- **The non-Gregorian locale harness.** Not re-run at this commit. The commit does not touch any date path, and `reviews-2/REVIEW-6.md` re-derived `1 / 1 / 5` at the parent's predecessor with the three log-reading tests passing under all three locales.

## Prohibited actions by me: none

All mutation happened in three detached worktrees under the session scratchpad (`wt-aa92ca7`, `wt-parent`, `wt-tip`), created by me with `git worktree add --detach` and confirmed `git status --porcelain` empty before removal.
Every falsification patch was applied by a script that printed the exact text it removed and asserted its occurrence count before writing.
The four files I added were my own probes (`ZZTruncProbeTests.swift`, `ZZBeforeAfterProbeTests.swift` in two worktrees); I deleted each one myself.
No file I did not create was deleted, and no `rm -rf` was run on any repository path.
No network call of any kind: refs were inspected with `git log`, `git show-ref`, `git branch -a --contains` and `git rev-parse` only, and every build and test read the local filesystem.
No commit, no push, no rebase, no history rewrite, no tag operation.
No physical device; the iOS Simulator (`<simulator-udid>`) was used as permitted.
Nothing in `<backup-dir>` was read, moved or modified.
This file is the only file I wrote, at `reviews-4/REVIEW-AA92CA7.md`; I edited no narrative document, no `PROD-READINESS-*.md`, and nothing else under `reviews-4/`.

Two notes on state I did not create and did not touch.
The main working tree carried uncommitted modifications throughout my review from concurrent work that is not mine - `NotificationCoordinator.swift`, `NotificationCoordinatorTests.swift` and `reviews-4/REVIEW-3.md` with an untracked `ZZOverlapProbe.swift` when I started, `SettingsExportTests.swift` and `reviews-4/REVIEW-4.md` when I finished - and its HEAD advanced from `8a62c0c` to `f7a76ab` while I worked.
My three worktrees are removed and `git worktree list` no longer shows any of them; it does show six worktrees under `scratchpad/rev4/` and `scratchpad/rev5/` belonging to other concurrent sessions, which I left alone because I did not create them.
The measurements in this file that name the tip are pinned to `80eeb97`, the commit `prod-readiness-4/2026-08-12` pointed at when I read it.
