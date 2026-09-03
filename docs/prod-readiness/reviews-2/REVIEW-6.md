**VERDICT: PASS-WITH-FINDINGS**

Adversarial review of stage 6, range `5d8ed6a..3ce3e01`, ledger `PROD-READINESS-2.md`, and — because this is the last stage — of the run's closing claims against the repository at HEAD.
Nothing below is read from the builder's account; every number is re-derived in scratch clones outside the repository.

Both items land. `RF-3`'s enrichment is real, wired, and falsifiable at the call site; `R5-2`'s guard genuinely fails when round 1's F2 fix is deleted. No schema change, no prohibited action, no weakened assertion, and HEAD is green from a clean clone.

The defects are in what the new guards depend on and in what the closing document says about it:

1. the three new tests fail with the **same signature as a real regression** when the host's log is empty, and the ledger states the opposite failure mode;
2. the `failed=` field this stage exists to enrich is **truncated at four subscriptions**, and the ledger's `N2-4` entry says the enrichment does not make that more likely — it does, measurably;
3. the ledger's closing sections are **unfinished**: it promises a reconciliation of the full carried-forward list, contains none, records no verification at HEAD, and still carries per-stage template text.

Round 1's failure — a closing section that was never inside any review's range and carried three false claims — did **not** recur in the same form. `3ce3e01` rewrote the work-list table, the range table, CANNOT ASSESS, ITEM 4, ITEM 6 and ITEM 7 and is inside this range, so every closing word now at HEAD has been read. The failure recurred in a different form: what is *missing* from the closing sections was never anyone's range.

---

## Verification re-derived from scratch

| measurement | ledger says | re-derived here | result |
|---|---|---|---|
| `scripts/verify.sh` at `3ce3e01` | **nothing — no HEAD figure is recorded anywhere** | exit 0 — OttoDomain **251**, OttoPersistence **118**, OttoUI **196**, total **565** | ✅ green, finding 4 |
| `swiftlint --strict` at HEAD | (via verify.sh) | clean, exit 0 | ✅ |
| simulator from `Packages/OttoUI/` at HEAD | baseline `101 / 65 / 20`, 7 known issues | exit 0, `** TEST SUCCEEDED **`, **108 / 70 / 31**, **7 known issues** | ✅ no regression |
| OttoUI host delta vs `5d8ed6a` | +3 tests (RF-3) +2 tests (R5-2) | 191 → **196**, exactly the 5 new tests | ✅ reconciles |
| non-Gregorian harness at HEAD | 1 / 1 / 5 | **1 / 1 / 5**, same five sites | ✅ exact |
| OttoUI suite duration | "~0.05 s to ~5 s" | `5d8ed6a`: **0.069 s**. HEAD: **10.836 / 11.118 / 12.117 s** quiescent | ❌ finding 6 |
| every commit in the branch builds | `d00c086` does not compile (ledger `:284`) | 13 code commits swept, **exactly one fails**: `d00c086`, OttoPersistence | ✅ confirmed **and recorded** |

### The locale baseline, re-measured at HEAD

Harness per `reviews-2/BASELINE-2.md`: `swiftpm-testing-helper` against `OttoUIPackageTests`, `DYLD_FRAMEWORK_PATH` set, `-AppleLocale <loc>`.

```
3ce3e01  th_TH@calendar=buddhist          1 issue    DisplayFormattingTests.swift:49
3ce3e01  ja_JP@calendar=japanese          1 issue    DisplayFormattingTests.swift:49
3ce3e01  ar_SA@calendar=islamic-umalqura  5 issues   DisplayFormattingTests.swift:49,59,68,69
                                                     NotificationReconciliationTests.swift:170
```

Exactly the documented `1 / 1 / 5` with exactly the documented sites. **This stage did not move the non-Gregorian baseline**, and the three new log-reading tests pass under all three non-Gregorian locales.

### Every commit in the branch, built

`swift build --build-tests` for all three packages at each of the 13 commits that touch a `.swift` file (`a82d4e0 4b18420 eb4a13b 12fdcfc db13abd 8ea8162 20d189a c566ce6 d00c086 0b76d65 8c1ab71 0ffe160 cac78f8`):

```
d00c086 OttoPersistence BUILD-FAIL
    RestoreIntoEmptyStoreTests.swift:101:30: error: value of type 'OttoDataSnapshot'
      has no member 'hasNoLiveRecords'
… every other commit × every other package: BUILD-OK
```

`reviews-2/REVIEW-5.md` finding 1 is confirmed and is the **only** such commit; the three stage-6 code commits all build. The ledger records it at `:284` with the CI consequence stated. **Nothing to add.**

### The two this stage adds, falsified

| what I broke | result |
|---|---|
| `NotificationScheduler.swift:200` back to `OttoLog.list(failures.map(\.id))` | 2 issues, `SchedulingLogTests.swift:73` and `:80`. Emitted line: `… failed=[00000000-0000-0000-0000-000000000077\|2026-08-22\|renewal …\|2026-09-22\|renewal …\|2026-10-22\|renewal]` — the ledger's quoted artifact, verbatim |
| both `OttoLog.actions` statements deleted from `NotificationActionHandler` | 2 issues, `NotificationActionLogTests.swift:57` and `:87`, both `#require … → nil` |
| same deletion at `5d8ed6a` (the ledger's "reconfirmed at HEAD" claim) | `✔ Test run with 191 tests in 34 suites passed` — **the whole suite green**, exactly as claimed |

### Four earlier items, falsified at HEAD

| item | what I broke | result | ledger row |
|---|---|---|---|
| F1 | `components.calendar = CalendarDay.conversionCalendar` deleted | `LiveNotificationClientTests.swift:145`: `(trigger.dateComponents.calendar?.identifier → nil) == (.gregorian)` | matches exactly |
| R4-1 | `sections.append(.coverageGap)` deleted | **5** issues: `TodaySectionPlanTests.swift:62`, `:63`, `:81`, `:270`, `:324` | substance matches; the ledger's row says 3, written before two remediations added the wiring guards |
| R0-6 | fetch predicate `deletedAt == nil` restored in `reconstructWatermarksNow` | exactly 2 issues, both watermark assertions and nothing else | substance matches; **line numbers wrong**, finding 5 |
| R3-1 | `current.hasNoLiveSubscriptions` → `current.isEmpty` | `ExportServiceTests.swift:196`: `restoredWatermarkPolicies == [.reconstruct]` | matches exactly |
| R0-4 | `OttoStore.swift:122` restored to `7a3cf54`'s exact pre-fix line | 2 issues, `MappingLogPrivacyTests.swift:91` (`ours → []`) and `:102` (`<private>` present) | **the stage's own rewrite of this test does not weaken it** |

---

## Findings

### 1. P2 — the three new tests fail identically to a real regression when the log store is empty, and the ledger's stated failure mode is the other one

**evidence.** With os_log emission suppressed on an otherwise healthy host:

```
$ OS_ACTIVITY_MODE=disable swift test --package-path Packages/OttoUI \
    --filter 'NotificationActionLogTests|SchedulingLogTests'
✘ NotificationActionLogTests.swift:57:24: Expectation failed:
    Self.actionLogLines(since: since).last { $0.contains(identifier) } → nil
✘ NotificationActionLogTests.swift:87:24: Expectation failed: … → nil
✘ SchedulingLogTests.swift:65:24: Expectation failed: Self.schedulingLogLines(since: since) …
✘ Test run with 5 tests in 2 suites failed after 11.021 seconds with 3 issues.
```

Compare the genuine regression (both `OttoLog.actions` statements deleted): `NotificationActionLogTests.swift:57` and `:87`, `#require … → nil`. **The two are indistinguishable.**

`PROD-READINESS-2.md:287` says the opposite:

> **If CI goes red on it**, the failure will be `OSLogStore(scope:)` throwing rather than an assertion, and the remedy is to move `theEmittedLineIsRedacted` behind a host check rather than to delete it.

That holds only for the store being *unreadable*. For the store being readable and **empty** — a suppressed logging subsystem, a runner whose `notice`-level persistence is configured off, a sandbox that drops the entries — the failure is an ordinary assertion that reads exactly like "someone deleted the log line", which is the misdiagnosis the remedy paragraph exists to prevent.

Two further understatements in the same risk statement:

- **CANNOT ASSESS (`:75`) names one test.** It names `MappingLogPrivacyTests.theEmittedLineIsRedacted` and the `persistence-tests` job only. At HEAD **four test functions** depend on `OSLogStore` — `theEmittedLineIsRedacted`, plus `theEmittedReconcileLineCarriesReasons`, `aFailedActionIsRecorded` and `aHandledActionIsRecorded` added by this stage — through three helper call sites (`MappingLogPrivacyTests.swift:107`, `NotificationActionLogTests.swift:100`, `SchedulingLogTests.swift:87`), and they run in **four** CI jobs, not one: `persistence-tests`, `ui-package-tests`, `dynamic-type-simulator` (which runs the whole OttoUI package on a simulator — `.github/workflows/ci.yml:48-73`), and `verify`. The stated remedy names only the persistence test.
- ITEM 7 (`:329`) says the risk "is recorded in CANNOT ASSESS with the remedy if CI goes red". It is not; the CANNOT ASSESS bullet was written in stage 5 and never extended.

**not flaky on this host, as far as I could push it.** 6 sequential isolated runs, 4 concurrent runs, 3 quiescent full-suite runs, 3 non-Gregorian bundle runs and one simulator run — 17 executions, zero failures. `OSLogStore(scope: .currentProcessIdentifier)` does isolate concurrent test processes. The exposure is environmental, not racy.

**why the builder missed it.** Stage 5 reasoned the risk through the constructor (`OSLogStore(scope:)` throwing) and stage 6 pointed at that reasoning instead of re-deriving it for its own three tests. Nothing forced the second half of the question — *what happens when the store is readable and empty?* — because the only host available answers "readable and full" every time. It is one `env` prefix away from being measurable, and the ledger's own doctrine ("a subsystem reporting that it accepted your work is evidence about the subsystem") is the argument for measuring it.

### 2. P2 — RF-3's enrichment makes the `failed=` field *more* likely to be lost, not less, and it happens at four subscriptions

**evidence.** `PROD-READINESS-2.md:356` (N2-4, this stage's own discovery):

> Observed on a 64-rung pass … Pre-existing; RF-3's enrichment makes the loss more costly, **not more likely**.

The 64-rung observation reproduces exactly — I re-ran it: `PROBE-LEN=1079 … added=[…<…>] failed=[<decode: missing data>]`. But the same probe, driven down to a handful of subscriptions, shows the claim about likelihood is false. Same fixture family, same seed, `refuseAdds(after: 3)`, four subscriptions, the only difference being the line's shape:

```
pre-RF-3   len=991   …|2026-10-14|renewal 00000000-…-000000000003|2026-11-03|usageCheckIn]   ← complete
at HEAD    len=1050  …|2026-09-14|renewal 00000000-…-000000000003|2026-10-14|ren<…>]          ← truncated
```

`os_log`'s argument budget is shared, `failed=` is the last field in the line, and `=AddRefused` adds ~11 bytes per failed rung. So a pass whose failure list was logged **completely** before this change now loses the tail of it: a rung that was named is now unnamed. At 6 subscriptions the line is already pinned at the 1050-character ceiling.

This is not a delivery regression — no user-visible behaviour changes, and the reasons are information that did not exist before — but the item's whole purpose (`OttoLog.swift:66-72`: *"On a device where two causes coexist … an investigation saw one error type and a list of names"*) is served only for small passes, and the ledger's N2-4 entry tells whoever picks it up that the enrichment did not move the threshold.

**the guard is written to avoid this regime.** `SchedulingLogTests.swift:47-50` says so plainly: *"one plain monthly subscription: … short enough that `os_log` does not truncate the field being asserted."* That is the right choice for a guard, but it means nothing in the tree exercises the fix at any realistic subscription count, and the ledger does not say that the verification stops where the defect starts.

**why the builder missed it.** N2-4 was found with a 64-rung fixture and diagnosed as a large-pass phenomenon; the fixture was then shrunk to make the guard stable, and the middle of the range — 4 to 20 subscriptions, i.e. every real user — was never measured. "More costly, not more likely" is the kind of claim that reads as analysis and is one probe away from being a measurement.

### 3. P3 — the ledger promises a reconciliation of the carried-forward list and does not contain one

**evidence.** `PROD-READINESS-2.md:347`:

> Carried forward from round 1 and not touched by round 2, plus what round 2 discovered. **The full list is reconciled at the end of this document.**

The document ends 10 lines later, at N2-2. The only subsection is `### Discovered by round 2` (N2-1, N2-4, N2-2). **Not one round-1 carry-forward appears anywhere in round 2's ledger**: `R0-5`, `R0-7`, `R0-9`, `R0-10`, `R0-11`, `F7`, `F8`–`F11`, `R4-2`, `R4-3`, `R5-1`, `RF-1`, `RF-2`, `RF-4` and the two `reviews/REVIEW-0.md` §4 items are all still live in `PROD-READINESS.md:173-196` and all still unlisted here. (`R4-2` and `R5-1` are mentioned in passing inside ITEM 2 and ITEM 7; that is prose, not the list the sentence promises.)

Two more pieces of per-stage scaffolding survive into the final document: `## DEFERRED` still reads *"(populated per stage)"* with no content, and `## NOT DEFECTS` still reads *"Nothing yet. All seven work-list items reconfirmed at HEAD **so far**."*

**why this is the round-1 failure in a new form.** Round 1's closing section was never inside a review range and carried three false claims. This run fixed the range mechanics — `3ce3e01` is inside my range and every closing sentence at HEAD has now been read — but the promise at `:347` is a claim about text that does not exist, and no reviewer's range can contain a section nobody wrote. Whoever writes it will be writing it after the last review, which is exactly the shape `RF-2` describes.

### 4. P3 — the ledger records no verification at HEAD

**evidence.** The `## Baseline` section (`:15-16`) gives `scripts/verify.sh` and the simulator suite at `7a3cf54` — `246 / 113 / 174`, total 533; `101 / 65 / 20`. Nothing in the document gives HEAD's numbers. Round 1's ledger had a `### Verification at HEAD` section (`PROD-READINESS.md:213-221`) that did, and `scripts/verify.sh`'s own header says to *"report ITS numbers"* before calling a wave complete.

Re-derived here, so this is a gap in the record rather than a hidden failure: **exit 0, 251 / 118 / 196, total 565, lint clean**; simulator **108 / 70 / 31 with 7 known issues, `** TEST SUCCEEDED **`**. The +32 host-test delta against the baseline the document *does* state is therefore unexplained inside the document.

**why the builder missed it.** Per-stage figures were captured in per-item prose (`114 tests in 23 suites`, `118 tests`, `~7 s`), which felt like the same thing; a run-level number has no per-item home and so never got written.

### 5. P3 — ITEM 3's falsification cites two line numbers, and both point at assertions that pass under that falsification

**evidence.** `PROD-READINESS-2.md:206-211` records the R0-6 falsification as:

```
✘ "watermarks reconstruct from the ledger…" DataTransferTests.swift:262
✘ "⛔ a subscription tombstoned at reconstruct time and resurrected later still has a watermark"
   RestoreIntoEmptyStoreTests.swift:116
✘ Test run with 114 tests in 23 suites failed with 2 issues.
```

Re-run at HEAD, the two issues are at `DataTransferTests.swift:282` and `RestoreIntoEmptyStoreTests.swift:166`, in a run of **118** tests in **24** suites. At HEAD, `DataTransferTests.swift:262` is the `fixtureUUID(1) == 2026-01-15` assertion, which *passes* under this falsification, and `RestoreIntoEmptyStoreTests.swift:116` is the all-tombstoned `.reconstruct` assertion belonging to a different test (`== 2026-06-15`).

`:116` was correct when written (at `c566ce6`) and drifted when stage 4 inserted the all-tombstoned end-to-end case into the same file. **`:262` was already wrong when written**: at `c566ce6` the `fixtureUUID(4)` assertion is at `:282-283`. Both sit inside the bullet at `:223` that announces it is correcting exactly this defect — *"the third recurrence of a citation measured before a move and not re-derived after it"*.

**why the builder missed it.** The correction bullet re-derived the *file* the assertion had moved to and carried the *line* across from the pre-split text unchanged, and then the block was treated as settled evidence by three later stages that edited both files.

### 6. P3 — item 7's cost figure understates by more than 2×

**evidence.** `PROD-READINESS-2.md:329`: *"The OttoUI suite goes from ~0.05 s to ~5 s."*

Measured on the same host, nothing else running:

```
5d8ed6a  ✔ Test run with 191 tests in 34 suites passed after 0.069 seconds.
3ce3e01  ✔ Test run with 196 tests in 36 suites passed after 10.836 / 11.118 / 12.117 seconds.
```

Each of the three log-reading tests reports ~11 s on its own; under load the suite reached 27 s. The `~0.05 s` half is exact; the `~5 s` half is not reproducible in 12 runs. This matters because "5 s" is the number the cost/benefit paragraph rests on, and because the same three tests run in four CI jobs.

**why the builder missed it.** Plausibly measured against a partially-built or single-suite run while the stage was in progress, and never re-derived at the stage's end — the same class as `reviews-2/REVIEW-1.md` finding 5 and the `440`/`456` correction the ledger already records at `:188`.

### 7. P3 — "no `.swift` file carried them before" is false for the issuer

**evidence.** `PROD-READINESS-2.md:289`, justifying the fixture de-identification: *"Not a new exposure (both already appear in committed documents, and no `.swift` file carried them before)"*.

```
$ git grep -c "Bank" 7a3cf54 -- '*.swift'
PaymentMethod.swift:1   PaymentMethodFormModel.swift:1   PaymentMethodsView.swift:1
ExportFixtures.swift:2  PaymentMethodOverviewTests.swift:2  TestSupport.swift:2
PaymentMethodStoreTests.swift:7  SubscriptionDetailStoreTests.swift:1
DynamicTypeTests.swift:2  EmptyStateTests.swift:1
```

Ten files, three of them production sources, including `SubscriptionDetailStoreTests.swift:34`'s `label: "Bank ..4821"`. `<last4>` genuinely appeared only in `docs/next-wave.md` and `reviews/BASELINE.md`, so half the claim holds. The de-identification itself is right and I am not asking for it to be reverted; the sentence justifying its severity is wrong, and it was inherited from `reviews-2/REVIEW-5.md` finding 8 without being re-derived — which the run's own standard forbids.

### 8. P3 — N2-3 disappears from the record with no note

`reviews-2/REVIEW-4.md:101,133` and `reviews-2/REVIEW-5.md:219` both reason about **N2-3** by identifier. `PROD-READINESS-2.md` contains no `N2-3` anywhere, and the NEXT ROUND list runs N2-1, N2-4, N2-2. The document has a section built for precisely this — `## NOT DEFECTS`, *"a finding that no longer reproduces at HEAD is moved here with its evidence rather than fixed"* — and it says "Nothing yet". A reader following REVIEW-5's citation finds a hole.

---

## Checked and found clean

- **No SwiftData schema change, in this stage or in the branch.** `git diff --name-only main..3ce3e01` touches no file under `Packages/OttoPersistence/Sources/OttoPersistence/Schema/`; no `Stored*` model, no `OttoSchemaV*`, no `OttoMigrationPlan`. The V3 freeze holds. The stage's only persistence-side edit is to a test file.
- **No prohibited action by the builder.** The range's file list is nine files: the ledger, `reviews-2/REVIEW-5.md`, and seven `.swift` files under `Packages/`. `.swiftlint.yml`, `.github/workflows/`, `project.yml`, every `Package.swift`, `PROD-READINESS.md`, `reviews/`, `DECISIONS.md` and `docs/` are all absent. `refs/remotes/origin/main` is unchanged at `406a5a6`, there is no `.git/FETCH_HEAD`, `ORIG_HEAD` dates from Aug 8, `git tag` is empty, and the reflog across the range contains only `commit:` entries — no fetch, push, rebase, reset or tag operation. `git branch -a --contains 3ce3e01` lists the working branch alone.
- **No new dependency, no new config key, no new public API.** `OttoLog.failures(_:)` is `static func`, internal like its sibling `list(_:)`; nothing else is added. No `Package.swift` or `project.yml` change.
- **No feature smuggled in.** The only production change in the range is six lines in `NotificationScheduler.reconcile`'s log statement plus the helper it calls. No user-facing copy, view, setting, or navigation. `R5-2` ships **no** production change at all, as claimed — `cac78f8` is one new test file and a corrected doc comment.
- **No test skipped, disabled or weakened.** No `.disabled(`, `.enabled(if:`, `withKnownIssue` or removed test in the range. The one rewritten test (`MappingLogPrivacyTests`) I falsified directly with `7a3cf54`'s exact pre-fix call site: **2 issues**, `:91` and `:102`. The rewrite narrows the value check to this test's own line and adds a broader `<private>` check across every line in the window, which is REVIEW-5 finding 4's remedy and is strictly better attribution; the in-loop `<private>` check is now unreachable (a redacted line cannot contain `cycleStartDay`), but the assertion that catches it is present one line later. Simulator known-issue count is 7 before and after.
- **The two new guards fail for the right reason.** Both falsifications above fail at content assertions, not at setup. `SchedulingLogTests` discriminates by `fixtureUUID(77)` and `NotificationActionLogTests` by the full `<uuid>|<day>|<kind>` identifier; `git grep` confirms indices 77 and 88 are used by no other OttoUI test, so neither can bind to a sibling's line. The privacy assertions are not vacuous: `TestSupport.swift:50` makes `"FoodApp"` the fixture's default vendor name, so `#expect(!line.contains("FoodApp"))` is a real check on a name that really is in the seeded subscription.
- **Verification exercises the changed path.** `theEmittedReconcileLineCarriesReasons` drives the real `NotificationScheduler.reschedule` through the real `reconcile` and reads the real emitted line back out of the process's log; reverting the call site fails it. `OttoLog.failures` also has unit-level guards for ordering, the empty case and the value-vs-type rule (`#expect(!rendered.contains("("))`).
- **No fix relocated a bug.** The scheduler change is confined to one interpolation; `failures` is still collected, still rethrown as `failures.first`, and the log statement still precedes the throw. The `throw` ordering comment added at `:203-206` describes existing behaviour and changes none.
- **No error is hidden.** `OttoLog.failures` renders `type(of:)` only, so no error payload reaches the log — the rule the file already states and item 5 restored on the persistence side. The caller half of `RF-3` is stated as out of reach rather than quietly narrowed (`:301`).
- **Severity, checked in both directions.** `RF-3` and `R5-2` were both P2 in round 1 and stay P2; neither is inflated. The `N2-4` disclosure is not deflated in kind — the truncation is real and reproduces exactly as quoted — only in reach (finding 2). ITEM 7's disclosure that `R5-1` remains unguarded is accurate: `aHandledActionIsRecorded` pins that the `handled` line exists, not that the snooze scheduled anything, and the ledger says exactly that.
- **Nothing marked RESOLVED without an artifact.** `0ffe160` and `cac78f8` both exist, both contain what their rows claim (`git show --stat`), both build, and both guards fail when the fix is broken. `d00c086`'s late addition to the `R4-1` and `R3-1` rows — REVIEW-5 finding 2's remediation — is correct: `d00c086` is where the shipped one-conjunct predicate and the three-argument wiring guard live.
- **The `<head>` placeholder in the range table is honest.** Stage 6's row reads `5d8ed6a..<head>` / *(pending)* because the verdict is this file. The start was recorded when the stage opened, which is the discipline `:54` describes. The grouping of two items into one stage is disclosed at `:56` rather than left to be noticed.

## Prohibited actions by me: none

All falsification was done in four scratch clones under the session scratchpad (`r6rev/h`, `r6rev/f`, `r6rev/p` at `5d8ed6a`, `r6rev/b` for the per-commit build sweep), never in the repository. Every clone was restored with `git checkout -- .` and confirmed empty by `git status --porcelain`; the one file I added to a clone (`ZZProbeN24Tests.swift`, my own N2-4 probe) I deleted myself. No network call of any kind: `scripts/verify.sh` and every clone read the local repository over a filesystem path, and refs were inspected with `git show-ref`, `git branch -a --contains` and `git log` only. No physical device; the iOS Simulator (`<simulator-udid>`) was used as permitted. Nothing in `<backup-dir>` was read, moved or modified; no file was deleted that I did not create; no `rm -rf` on any path. This file is the only file I wrote.

The repository is at `3ce3e01` with no modification to any tracked file; the sole working-tree entry is this review, untracked at `reviews-2/REVIEW-6.md`.
