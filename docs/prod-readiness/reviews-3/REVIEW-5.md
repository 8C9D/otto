# REVIEW-5 — stage 4 remediation, range ce66bf7..6d981f4

verdict: PASS-WITH-FINDINGS

The remediation is substantively sound, and the two things `reviews-3/REVIEW-4.md` rejected on are genuinely fixed rather than claimed fixed.
I re-ran the flake measurement independently: **12 of 12** unmutated full `swift test --package-path Packages/OttoUI` runs pass at `6d981f4`, 207 tests each, zero issues - the same sample size that measured 3 failures at `ce66bf7`.
The watermark read now validates before the minimum, and I falsified it: reverting `watermarkDay` to the `ce66bf7` shape fails the new test deterministically, and five edge cases the ledger does not claim (a nil column beside a value, two corrupt rows beside a value, only-nil rows, ordering over three readable values, a negative packed value) all behave correctly, with exactly two log lines for two corrupt rows.
Findings 4, 5, 6, 7 and 9 are closed, each with a mutation that reproduces at the assertion the ledger names.
Both function splits are behaviour-preserving and both were **required**: inlining them back with the new log lines produces `function_body_length` violations of 59 and 56 lines against the 50-line default, which I measured.

It is not a PASS on four things.

**ITEM 6's claim "logs every exit" is still false, for a sixth exit the list did not contain.**
`supplyPausedResumeDate` sits in the same `SubscriptionFlowService+Cancellation.swift`, is reached from a real button in `CancellationSectionView.swift`, and has two non-throwing exits, neither of which logs anything.
`PROD-READINESS-3.md:421` still reads "logs every exit", and the disclosure that was supposed to bound it (`N3-7`) says in terms "F11 named cancellation and verification; **those are closed**".
This is the exact failure mode of a remediation written against a list: the five named exits were fixed and the claim was not re-derived.

**None of the five new log statements is guarded.**
Deleting all five leaves the OttoUI suite at **207/207 green and `swiftlint --strict` clean**.
That is the same shape this run's own record already names twice - round 1 closed F2 with two log lines and an artifact quoted in a commit message, and `reviews/REVIEW-5.md` measured that deleting both left the suite green.

**REVIEW-4's finding 8 is not closed; the table is worse than it was.**
The stage-2 table was relabelled `e4f4872` and its simulator second bucket changed 70 → 72.
I measured `e4f4872` myself: host **256 / 119 / 201 = 576** (the table says 258 / 119 / 201 = 578, "+13"), simulator **113 / 70 / 31** (the table says 113 / 72 / 31).
The row that was right before the remediation is now wrong.

**One residual of the flake fix**, P3 and measured at ~1.1e-5 per run rather than 25 %: the amount tripwire is still asserted against a line carrying a random UUID the test does not control, which is precisely what the shipped comment says it no longer does.

## Status of REVIEW-4's nine findings

1. **`BoundaryLogTests` flake (P1)** — **CLOSED.** 12/12 unmutated full-suite runs at `6d981f4`, `✔ Test run with 207 tests in 38 suites passed` every time, `grep -c ✘` = 0 in all twelve logs. `!entry.contains("999")` over every line is gone. Residual: finding 4.
2. **Corrupt row shadows a readable one (P2)** — **CLOSED.** Mutation F (revert `watermarkDay` to the `ce66bf7` `min()`-then-validate shape) fails `aCorruptRowDoesNotShadowAReadableOne` at `CorruptWatermarkTests.swift:82`. Five independent edge-case probes pass; both corrupt rows are logged.
3. **"Logs every exit" false for five exits (P2)** — **PARTIALLY CLOSED.** All five named exits now log a reason, and all five are privacy-clean. A sixth exit pair in the same file does not (finding 1), and none of the five is guarded by a test (finding 2).
4. **R5-1 test's line supplied by a sibling (P2)** — **CLOSED.** Removing this test's own working-rung snooze now fails **3 runs of 3**, at `NotificationActionLogTests.swift:155`, `lines.last { $0.contains(workingIdentifier) } → nil` - the assertion the ledger names, exactly.
5. **Two assertions weakened, disclosed only as a selector change (P2)** — **CLOSED.** Deleting all four of the test's own export/import calls now fails with **2 issues**, both at the `expectLine` `#expect`. Production mutations that pin `subscriptions=1` and `databaseEmpty=true` also fail, 2 issues. The weakening is now disclosed in both the ledger and the source.
6. **Simulator delta +16 recorded as +14 (P3)** — **CLOSED.** I measured 117 / 72 / 36 = 225 against the baseline's 108 / 70 / 31 = 209; the table now says +16.
7. **ITEM 6's falsification table quoted a deleted assertion (P3)** — **CLOSED.** Deleting the `import begin` and `cancellation started` production statements reproduces at `lines.contains { $0.contains(needle) && $0.contains(field) }`, which is what the table now quotes, and the ledger adds an explicit note that the rows were re-measured.
8. **Stage-3/stage-2 table (P3)** — **NOT CLOSED.** See finding 3; two of the table's four numbers are wrong for the commit it now names, and one of them was right before the fix.
9. **`zeroIsUnreadable` is a characterisation test (P3)** — **CLOSED as a disclosure.** Renamed `aLoneUnreadableRowIsNil` and labelled "Characterisation, not a regression guard" in the source. I re-confirmed the substance: under the whole read fix reverted, it still passes, and the source now says so.

## What I ran

All mutation work in one detached worktree at `6d981f4` under a scratch path I created.
The worktree is removed and the main tree was never modified; no commit was created; no network command was run.

**Baseline, all four, at the reviewed HEAD. I ran all four; I reasoned about none of them.**

```
$ ./scripts/verify.sh                                            # exit 0
== VERIFIED: 6d981f4b609ac88c26a172c455a901a2d2905642 builds, tests, and lints from a clean clone
   OttoDomain: 258
   OttoPersistence: 124
   OttoUI: 207
   total: 589 tests

$ swiftlint --strict                                             # SwiftLint 0.65.0
Done linting! Found 0 violations, 0 serious in 220 files.

$ cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"   # exit 0
✔ Test run with 117 tests in 22 suites passed after 3.275 seconds.
✔ Test run with 72 tests in 12 suites passed after 0.083 seconds.
✘ Test run with 36 tests in 7 suites passed after 2.880 seconds with 7 known issues.
** TEST SUCCEEDED **

non-Gregorian harness (command from CalendarEraTests.swift's header, bundle path absolute, from the repo root):
  th_TH@calendar=buddhist          207 tests, 1 issue   DisplayFormattingTests.swift:49
  ja_JP@calendar=japanese          207 tests, 1 issue   DisplayFormattingTests.swift:49
  ar_SA@calendar=islamic-umalqura  207 tests, 5 issues  DisplayFormattingTests.swift:49,59,68,69
                                                        NotificationReconciliationTests.swift:170
```

565 → 589 is +24, exactly what the ledger claims, and the +1 over `ce66bf7`'s 588 is the one persistence test this range adds.
Simulator 209 → 225 is +16, which the corrected table now records.
The 7 known issues are the same seven `EmptyStateTests` accessibility assertions, in the same 36-test bucket; the non-Gregorian counts and all five citations are `BASELINE-3.md:143-171` unchanged.

**The flake, 12 unmutated full runs.**

```
run  1: ✔ Test run with 207 tests in 38 suites passed after 17.077 seconds.
run  2..12: ✔ 207 tests, passed (11.8 s - 14.8 s)
summary: 12 runs, rc=0 × 12, "✘" occurrences in every log: 0
```

**Every commit in the range builds, all three packages.**
Only `ef7e9b8` touches code; `7086e00` and `6d981f4` are ledger-only, which I confirmed from `git show --stat`.

```
7086e00  OttoDomain OK  OttoPersistence OK  OttoUI OK
ef7e9b8  OttoDomain OK  OttoPersistence OK  OttoUI OK
6d981f4  OttoDomain OK  OttoPersistence OK  OttoUI OK   (+ verify.sh, which also builds the app target)
```

**Mutation testing**, 11 mutations, tabulated under Explicit checks 10; two survive by design and one survives by omission (finding 2).

**Two independent re-measurements outside the range**, to settle finding 3: host counts and a full simulator run at `e4f4872`.

## Findings

### 1. "Logs every exit" is still false: `supplyPausedResumeDate` has two unlogged exits, in the same file, on a live UI path

- severity: **P2**
- evidence: `PROD-READINESS-3.md:421`, unchanged in this range, still says "**`SubscriptionFlowService`'s cancellation half** logs every exit - started, refused with a reason, abandoned with the day the watermark rewound to, and both verification answers with what they did."

  The cancellation half is `Packages/OttoUI/Sources/OttoServices/SubscriptionFlowService+Cancellation.swift`, and it has **four** public methods, not three. `supplyPausedResumeDate` is at `:205-217`:

  ```swift
  guard let subscription = try await subscriptions.subscription(withID: subscriptionID),
        let record = try await cancellations.openEpisode(forSubscription: subscriptionID)
  else { return }                                    // :212 — silent
  let supplied = record.supplyingResumeDate(resumeDate, for: subscription, at: now)
  if supplied != record {
      try await cancellations.save(supplied)
  }
  }                                                  // :217 — success, also silent
  ```

  Its own doc comment places it in scope: "The user supplied the resume date a deferred verification was waiting on (spec §5.4, v1.5) ... the record joins the ordinary pending watch."
  It is not dead code: `CancellationSectionView.swift:184` ("Start watching from this date") → `AppModel.swift:195` → this method, and neither intermediate layer logs.

  The consequence is the same one finding 3 was raised about: the idempotent no-op path ("a record no longer awaiting its date is left alone, so a double-tap cannot overwrite a check already rolling forward") and the missing-record path and the success path are, from outside this actor, one silence. A user who taps the button and gets no watch has no record of which of the three it was.

  The disclosure that would bound this does not: `N3-7` reads "the trial, pause and usage flows are still unlogged. F11 named cancellation and verification; **those are closed**. `confirmTrialConversion`, `pause`, `resume` and `recordUsage` change money state and record nothing" - a four-item list that does not contain `supplyPausedResumeDate`, and a sentence that asserts the opposite of what the file shows.
- why the builder missed it: the reviewer handed over a list of five exits with file:line citations, and the remediation closed the five. Nobody re-enumerated the method's own claim against the file, which is the only way this one surfaces - it is the one method in the file whose *name* does not contain "cancellation" or "verification", so a scan for the flow's vocabulary skips it. The same list-shaped closure explains why `N3-7`'s "those are closed" was written rather than checked.

### 2. All five new log statements are unguarded: deleting them leaves the suite green and lint clean

- severity: **P2**
- evidence: I deleted all five `OttoLog.flows.notice` blocks this range adds (`SubscriptionFlowService+Cancellation.swift:108`, `:126`, `:155`, `:175`, `:295`) and ran the full suite plus lint:

  ```
  ✔ Test run with 207 tests in 38 suites passed after 15.310 seconds.
  $ swiftlint --strict --quiet     # rc=0, no output
  ```

  `grep -rn "lifecyclePastCancellation\|cannotRestoreInterruptedStatus\|noEpisodeToAbandon\|noWatchedDate\|abandon refused"` across `Packages/` returns **no test file**. `BoundaryLogTests` asserts `cancellation started` and `verification answered ... chargesStopped=true`, which are the two statements that already existed at `ce66bf7`; nothing in the tree observes any of the five.

  This is the shape the ledger itself records as a defect, twice, in the file being edited: `NotificationActionLogTests.swift:7-13` says "Round 1 closed F2 by adding two `OttoLog.actions` lines and evidenced the emission with an artifact quoted in a commit message - which is a real artifact, and not a guard. `reviews/REVIEW-5.md` measured that deleting both statements left the whole suite green."
  The remediation did the same thing five more times, in the same category, one file away from the suite that would have caught it. Both the existing `BoundaryLogTests` window read and `SchedulerFixture` are already in that test target, so the marginal cost of pinning one of the five - `lifecyclePastCancellation` is reachable by starting a cancellation on an already-cancelled subscription - is a fixture and three lines, not a new query.

  The ledger does not claim a test for these. It also does not disclose their absence, and the remediation section's other four bullets each quote a falsification.
- why the builder missed it: four of the five findings being remediated were *test* defects, so the work was framed as "fix the tests"; finding 3 was the one production change, and it was closed by writing the code the reviewer asked for. The reviewer's own text framed it as a false claim rather than as a missing guard ("the finding is about the claim, which is falsifiable from the source alone"), so satisfying the claim read as satisfying the finding.

### 3. REVIEW-4 finding 8's remedy put a wrong number where a right one had been

- severity: **P3**
- evidence: the stage-2 table (`PROD-READINESS-3.md`, "Baseline at the end of STAGE 2 (`e4f4872`)") now reads:

  | measurement | at this stage |
  |---|---|
  | `scripts/verify.sh` | exit 0, 258 / 119 / 201 = **578**, "+13, exactly this run's new tests" |
  | simulator suite | **113 / 72 / 31**, "+7 since baseline; an earlier draft recorded the second bucket as 70, which `reviews-3/REVIEW-3.md` measured as 72" |

  I measured `e4f4872` directly, in the worktree:

  ```
  OttoDomain:      ✔ Test run with 256 tests in 57 suites passed
  OttoPersistence: ✔ Test run with 119 tests in 24 suites passed
  OttoUI:          ✔ Test run with 201 tests in 37 suites passed      → 576, not 578; +11, not +13

  $ xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"   # exit 0
  ✔ Test run with 113 tests in 21 suites passed after 2.770 seconds.
  ✔ Test run with 70 tests in 12 suites passed after 0.073 seconds.        → 70, not 72
  ✘ Test run with 31 tests in 6 suites passed after 2.904 seconds with 7 known issues.
  ** TEST SUCCEEDED **
  ```

  Both of my numbers match `reviews-3/REVIEW-2.md:44-47,52-54`, which measured `e4f4872` independently at 256 / 119 / 201 = 576 and 113 / 70 / 31.
  The `72` the remediation imported is `reviews-3/REVIEW-3.md:41`, measured at **`b006d20`** - a later commit, after stage 3 added two simulator tests to that bucket. So the simulator row was **correct before this range and is incorrect after it**, and the citation the ledger gives for the change does not support it at the commit the table now names.

  The verify row is wrong under either reading: 576 at `e4f4872` (measured above), 580 at `b006d20` (`REVIEW-3.md:31-34`), and the table says 578.

  REVIEW-4's finding 8 was itself built on the premise that the table was a stage-3 table; the remediation resolved the ambiguity the other way, toward stage 2, and then applied a correction that is only valid under the premise it had just rejected.
- why the builder missed it: the finding arrived as "this table is unlabelled and this number is wrong", and both halves were actioned in one edit without re-measuring either commit. The label and the number pull in opposite directions, and nothing in the ledger cross-checks a per-stage table against the review that measured that stage.

### 4. The amount tripwire is still checked against a random UUID, which is what the fix says it stopped doing

- severity: **P3**
- evidence: `BoundaryLogTests.swift:136-144` now reads

  ```swift
  for entry in lines where entry.contains(ownIdentifier) {
      #expect(!entry.contains("99999"))
  }
  ```

  and the doc comment two lines above justifies it as "The amount is checked only where this test controls the whole population: the lines carrying its own subscription's identifier."

  It does not control that population. The line carrying its own identifier is, verbatim from my mutation-K run:

  ```
  cancellation started id=00000000-0000-0000-0000-000000000091 amountCents=99999
    episode=2D2B161A-23BF-41EB-9917-EEE6EC79D155 checkDay=2026-09-06
  ```

  `episode=` is `openingCancellationEpisode(id: UUID(), …)` - a fresh random UUID on every call, and the exact interpolation that produced the P1 flake one commit earlier.
  The rate is ~1.1e-5 per run, not 25 %: a UUID string has 12 five-character windows lying entirely inside a hex run (8-4 in the first group, 12-4 in the last), each `99999` with probability 16⁻⁵, and exactly one such line falls in the filtered set per run.
  That is not an operational risk, and I am not calling the test flaky. What is falsifiable is the ledger's own summary of the fix - "the mechanism it depended on - an absolute assertion over a population containing foreign random hex - **no longer exists**" - which is true of `999` over the whole window and false of `99999` over this line.

  Second, smaller half: the needle itself narrowed from `999` to `99999`, which neither the ledger nor the source comment records. The fixture's amount is `999_99`; `99999` catches a raw-cents leak, and the surviving global `$` check catches a formatted `$999.99`, but a symbol-less `999.99` on an own-identifier line now passes where it previously failed. The ledger's closing statement counts **two** of this run's own assertions as weakened and restored; this is a third, weakened and not restored, disclosed only as a scope change.
- why the builder missed it: the fix was reasoned about entirely in terms of foreign *suites* - "a sibling cannot produce `Zzyzx`, `$` or `/` by accident" - and pinning to `ownIdentifier` does exclude every sibling. The random value that remains is produced by this test's own call into production code, so it does not look foreign, which is the same blind spot in a smaller frame.

## Explicit checks

1. **Fabricated or unreproducible findings.** The remediation section's measured numbers reproduce with one exception (finding 3). `verify.sh` 258 / 124 / 207 = 589 exact. Simulator 117 / 72 / 36 = 225 with 7 known issues exact, `** TEST SUCCEEDED **`. Non-Gregorian 1 / 1 / 5 at the same five citations exact. "12 of 12 passed, 0 failed" reproduces on my own 12 runs. "`.swiftlint.yml` is untouched by this remediation" is true - it is not in `git diff --name-only ce66bf7..6d981f4`. The two rewritten falsification rows in ITEM 6 reproduce at the expression they now quote. The corrected simulator deltas reconcile: 225 − 209 = 16, and 216 − 209 = 7 for the stage-2 row's arithmetic (though its inputs are wrong - finding 3).
2. **Citations that don't say what they're claimed to say.** Two. Finding 3 (`REVIEW-3.md`'s `72` cited for `e4f4872`, measured at `b006d20`). Finding 4 (the source comment's "controls the whole population"). `reviews-3/REVIEW-4.md` is committed into the range at `ef7e9b8` and I read it as shipped; the citations it carries into the new source comments (`finding 1`, `finding 2`, `finding 4`, `finding 5`) each point at the right finding.
3. **Severity inflation or deflation.** One deflation, finding 1: `logs every exit` is still asserted as a completed property. Nothing inflated. The ledger's self-criticism is unusually accurate - "My own four `verify.sh` runs passed, which at 25 % has probability 0.32 - a single green run is not evidence about an event of that rate, and I treated it as one" is exactly right, and the F6-signature framing of the watermark regression understates nothing.
4. **Features smuggled past the no-features rule.** None. No file under `Otto/`, no view, no localized string, no navigation, no setting. The only production changes are `OttoStore.watermarkDay` (same signature, same static, internal), and `SubscriptionFlowService+Cancellation.swift`, whose two new methods are `private`. No new public API in this range.
5. **Any SwiftData schema change.** None. `git diff --name-only ce66bf7..6d981f4` over `Packages/OttoPersistence/Sources/OttoPersistence/Schema`, `*OttoSchemaV*` and `*OttoMigrationPlan*` is empty. The one persistence source file touched is `Store/OttoStore.swift`; V3 is not lifted.
6. **Prohibited actions.** None found. Seven files changed, of which the documents are `PROD-READINESS-3.md` and the new `reviews-3/REVIEW-4.md`; no `.github/`, `docs/`, `DECISIONS.md`, `README.md`, `project.yml`, `Otto/`, `PROD-READINESS.md` / `-2.md`, `reviews/`, `reviews-2/`. `--diff-filter=DR` is empty - zero deletions, zero renames. `git diff ce66bf7..6d981f4 -- '*Package.swift'` is empty - no new dependency. `.swiftlint.yml` untouched, so no rule relaxed, disabled, re-thresholded or excluded. `git reflog` shows the three range commits as plain `commit:` entries, no `rebase`/`amend`/`reset`. No tags. `.git/FETCH_HEAD` does not exist. `refs/remotes/origin/main` is `406a5a6`, matching `BASELINE-3.md`. I made no network call and touched no device.
7. **Fixes that relocated a bug rather than removed it.** The watermark fix removes it: `min` now runs over validated `CalendarDay`s, and I probed the shapes the ledger does not claim -

   ```
   PROBE nil+valid            -> Optional(2026-06-01)
   PROBE 0+20260230+valid     -> Optional(2026-06-01)   unreadable lines = 2 (both values named)
   PROBE nil+nil              -> nil                    lines mentioning this id = 0  (absent stays silent)
   PROBE ordering (3 values)  -> Optional(2026-01-01)
   PROBE negative+valid       -> Optional(2026-06-01)
   ```

   **Both function splits are behaviour-preserving.** Stripping comments and `OttoLog` statements from `startCancellation` at `ce66bf7` and from `startCancellation`+`watchingEpisode` at `6d981f4` leaves the same statement sequence in the same order, with two substitutions: `var episode = existing` becomes `if var existing`, which is identical for a `struct` (`CancellationEpisode` is `public struct`, `Subscription` is `public struct`); and the outer `var subscription` reassignment becomes a returned tuple member the caller assigns, so `markingCancellationPending` still sees the restored value and `let url` is still read from the pre-restore subscription. `recordStillCharging` is a verbatim move of the no-path. The one non-identity is that both new methods derive `subscriptionID` from `subscription.id` rather than from the caller's parameter; I checked all six `subscription(withID:)` implementations - the store fetches by an `id` predicate and maps that record, the fake is `stored[id]` keyed by `subscription.id` on save - so the two are equal on every path. Actor isolation is preserved (same-module `private` methods on the actor's extension).
   **The splits were required, not cosmetic.** Inlining both back with the new log lines and linting that one file:

   ```
   SubscriptionFlowService+Cancellation.swift:29:12: error: Function Body Length Violation:
     ... currently spans 59 lines (function_body_length)
   SubscriptionFlowService+Cancellation.swift:197:12: error: ... currently spans 56 lines
   ```

   `.swiftlint.yml` configures no `function_body_length`, so this is SwiftLint's 50-line default promoted to an error by `--strict`; no threshold was moved to accommodate anything.
8. **Error handling that hides errors.** Nothing swallowed. The five new statements are on paths that already returned nil/void and now say why. `watermarkDay` now logs *more* than before - every unreadable row rather than the one that would have won - and the message correctly dropped "materializing from today", which is no longer true when a readable sibling row wins. The one thing this range makes noisier: the loop emits one `.error` line per unreadable row on **every** read of that subscription's watermark, and `deviceWatermark` is read per subscription per scheduling pass, so a duplicate pair of corrupt rows now writes two lines per pass rather than one. Bounded by the duplicate count and justified in the comment; recorded, not raised.
9. **Privacy audit of the five new log statements**, against `OttoLog`'s stated rule (no amount, vendor, payment method or subscription content; `.private` explicitly not sufficient). All five interpolate exactly two kinds of value: `subscriptionID.uuidString` (the opaque identifier the rule permits in the clear) and a **string literal** reason - `noSubscription`, `cannotRestoreInterruptedStatus` (twice), `lifecyclePastCancellation`, `noEpisodeToAbandon`, `noWatchedDate`. `:175`'s value is a ternary between two literals, not a computed string; `reference` itself is never interpolated. Every field is `.public`, so nothing rests on redaction. No file path, no URL, no `EvidenceNote` text, no `expectedChargeAmountCents`, no `subscription.name`. Longest line as emitted is `cancellation abandon refused reason=cannotRestoreInterruptedStatus id=<36>` at ~74 characters, far inside the ~1050-character per-entry budget round 2 measured, so nothing here can be truncated. The sixth new interpolation, `watermarkDay`'s `stored=\(value)`, is a packed calendar day - the one numeric class the rule names as permitted - and it is a column that has only ever held one.
10. **Tests that pass for the wrong reason.** I broke what each added or changed test claims to guard, and also broke the two things nothing claims.

    | test | mutation | result |
    |---|---|---|
    | `aCorruptRowDoesNotShadowAReadableOne` | `watermarkDay` reverted to `ce66bf7`'s min-then-validate | **fails**, `CorruptWatermarkTests.swift:82` |
    | | reverted to the pre-fix `rows.first?…flatMap` | passes — the pre-fix shape is order-dependent and this fixture's first row is the readable one; `duplicateRowsTakeTheMinimum` and `corruptIsLoggedAndAbsentIsNot` catch that shape instead (2 issues) |
    | `corruptIsLoggedAndAbsentIsNot` | the `watermark unreadable` statement deleted | **fails**, `lines.last { … } → nil` |
    | `aLoneUnreadableRowIsNil` | the whole read fix reverted | passes — characterisation, and the source now says so |
    | `theBoundariesRecordThemselves` | the test's own four export/import calls deleted | **fails, 2 issues** — REVIEW-4 finding 5 closed |
    | | `databaseEmpty` pinned to `true` + `subscriptions` pinned to `1` in production | **fails, 2 issues** at `:87` |
    | | `import begin` and `cancellation started` statements deleted | **fails, 2 issues** at `:87` — the rows ITEM 6 now quotes |
    | | export line leaks `name=Zzyzx Streaming url=https://…` | **fails, 2 issues** at `:138` (`Zzyzx`) and `:140` (`/`) — the split-out `assertPrivacyRule` does bite |
    | | `cancellation started` leaks `amountCents=99999` | **fails** at `:143` — the own-identifier loop does bite |
    | `aSnoozeThatScheduledNothingSaysSo` | this test's own working-rung snooze removed | **fails 3/3** at `:155` — REVIEW-4 finding 4 closed |
    | (none) | all five new `OttoLog.flows.notice` statements deleted | **207/207 passes, lint clean** — finding 2 |
    | (none) | `supplyPausedResumeDate` — no log to delete | **no statement, no test** — finding 1 |

11. **Flaky or environment-dependent tests.** None measured: 12/12 clean, and 21 further OttoUI runs across the mutations produced no unexplained failure. I checked the remaining absolute assertions by enumerating the population rather than by trusting the rate. The window is `subsystem == com.arthurzhang.otto AND (category == "transfer" OR category == "flows")`; every statement that can land in it is in `ExportService.swift` (9) or `SubscriptionFlowService+Cancellation.swift` (11), and their interpolations are UUID strings, `Int` counts, `Bool`s, enum `rawValue`s, ISO days via `OttoLog.dayText`, and `String(describing: type(of: error))`. None can contain `$` or `/`. The last of those is the only free-form one and the comment's justification ("impossible in a UUID") does not cover it, so I measured it: `pickerOutcomesAreDistinguished` - a sibling test in the same file - feeds a **function-local** `struct Unreadable: Error {}` into that interpolation, and `String(describing: type(of:))` yields `Unreadable` where `String(reflecting:)` on the same type yields `lt.(unknown context at $10f050134)…Unreadable`. The `$` assertion is safe today because of which `String` initialiser the production line uses, and nothing in the rule or the test records that dependency. Residual risk, not a finding.
12. **Anything marked resolved without an artifact.** ITEM 6 stays RESOLVED on a claim measurement contradicts (finding 1) and on five statements with no artifact at all (finding 2). ITEM 5's artifact is now complete: the mixed corrupt/readable case has a fixture, and it falsifies. The remediation section's other four bullets each carry a falsification I re-ran.
13. **Every commit in the range builds.** All three, all three packages. `6d981f4` additionally builds the app target under `verify.sh`.
14. **The baseline must not regress.** It does not, and this time it is stable rather than probabilistic: `verify.sh` exit 0 at 258 / 124 / 207 = 589, `swiftlint --strict` clean over 220 files, simulator `** TEST SUCCEEDED **` with the same 7 `EmptyStateTests` known issues in the same 36-test bucket, non-Gregorian 1 / 1 / 5 at the same five citations, and 12 of 12 clean full-suite runs where `ce66bf7` gave 9 of 12.
15. **Two cosmetic residuals in the changed test**, recorded rather than raised. `aSnoozeThatScheduledNothingSaysSo` still calls `_ = try await seedTrial(fixture.subscriptions)` and discards it; `FakeSubscriptionRepository.seed` merges rather than replaces, so index 88 is seeded and never used by this test. The two alias lines (`let trial = workingTrial`, `let subscription = working`) exist only to keep the rest of the body unchanged. Neither affects what the test proves - index 8801 and trial index 501 collide with nothing in this target, and the sibling `seedTrial`s in `AcknowledgementActionTests` and `NotificationActionTests` use index 1.

## What I could not check, and why

- **Whether `supplyPausedResumeDate`'s three outcomes are distinguishable in production by some other route.** I read the call chain to the button and confirmed neither `AppModel` nor the view logs, but I did not build a fixture that drives all three exits through a real store. The finding is about the claim and the call chain, both of which are falsifiable from source.
- **The K sweep.** `reviews-3/REVIEW-4.md` re-derived the ledger's 3 / 7 / 15 / 64 to the digit from a standalone Foundation script, and the remediation's "one correction to the reviewer" rests on that. It is outside this range and I did not re-run it; I am reporting REVIEW-4's result, not confirming it.
- **CI.** No run may be triggered and I read none. `.github/workflows/` is unchanged in this range.
- **A physical device and Release configuration.** Prohibited / not built. `BGAppRefreshTask`'s real behaviour stays CANNOT ASSESS.
- **The `OSLogStore` tests on a CI runner.** Unchanged CANNOT ASSESS. This range adds no new reader; the count stays at six in OttoUI and one in OttoPersistence.
- **Whether `reviews-3/REVIEW-4.md` as committed at `ef7e9b8` is byte-identical to what its author wrote.** It is added, not modified, in this range, and nothing after `ef7e9b8` touches it; I have no earlier copy to diff against.
- **Non-Gregorian coverage beyond three locales.** Buddhist, Japanese and Islamic-umalqura only, as the harness offers.

The worktree is removed and `git worktree list` shows only `/Users/<user>/dev/otto`.
The main working tree was never modified: at the end of this review `git status --porcelain` shows `?? reviews-3/REVIEW-5.md`, the only file this review writes.
No commit was created, no network command was run, and nothing outside this range was edited.
