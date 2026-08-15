# REVIEW-4 — stage 4, range b006d20..ce66bf7

verdict: REJECT

The stage's four items are real fixes, and most of the ledger reproduces: every falsification row I could run reproduces exactly, the three simulator falsifications for R4-2 land on the assertions the ledger names, the widened lint rule closes REVIEW-3 finding 1 including a spelling the remediation text does not claim, REVIEW-3 finding 2 is genuinely closed, the K sweep re-derives to the digit, and the "missing canary in round 2's record" claim is true.

It is rejected on two things.

**The stage ships a nondeterministically failing test, in the commit whose message is "Stop the boundary log guard depending on which suite logged last".**
`BoundaryLogTests` failed **3 of 12** full `swift test --package-path Packages/OttoUI` runs at `ce66bf7` on this host, at `BoundaryLogTests.swift:110`, on a randomly generated episode UUID emitted by a *sibling* suite.
The remediation that widened the privacy loop to "every line in the window rather than only this test's" is what made a foreign random value load-bearing.
That is the same defect class the commit exists to remove, reintroduced one line below the one it fixed. `verify.sh` and CI run the same suite by the same command, so they will red at a rate of that order; my own four `verify.sh` runs happened to pass, which four runs cannot distinguish from bad luck.

**The R0-5 read fix regresses the case it is about.** `OttoStore.watermarkDay` takes `min()` over RAW `Int`s and validates afterwards, so a corrupt duplicate row now deterministically shadows a perfectly readable one and the subscription materializes from TODAY — F6's exact signature, which the fix exists to remove a third route into. Measured: `nil` at `ce66bf7`, `2026-06-01` at the pre-fix `rows.first` shape. The sibling fix in the same commit (`OttoStore+Watermarks.swift:76-79`) validates *before* the `min` for precisely this reason; the read path does not.

Seven further findings: one more claim the code does not support (finding 3), three more tests that pass on evidence they did not produce (findings 4, 5, 9), and three record-keeping errors (findings 6, 7, 8).

## What I ran

All mutation work in two detached worktrees under a scratch path I created, both at `ce66bf7`; both are removed and the main tree was never modified. No commit was created. The main tree carries the builder's concurrent post-`ce66bf7` work (`7086e00`), which is outside this range and which I did not touch — every citation below is re-read from `git show ce66bf7:<path>`, not from the live tree.

**Baseline, all four measurements, at the reviewed HEAD. I ran all four; I reasoned about none of them.**

```
$ ./scripts/verify.sh                          # exit 0
== VERIFIED: ce66bf7fef0d03e6ee1e6aa01035af5b89326f87 builds, tests, and lints from a clean clone
   OttoDomain: 258
   OttoPersistence: 123
   OttoUI: 207
   total: 588 tests

$ swiftlint --strict                           # SwiftLint 0.65.0
Done linting! Found 0 violations, 0 serious in 220 files.

$ cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"   # exit 0
✔ Test run with 117 tests in 22 suites passed after 3.817 seconds.
✔ Test run with 72 tests in 12 suites passed after 0.070 seconds.
✘ Test run with 36 tests in 7 suites passed after 2.956 seconds with 7 known issues.
** TEST SUCCEEDED **

non-Gregorian harness (command from CalendarEraTests.swift's header, bundle path absolute, from the repo root):
  th_TH@calendar=buddhist          207 tests, 1 issue   DisplayFormattingTests.swift:49
  ja_JP@calendar=japanese          207 tests, 1 issue   DisplayFormattingTests.swift:49
  ar_SA@calendar=islamic-umalqura  207 tests, 5 issues  DisplayFormattingTests.swift:49,59,68,69
                                                        NotificationReconciliationTests.swift:170
```

565 → 588 is +23, exactly what the ledger claims. The simulator's 108/70/31 → 117/72/36 is **+16**, not the +14 the ledger records (finding 6). The 7 known issues are the same seven `EmptyStateTests` accessibility assertions; the non-Gregorian issue counts and all five file:line citations are `BASELINE-3.md:143-171` unchanged.

**Every commit in the range builds, all three packages** — swept in the worktree, `swift build --build-tests` per package per commit:

```
8ceaf9c OttoDomain OK  OttoPersistence OK  OttoUI OK
8ed5577 OttoDomain OK  OttoPersistence OK  OttoUI OK
bd781e7 OttoDomain OK  OttoPersistence OK  OttoUI OK
20ad49c OttoDomain OK  OttoPersistence OK  OttoUI OK
28cfa03 OttoDomain OK  OttoPersistence OK  OttoUI OK
4380736 OttoDomain OK  OttoPersistence OK  OttoUI OK
ce66bf7 OttoDomain OK  OttoPersistence OK  OttoUI OK   (+ verify.sh, which also builds the app target)
```

**Mutation testing of every test added or changed in the range** — 17 mutations, tabulated under Explicit checks 10. Every ledger falsification row I could re-run reproduces; three tests survive mutations the ledger does not claim (findings 1, 4, 9).

**Repeat runs for flakiness.** 12 unmutated full `swift test --package-path Packages/OttoUI` runs (3 failed — finding 1), 4 `verify.sh` runs (all exit 0), 3 non-Gregorian harness runs, 6 simulator runs.

**Two independent re-derivations.** The K sweep for the rejected `createdAt` rule, from a standalone `xcrun swift` script that imports only Foundation. A mechanical strip-and-diff of the `SubscriptionFlowService` split.

## Findings

### 1. `BoundaryLogTests` fails about one run in four, on a random UUID emitted by another suite

- severity: **P1**
- evidence: 12 unmutated full-suite runs at `ce66bf7` in a clean worktree; **3 failed**, always at the same assertion.

  ```
  run 3: ✘ BoundaryLogTests.swift:110:13: Expectation failed:
    !((entry → "cancellation started id=00000000-…-000000000001
       episode=AF52516D-6999-4AAB-A5C8-0ACE097832D9 checkDay=2026-08-15").contains("999") → true)
  run 8: ✘ BoundaryLogTests.swift:110:13: Expectation failed:
    !((entry → "cancellation started id=00000000-…-000000000002
       episode=9491A2EF-D535-4E54-9990-9D877862829F checkDay=2026-08-15").contains("999") → true)
  (a third, episode=5C94E2CD-2CF8-42FF-9E7C-C4F99969159B, in an earlier batch)
  ```

  The mechanism is exact. `BoundaryLogTests.swift:108-112` asserts the privacy rule over **every** line in the window, siblings' included. `SubscriptionFlowService+Cancellation.swift:88` logs `episode=\(episode.id.uuidString)`, and that id comes from `openingCancellationEpisode(id: UUID(), …)` — a fresh random UUID on every call. A random UUID string carries the substring `999` with probability ≈ 22/4096 ≈ 0.54 %, and one full-suite window holds ~20-25 distinct episode UUIDs from `SubscriptionFlowTests`, `VerificationFlowTests` and friends. None of the three failures involved this test's own fixture at all; two of them name `id=…0001`, which is not this test's subscription (`index: 91`).

  `#expect(!entry.contains("999"))` is a tripwire for the fixture's amount `999_99`. It is checked against a population — every value any sibling can put in the `transfer` or `flows` categories — that the test does not control and that contains randomly generated hex.

  This reaches `verify.sh`, which makes the identical `swift test --package-path Packages/OttoUI` call in a clean clone, and `.github/workflows/ci.yml`. It is the same route by which the *previous* version of this test was caught, which the ledger records: "It passed in isolation, passed under `swift test`, and failed in the clean clone." My own 4 `verify.sh` runs all exited 0, which at 25 % has probability 0.32 and is not evidence against the finding.
- why the builder missed it: the tripwire was written from the fixture (`Zzyzx`, `999`, `$`, `/`) and validated against the fixture, so the rule and its test shared one premise — the shape this run has now recorded four stages running. Commit `4380736` then widened the loop's scope from "this test's lines" to "every line in the window" *on purpose*, and the risk that widening created is the opposite of the one it was fixing: `.last` picking a foreign line was a false pass, a foreign line tripping an absolute assertion is a false fail. The comment added at `:105-107` reasons about the first and not the second. A single passing run after the change is not evidence about a 25 % event.

### 2. The R0-5 read fix makes a corrupt duplicate row shadow a readable one, which is the failure it exists to remove

- severity: **P2**
- evidence: `OttoStore.swift:103` is

  ```swift
  guard let stored = rows.compactMap(\.lastMaterializedThrough).min() else { return nil }
  guard let day = CalendarDay(yyyymmdd: stored) else { … log … ; return nil }
  ```

  The `min` runs over **raw `Int`s, before any validation**, and `0` — the ledger's own example of "the shape a partially written row takes" — is smaller than every real packed day. So one corrupt row in a duplicate pair discards the readable one. Probe in my worktree, two rows for one subscription, `20260601` and `0`:

  ```
  at ce66bf7                          PROBE corrupt+valid -> nil
  with the pre-fix rows.first shape   PROBE corrupt+valid -> Optional(2026-06-01)
  ```

  A `nil` watermark sends `materializeEvents` back to TODAY — the ledger states this itself, twice — so the change turns a recoverable state into F6's signature. It also contradicts the justification shipped three lines above it (`OttoStore.swift:93`): "a watermark errs earlier, never later"; `nil` errs *later*.

  This is not a hypothetical pairing. Duplicates are the premise of the change ("There is no unique constraint (CloudKit forbids one)", `OttoStore.swift:90-91`), and the unvalidated V2→V3 carry-over the ledger cites (`OttoMigrationPlan.swift:242,247`, verified — both branches assign `carry.watermark` with no validation) is what puts a corrupt value beside a good one in the first place.

  The correct shape is in the same commit: `OttoStore+Watermarks.swift:76-79` filters on `CalendarDay(yyyymmdd: stored) != nil` **before** the `min`, with a comment explaining exactly this hazard. The read path did not get the same treatment.

  No test covers the mixed case: `duplicateRowsTakeTheMinimum` seeds two *valid* values, `corruptIsLoggedAndAbsentIsNot` seeds one corrupt row alone.
- why the builder missed it: two defects were fixed in one method — "log the unreadable value" and "make duplicate selection deterministic" — and each was falsified with a fixture that contains only its own defect. The interaction between them has no fixture, and the `min` reads as safe because in the *other* method, where it was written correctly, it is.
- note, recorded rather than quietly dropped: the main working tree at the time I finished carries an **uncommitted** edit to this exact method that moves the validation before the minimum and logs every unreadable row rather than one. That is the builder's own concurrent work at `7086e00`, outside this range and after this range's HEAD; I read it (read-only) to confirm the dirty file was not mine and did not touch it. The finding stands against `ce66bf7`, which is what was submitted for review, and it still needs the missing fixture — a corrupt row beside a readable one — before it can be called closed.

### 3. "Logs every exit" is false: five non-throwing early returns in the §5.4 flows are still silent

- severity: **P2**
- evidence: the ledger's ITEM 6 says "`SubscriptionFlowService`'s cancellation half logs **every exit** — started, refused with a reason, abandoned with the day the watermark rewound to, and both verification answers", and the shipped comment at `SubscriptionFlowService+Cancellation.swift:36` says "F11: every exit from this flow says which one it was."

  Exits in that file at `ce66bf7` that return without logging anything:

  ```
  :71   startCancellation   guard let restored = subscription.abandoningCancellation(...) else { return nil }
  :80   startCancellation   guard let opened  = subscription.openingCancellationEpisode(...) else { return nil }
  :114  abandonCancellation guard let subscription = ... else { return }
  :128  abandonCancellation guard let reference, let restored = ... else { return }
  :223  answerVerification  guard let chargeDay = disputed.nextChargeDateIfNotCancelled else { return nil }
  ```

  `:80` is the one that matters most: `openingCancellationEpisode` returns nil when the lifecycle is already past cancellation, so a "Cancel this" that opened no watch returns nil to `NotificationActionHandler`, which reports it as `effect=notApplicable`, and nothing anywhere says which of the two nil-returning reasons it was. That is verbatim the state the comment four lines above it describes as the defect being closed.
- why the builder missed it: the two exits that got a log are the two the item's summary names ("refused", "started"), and both sit at the top and bottom of the method where they are visible when you write the log lines. The three in the middle are `guard let … else { return nil }` one-liners that read as plumbing rather than as outcomes.

### 4. The R5-1 test's "a snooze that worked" line is supplied by a different test, and it passes when this test does not snooze at all

- severity: **P2**
- evidence: `NotificationActionLogTests.swift:142` is `lines.last { $0.contains(workingIdentifier) }` — the `.last`-over-a-shared-window shape that `4380736` removed from `BoundaryLogTests` one commit later, left in the file `28cfa03` had just edited.

  `aHandledActionIsRecorded` (`:94`) and `aSnoozeThatScheduledNothingSaysSo` (`:142`) both snooze the identical rung, because both call the same `seedTrial` (`index: 88`) and build `PlannedReminder(subscriptionID:…, day: trial.cancelByDate, kind: .trialDayOfMorning)`. Dumping the `actions` window from inside the second test during a full-suite run shows the line twice, and it only emits one:

  ```
  ACTWIN| handled action=otto.action.remindLater id=00000000-…-000000000088|2026-08-08|trialDayOfMorning effect=scheduled
  ACTWIN| handled action=otto.action.remindLater id=00000000-…-000000000088|2026-08-08|trialDayOfMorning effect=scheduled
  ```

  Direct proof: replacing `for identifier in [workingIdentifier, orphanIdentifier]` with `[orphanIdentifier]` — so the test never snoozes the working rung — leaves it **passing 3 runs out of 3**:

  ```
  ✔ Test "⛔ a snooze that scheduled nothing does not log what a snooze that worked logs" passed after 13.295 s
  ✔ … passed after 22.028 s
  ✔ … passed after 13.949 s
  ```

  The test's stated discriminator is "the two lines DIFFER"; only one of the two is its own. The `didNothing` half is sound (UUID 4242 is unique), and the production falsification still bites — this is a defect in what the test proves, not in the fix.
- why the builder missed it: the same flakiness was diagnosed and fixed for `BoundaryLogTests` in the very next commit, but the diagnosis was scoped to the file that failed in `verify.sh` rather than to the technique. `index: 88` was chosen to isolate this suite from *other* suites and does not isolate its two tests from each other.

### 5. The flakiness remediation weakened two assertions' content, and the ledger discloses only the selector change

- severity: **P2**
- evidence: `git show 4380736` changes, besides `.last` → `contains`:

  ```
  -#expect(try line("export kind=json").contains("subscriptions=1"))     → expectLine("export kind=json", "subscriptions=")
  -#expect(try line("import preview").contains("databaseEmpty=false"))   → expectLine("import preview",  "databaseEmpty=")
  ```

  `databaseEmpty=` is satisfied by `databaseEmpty=true`, so the field's *value* is no longer asserted at all; a regression that always reported the database as empty would pass. `subscriptions=` likewise no longer asserts the count. The ledger's account of this commit says only "Now it asks whether **any** line in the window carries both parts, and the two lines that carry an identifier are pinned to this subscription's UUID" — it does not say that two fields lost their values. The stage's closing statement, "No pre-existing test was skipped, disabled or weakened", stays literally true because the assertions were four commits old rather than pre-existing; that is precisely the gap a disclosure rule scoped to *pre-existing* tests leaves open, and the ledger discloses everything else about this commit in detail.

  The consequence, measured: deleting **all four** of the test's own service calls (`exportJSONFile`, `exportChargesCSVFile`, `importPreview`, `performImport`) and running the full suite leaves the whole export/import half green, because `ExportServiceTests` supplies every line.

  ```
  // REVIEW-4 EXPERIMENT: this test performs NO export and NO import.
  ✔ Suite "The boundaries that recorded nothing (F11)" passed after 21.293 seconds.
  ```

  The pinning technique that would have fixed this without weakening anything is in the same diff — the three-way conjunction the builder wrote for `verification answered` at `:95-101`.
- why the builder missed it: the flake was diagnosed as "`.last` picked a sibling's line", which is true, and the minimal edit that makes a sibling's line acceptable is to drop the parts of the assertion a sibling cannot satisfy. Reframing the fix as "make the window contain a line only this test could have written" was available and is what the two identifier-bearing assertions already do.

### 6. The simulator delta in the stage-4 verification table is +16, recorded as +14

- severity: **P3**
- evidence: `PROD-READINESS-3.md:492` (at `ce66bf7`): `| simulator suite | 108 / 70 / 31, 7 known issues | **117 / 72 / 36**, … | +14, this run's new simulator tests |`. 117 + 72 + 36 = 225; 108 + 70 + 31 = 209; the delta is **16**. I measured 117 / 72 / 36 myself, so the measured numbers are right and only the arithmetic is wrong. The `verify.sh` row in the same table (+23) reconciles exactly.
- why the builder missed it: the third bucket's own delta is +5 and this stage's simulator contribution is +9 (4 in bucket 1, 5 in bucket 3); the verdict column mixes a per-stage number into a since-baseline row, and no other row in the table has that ambiguity to expose it.

### 7. ITEM 6's falsification table quotes an assertion the shipped test no longer contains

- severity: **P3**
- evidence: `PROD-READINESS-3.md` ITEM 6 records all three falsifications as failing at `lines.last { $0.contains(needle) } → nil`. `4380736` deleted that expression. Re-running the same three mutations at `ce66bf7` gives, in every case:

  ```
  ✘ BoundaryLogTests.swift:80:13: Expectation failed: lines.contains { $0.contains(needle) && $0.contains(field) }
  ```

  The ledger says the falsification "was re-measured after the change", so the measurement was presumably redone; the evidence quoted is from before it.
- why the builder missed it: ITEM 6's table was written at `20ad49c` and the remediation two commits later edited the prose paragraph beneath it rather than the table above it.

### 8. REVIEW-3 finding 4's remedy is described as a stage-3 baseline table, and no stage-3 table exists

- severity: **P3**
- evidence: the remediation list says "the stage-3 baseline table is now recorded below (it was missing, and the ledger's only table was stale)". The table below is headed "VERIFICATION AT THE END OF STAGE 4" and is measured at `4380736`. The stale table REVIEW-3 named is still at `PROD-READINESS-3.md:264-267`, still headed "Baseline at the end of this stage" with no commit, and still reads `578` and `113 / 70 / 31` where REVIEW-3 measured 580 and 113 / **72** / 31 at `b006d20`. A reader now meets three tables of four measurements, two of them unlabelled by commit and one of them wrong.
- why the builder missed it: the finding was routed with the five other P3s in one bullet, and "record the missing table" was satisfied by the table the stage was writing anyway.

### 9. `zeroIsUnreadable` passes with the entire R0-5 read fix reverted

- severity: **P3**
- evidence: under mutation M2 (the read reverted to `rows.first?.lastMaterializedThrough.flatMap(CalendarDay.init(yyyymmdd:))`, i.e. the pre-fix shape the item exists to replace), the suite records issues in `corruptIsLoggedAndAbsentIsNot` and `duplicateRowsTakeTheMinimum` only — `zeroIsUnreadable` passes, because `CalendarDay(yyyymmdd: 0)` was already nil before the change. It is a characterisation test for pre-existing behaviour counted among the four the item claims. Harmless on its own; it inflates the item's apparent coverage by one.
- why the builder missed it: it reads as a second case of the corrupt-value test, and its title ("the shape a partially written row takes") describes a real input; nothing about it signals that the input was already handled.

## Explicit checks

1. **Fabricated or unreproducible findings.** The ledger's measured numbers reproduce, with two exceptions (findings 6 and 7). `verify.sh` 258/123/207 = 588 exact. Simulator 117/72/36 with 7 known issues exact. Non-Gregorian 1/1/5 at the same five citations exact. `onOutcome` occurrences in `handleBackgroundRefresh` at `b006d20`: **0**, as claimed. `OttoMigrationPlan.swift:242,247` do assign `lastMaterializedThrough` unvalidated, in both branches. The K sweep re-derives **exactly** from a standalone Foundation script — `K=1 → 3/4001 (0.07 %)`, `K=3 → 7`, `K=7 → 15`, `K=31 → 64`, sensitivity 13/13 throughout, and the K=1 anchors are 2018-11-29/30 and 2018-12-01 by Ethiopic. That means the ledger is right and `REVIEW-3.md` finding 3's 2/14/63 was the off-by-one; the ledger publishes the correct figures without noting that it is contradicting the reviewer's "not reproducible to the digit" claim, which is a transparency gap rather than an error.
2. **Citations that don't say what they're claimed to say.** Two, findings 7 and 8. `SettingsView.swift`'s new comment cites the pre-existing alert at ":275-285" — the alert block is `:274-284`, close enough to be a pointer and not a claim. The "discrepancy in round 2's record" is **verified**: `grep -rn requireDelivered` finds it in `NotificationActionLogTests`, `SchedulingLogTests`, `BoundaryLogTests` and the new `OttoPersistenceTests/OttoLogProbe.swift`, and `MappingLogPrivacyTests.swift:91` asserts `#expect(!ours.isEmpty, …)` with no canary anywhere in the file. `PROD-READINESS-2.md`'s "each of the four" is wrong and the ledger's correction is right.
3. **Severity inflation or deflation.** One deflation, finding 3: "logs every exit" is stated as a completed property of the flow and five exits do not have it. Nothing is inflated. The stage's self-assessment of ITEM 4's residuals (`start()` unreachable, the delegate half untested, nothing proved about the real daemon) is accurate and if anything understates what it did achieve.
4. **Features smuggled past the no-features rule.** None found. The only user-visible change is `SettingsView.swift:230-238`, which routes a real `.fileImporter` failure to the alert that already existed at `:274-284` with the already-localised title "Nothing was imported" and the same `error.localizedDescription` message the sibling `preview()` catch has always used. No new screen, setting, navigation, or localised string. `ImportPickerOutcome`/`importPickerOutcome(of:)` and `BackgroundRefreshTask` are new *public API* in `OttoServices`, which is a module boundary change rather than a feature; `appDidBecomeActive()`'s new return type is source-compatible via `@discardableResult` and the app target is byte-identical in this range (`git diff --stat b006d20..ce66bf7 -- Otto/` is empty) and builds under `verify.sh`.
5. **Any SwiftData schema change.** None. No file under `Packages/OttoPersistence/Sources/OttoPersistence/Schema/` is touched, no `OttoSchemaV*.swift`, no `OttoMigrationPlan.swift`, no versioned model. The two persistence source files changed are `Store/OttoStore.swift` and `Store/OttoStore+Watermarks.swift`; V3 is not lifted.
6. **Prohibited actions.** None found. `git diff --name-only b006d20..ce66bf7` touches 19 files, of which the only documents are `PROD-READINESS-3.md` and the new `reviews-3/REVIEW-3.md`; no `.github/workflows/`, no `docs/`, no `PROD-READINESS.md` / `-2.md`, no `reviews/` or `reviews-2/`, no `DECISIONS.md`. Zero deletions or renames (`--diff-filter=DR` is empty). Zero added `.package(` lines — `OttoUITests`' new `OttoServices` dependency is an internal target edge inside the existing `Packages/OttoUI/Package.swift`. `.swiftlint.yml` against the run's baseline `8806853` adds one `custom_rules` entry and nothing else: no rule relaxed, disabled or re-thresholded, `excluded:` is still exactly `Packages/*/.build`, and the new rule carries no `excluded:` of its own. `git reflog --all` shows the seven range commits as plain `commit:` entries with no `rebase`, `amend` or `reset`; no tags exist; no `FETCH_HEAD`; `refs/remotes/origin/main` is still `406a5a6`, matching `BASELINE-3.md`. I made no network call.
7. **Fixes that relocated a bug rather than removed it.** The `SubscriptionFlowService` split **is** behaviour-preserving, proved mechanically rather than read: stripping comments and `OttoLog` statements from the removed block and from the new file and diffing leaves only the file scaffolding (`import`s, `extension SubscriptionFlowService {`) and one rewrite, `if let archived = subscription.archiving(at: now) {` → `let archived = subscription.archiving(at: now); if let archived {`, which exists so `archived != nil` can be logged and is semantically identical. Actor isolation is preserved (same-module extension of the actor); the widened `subscriptions`/`billingEvents` are `internal`, so nothing leaves the module; `SubscriptionFlowService.swift` retains `private let priceChanges`. The relocation finding in this range is elsewhere: finding 2, where the R0-5 fix moves a nondeterministic wrong answer to a deterministic wrong answer in the more harmful direction.
8. **Error handling that hides errors.** `ExportService.importPreview` and `performImport` both log and **rethrow** — nothing swallowed. `importPickerOutcome` converts a dropped `.failure` into a logged, alert-raising `.failed`, which is strictly more error handling than before, and discards only the error object in favour of its `localizedDescription`. `route` returns `.unroutable` where it previously returned a `.none` indistinguishable from four other reasons. The one place where this stage makes a path *hide* something is finding 2: a readable watermark is now discarded in favour of a corrupt sibling row. Finding 3 is the adjacent one — five paths that were supposed to stop being silent and did not.
9. **Verification that doesn't exercise the changed path.** The simulator target really does run the new tests: `-only-testing:OttoUITests/NotificationCoordinatorTests` executes 5 tests, and the full simulator run's third bucket moves 31 → 36 across 6 → 7 suites. The `os_log` per-entry budget (N2-4) is not a risk for any new line: the longest is `cancellation started id=<36> episode=<36> checkDay=<10>` at **124 characters** as actually emitted, against the ~1050-character cap round 2 measured, so nothing asserted here can be truncated away. Gaps: `SettingsView`'s routing of `.failed` to the alert has no test (disclosed), the `deadlinePassed` effect has no test (disclosed), and the three unlogged flow exits in finding 3 have neither a log nor a test.
10. **Tests that pass for the wrong reason.** I broke the thing each added or changed test claims to guard. 17 mutations; three survived.

    | test | mutation | result |
    |---|---|---|
    | `corruptIsLoggedAndAbsentIsNot` | delete the `watermark unreadable` statement | fails, `lines.last { … } → nil` |
    | | revert the read to `rows.first?…flatMap` | fails, +`duplicateRowsTakeTheMinimum` — the ledger's 2 issues, exact |
    | `duplicateRowsTakeTheMinimum` | same revert | fails, `read == (try day(2026, 6, 1))` |
    | `reconstructionIgnoresAnUnreadableCap` | drop the cap validation | fails, reconstruction pinned at the corrupt value |
    | `zeroIsUnreadable` | the whole read fix reverted | **passes** — finding 9 |
    | (none) | corrupt row beside a valid one | **no test exists** — finding 2 |
    | `theBoundariesRecordThemselves` | delete `export kind=json` | fails at `:80` |
    | | delete `import begin` | fails at `:80` |
    | | delete `import preview` | fails at `:80` |
    | | delete `cancellation started` | fails at `:80` |
    | | delete `verification answered chargesStopped=true` | fails at `:80` and `:95` |
    | | delete the test's own four export/import calls | **passes** — finding 5 |
    | `pickerOutcomesAreDistinguished` | every failure treated as a cancel | fails at `:128` and `:130` |
    | `aHandledActionIsRecorded` (strengthened) | remove `effect=` | fails at `:103` |
    | `aSnoozeThatScheduledNothingSaysSo` | remove `effect=` | fails at `:150`, `:151` (4 issues over 3 tests, exact) |
    | | `snooze` reports `.scheduled` unconditionally | fails at `:151`, exact |
    | | remove this test's own working-rung snooze | **passes 3/3** — finding 4 |
    | `anUnroutableIdentifierSaysSo` | `.unroutable` → `.notApplicable` | fails at `:172` |
    | `foregroundFailurePublishesNil` | `rescheduleSoon` back to its pre-F3 shape | fails, `(published.count → 0) == 1`, `(published → []).first → nil` |
    | `backgroundPassPublishes` / `backgroundFailurePublishesNil` | remove `onOutcome?(outcome)` | fails, 4 issues over 2 tests, exact |
    | `expirationCompletesOnce` | remove the `completion.claim()` guard | fails, `(task.completions → [false, true]) == [false]`, exact |
    | `reportedDaysAreDedupedAndSorted` | remove `.sorted()` | fails, `[2569-08-06, 2569-08-20, 2569-07-01]` — REVIEW-3 finding 2 closed |
    | | remove the dedup `Set` | fails, `Set(reported).count → 3` vs `reported.count → 4` |

    The lint rule is falsified separately, six spellings substituted into `DisplayFormatting`'s three defaults, control clean:

    ```
    control                                                       rc=0, 0 violations
    Calendar.current                                              rc=2, 3 violations
    .current                          (implicit member)           rc=2, 3 violations
    Locale.current.calendar                                       rc=2, 3 violations
    Calendar(identifier: Locale.current.calendar.identifier)      rc=2, 3 violations
    Calendar    =    .current         (extra whitespace)          rc=2, 3 violations
    Locale.autoupdatingCurrent.calendar                           rc=2, 3 violations
    ```

    REVIEW-3 finding 1 is closed, and the fourth spelling it named (`Calendar(identifier: Locale.current.calendar.identifier)`) is caught too, which the remediation text does not claim. The residual REVIEW-3 also named — deleting `components.calendar = CalendarDay.conversionCalendar` outright — is still lint-clean and is still not disclosed in ITEM 3's "What this does NOT do", which covers only the implicit-`Date.FormatStyle` and `conversionCalendar`-identity blind spots.
11. **Flaky or environment-dependent tests.** One, and it is finding 1: 3 failures in 12 unmutated full-suite runs, caused by another suite's random UUID, in a test whose whole subject is the log window shared with those suites. The related-but-benign case is finding 4. `BoundaryLogTests`' other tripwires are safe today and are the same class of hazard: `bytes=` counts already reach four digits in the window (`bytes=794`, `bytes=1053`), and `!entry.contains("999")` is asserted against them too, so a fixture change alone can make this deterministic. The remaining new tests are clean: the coordinator tests were green in all 5 simulator runs I made of them and are deterministic by construction — `Task {}` inherits the coordinator's `@MainActor` isolation, so `task.expirationHandler?()` always runs to completion before the pass body starts; the persistence tests are serialised under `SerializedPersistenceTests`; all 207 host tests pass under all three non-Gregorian locales. This stage adds two more `OSLogStore` readers (six in OttoUI, one in OttoPersistence), which sharpens BASELINE-3's CANNOT ASSESS rather than softening it — the ledger says so.
12. **Anything marked resolved without an artifact.** All four items have artifacts I could re-run. Item 5's artifact is incomplete in the way finding 2 describes: the item is RESOLVED on three sub-changes and one of them introduces a regression no fixture covers. Item 6 is RESOLVED on a claim ("logs every exit") that measurement contradicts (finding 3).
13. **Every commit in the range builds.** Swept, all seven, all three packages — transcript above. `ce66bf7` additionally builds the app target under `verify.sh`.
14. **The baseline must not regress.** On a passing run it does not: 565 → 588 is this run's added host tests, `swiftlint --strict` clean over 220 files (215 + the 5 files this stage adds), simulator `** TEST SUCCEEDED **` with the same 7 `EmptyStateTests` known issues and the same 31-test bucket carrying them, non-Gregorian 1 / 1 / 5 at the same five citations. The qualification is finding 1: "exit 0" is now a ~75 % outcome rather than a property of the commit, so the baseline is not *stable* even though it is not regressed.

## What I could not check, and why

- **The rate at which finding 1 reaches `verify.sh` specifically.** I ran `verify.sh` 4 times at `ce66bf7` and it exited 0 all four times (588 tests each, and no `verify-*-failure.log` was ever written). That is not evidence against the finding — at the measured 25 %, four consecutive passes has probability 0.32 — and `verify.sh` runs the identical `swift test --package-path Packages/OttoUI` invocation on the identical suite, which is how the *previous* version of this same test was caught (the ledger says so). But 4 is too small a sample to put a rate on the script, so finding 1 quotes the rate I measured directly over 12 suite runs and does not claim one for `verify.sh`.
- **CI.** No run may be triggered and I read none. `.github/workflows/ci.yml` is unchanged in this range.
- **A physical device and Release configuration.** Prohibited / not built, as in every round. `BGAppRefreshTask`'s real behaviour stays CANNOT ASSESS; what this stage proves is the handler body against a fake, which is what it claims.
- **The `OSLogStore` tests on a CI runner.** Unchanged CANNOT ASSESS, now with two more readers in it.
- **Whether the three unlogged exits of finding 3 are reachable in production.** I read the guards and the domain methods behind them but did not build a fixture that drives `openingCancellationEpisode` to nil through the real store; the finding is about the claim, which is falsifiable from the source alone.
- **Non-Gregorian coverage beyond three locales.** Buddhist, Japanese and Islamic-umalqura only, as the harness offers.

Both worktrees are removed; `git worktree list` shows only `/Users/<user>/dev/otto`. The main working tree was never modified by this review: at the end of it `git status --porcelain` shows `?? reviews-3/REVIEW-4.md`, the only file this review writes, and ` M Packages/OttoPersistence/Sources/OttoPersistence/Store/OttoStore.swift`, which is the builder's own uncommitted concurrent work (see the note under finding 2) — I read it to confirm it was not mine and left it exactly as it was. No commit was created, no network command was run, and nothing outside this range was edited.
