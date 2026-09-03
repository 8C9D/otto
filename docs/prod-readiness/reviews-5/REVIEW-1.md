# REVIEW-1 - round 5, stage 1, item 1 (N4-7 + N4-3), range `d7cbd37..c26b2a7`

Reviewed head `c26b2a7dc5bd825fddf722917aa0546d737e6b45`, branch `prod-readiness-5/2026-08-15`.
The range contains two commits: `eb4d2ae` (code, six files) and `c26b2a7` (ledger only; `git diff eb4d2ae c26b2a7 --name-only` is exactly `PROD-READINESS-5.md`).
At review time the working tree matched the head: `git status --porcelain` empty, `HEAD == c26b2a7`, before this file was added.
All mutation and probe work was done in one detached worktree at `c26b2a7` under my own scratchpad; it was `git status --porcelain` clean before removal, and `git worktree list` now shows only the main tree.

verdict: REJECT

## Summary

**The headline defect is genuinely fixed, and I could not put two passes inside the scheduler through the shipped gate.**
The serialisation is structural: across eight scoped simulator runs and one full run of the shipped `threeEntryPointsSerialise` test, `peak == 1` held on every one of 480+ iterations, and my own caller-during-the-follow-up probe measured 0 of 60 overlaps three times over.
The pre-fix defect reproduces through the real entry points at this head with the gate removed (11 of 180 background, 25 of 180 store on my host), the four consumers are correctly enumerated and all four receive the one gated instance, two of the four recorded falsifications reproduce to the digit, the coordinator's nine prior tests are byte-identical, no test was modified or weakened, the `OSLogStore` reader count is still ten, and four of the five baseline dimensions reproduce exactly (verify.sh 261/127/217 = 605 exit 0, lint clean over 228 files, non-Gregorian 1/1/5 with the same citations, seven clean full host runs).

It is rejected for two things, both of them inside the expiration-and-cancellation territory that was this item's own named open question.

**First, the shipped gate has a real defect: an uncancelled caller can be answered with `CancellationError` and no pass ever runs for its trigger.**
`waiterCancelled` cancels an abandoned follow-up's task but never clears the `queued` slot, and `join` checks only that a queued task exists, not whether it is already cancelled.
So from the moment a background expiration abandons its queued follow-up until the in-flight pass finishes - a window as long as a full scheduling pass - every new caller joins the corpse and inherits its `CancellationError`.
Measured deterministically, four runs of four: the caller gets no outcome, `spy.passes` stays 1, and the gate even logs `pass coalesced into queued pass` for a join onto a dead pass.
In production that is a store write or a snooze whose scheduling pass silently never happens, plus `apply(nil)` putting Today into the failed-pass state, and it directly falsifies the ledger's coalescing sentence: "every one of them is answered by that follow-up, a pass that starts after their calls".

**Second, the stage shipped a flaky test, and the simulator suite - this stage's principal verification surface - now fails about 40 % of the time on the project's own host and simulator.**
`expirationSparesTheForegroundPass` asserts the order of two publishes (`published.first` is the foreground outcome, `published.last` is nil) that the code does not order: both continuations are resumed by the same pass completion and the scheduler picks.
It failed 7 of 18 suite-scoped simulator runs and my single full-suite run at the head (`** TEST FAILED **`, 9 issues including the 7 known), while passing 10 of 10 when run alone, so the stage's three green runs and the recorded `TEST SUCCEEDED` at the head are samples of a coin flip, not verification.
The ledger states the same unenforced ordering as measured fact ("the foreground pass completes uncancelled and publishes its outcome ... The background path then publishes nil").
The simulator-suite dimension is therefore worse than baseline (`BASELINE-5.md`: `TEST SUCCEEDED`, 119/72/53), which is the regression the standing rules exist to catch.

Both fixes are small and the rest of the stage is strong; the reject is for shipping them inside the one semantic area the item existed to settle, with ledger sentences that state the broken behaviours as verified.

## What I ran

All measurements at `c26b2a7`.
Host: macOS 15.6.1 (Darwin 24.6.0), arm64, Xcode 26.3, SwiftLint 0.65.0, simulator `<simulator-udid>`.

### The five baseline dimensions, re-measured at the head

| dimension | `reviews-5/BASELINE-5.md` at `1b352f4` | measured here at `c26b2a7` | result |
|---|---|---|---|
| `./scripts/verify.sh` | exit 0; 261/127/209 = 597 | **exit 0**; OttoDomain **261**, OttoPersistence **127**, OttoUI **217**, total **605** | +8, matches the ledger's 209 -> 217 |
| `swiftlint --strict` | 0 violations, 225 files | **0 violations, 0 serious in 228 files** | clean; +3 files are the range's three new files |
| simulator suite, from `Packages/OttoUI/` | 119/72/53, 7 known issues, `TEST SUCCEEDED` | **127 / 72 / 56** but `** TEST FAILED **`, **9 issues (including 7 known issues)** on my one full run | **worse than baseline** - finding 2 |
| non-Gregorian harness | 1 / 1 / 5 | **1 / 1 / 5**, same citations | exact |
| flake, full host `swift test --package-path Packages/OttoUI` | 12 of 12 | **7 of 7 clean** (six in the main tree, one in the worktree), 217 tests each | clean on the host; the flake is simulator-side |

The two extra issues in the failed simulator run are `SchedulingGateIntegrationTests.swift:188` and `:190`, the ordering assertions of finding 2; all behavioural assertions in the same test held.

### The stage's stochastic claims, re-run rather than accepted

| claim | ledger | measured here |
|---|---|---|
| pre-fix overlap, background vs foreground, real entry points, simulator | 22/18/22 of 60 = 62 of 180 | **5, 2, 4 of 60 = 11 of 180** (bare-seam probe at the head; the coordinator and store differ from `d7cbd37` only in comments, verified by diff) |
| pre-fix overlap, store vs foreground | 15/8/16 of 60 = 39 of 180 | **5, 8, 12 of 60 = 25 of 180** |
| post-fix overlap through the gate | 0 of 180, `peak == 1` per iteration | **0 overlaps in 480+ iterations** across eight scoped runs and one full run; the `peak == 1` assertion never fired |
| `expirationSparesTheForegroundPass` is a deterministic pin | implied by "each half pinned by a simulator test" | **fails 7 of 18 suite-scoped runs** (1 of 3, 2 of 5, 4 of 10), **passes 10 of 10 alone**, failed my one full-suite run |

The pre-fix rates are lower on my host than the stage's but the defect reproduces on both shapes in every run; rates of this quantity are executor-dependent (round 4 measured 45 of 240, then 74 of 180, for the same shape) and the ledger does not lean on the rate, so the difference is recorded here and not raised as a finding.

### Falsifications - the stage's four, reproduced

Each mutation was applied by a script that asserted the target text's occurrence count was 1 before writing, in my worktree, and restored from a saved pristine copy verified with `cmp`.

| # | what was broken | ledger says | I measured (full 217-test host suite) |
|---|---|---|---|
| M1 | serialisation barrier removed (`_ = try? await predecessor.value` deleted) | 4 tests fail, 71 issues | **5 tests fail on every one of five runs**; issues 72, 73, 73, 73, 73 |
| M2 | joiners handed the in-flight pass instead of a follow-up | 2 tests fail, 15 issues - freshness breaks | **4 tests fail, 17 issues**, three times over, with my nearest formulation (the mutant's text is recorded nowhere); the freshness test is among them with 7 issues |
| M3 | refcount inverted to cancel on the first waiter | 1 test fails | **1 test fails, 1 issue**, three times over - exact |
| M4 | queued slot never cleared after promotion | survived, then caught with 2 issues | **caught: 2 issues at `CoalescingReminderSchedulerTests.swift:170` and `:171`**, three times over - exact |

### Falsifications - my own, beyond the four

| # | what I did | result |
|---|---|---|
| Probe A | uncancelled caller joins after a queued follow-up is abandoned but before the in-flight pass finishes | **the caller gets `CancellationError`, no pass runs for it (`passes` stays 1)** - deterministic, 4 of 4 runs - finding 1 |
| M5 | `queued.arguments = arguments` deleted (the "most recent joiner's arguments" semantic) | **survives: 217 host tests green, 3 of 3 runs**; every test in both new files passes one fixed argument set, so no test can notice - finding 4 |
| M6 | `inFlight = pass` deleted from the promotion in `execute` | **survives the host suite 3 of 3**; my probe shows it breaks serialisation in **58 of 60** iterations (caller during the follow-up pass); the simulator's serialisation test catches it in only **2 of 3** runs - finding 5 |
| Probe B | caller arriving during the follow-up pass, against the pristine gate | **0 of 60 overlaps, three times over** - the shipped code handles the window M6 breaks; the suite just does not guard it |

### Claims verified by enumeration

- **Four consumers**: `NotificationCoordinator.swift:212` (`rescheduleSoon` chain) and `:253` (`handleBackgroundRefresh`), `NotificationStatusStore.swift:45`, and `NotificationActionHandler.swift:131`, `:137`, `:145`, `:154`, `:160` - five `.notificationAction` sites, as the ledger says; no other production call site of `reschedule` on the seam exists.
- **One wrap**: `OttoApp.swift:44` is the only production construction of either `CoalescingReminderScheduler` or `NotificationScheduler`, and the one instance reaches the store, the coordinator and the action handler; "wrapped ONCE" is enforced by a comment and the single call site, not structurally.
- **No test modified**: `git diff d7cbd37..c26b2a7 -- '*Tests*'` is exactly the two new files; `NotificationCoordinatorTests.swift` is byte-identical and still holds nine tests.
- **Test counts**: 8 `@Test` in `CoalescingReminderSchedulerTests.swift`, 3 in `SchedulingGateIntegrationTests.swift`; host 209 -> 217 and simulator 53 -> 56 both check out.
- **`OSLogStore`**: ten reads, enumerated by the four helper call sites exactly as `BASELINE-5.md` counts them; neither new file adds one.
- **Round-4 figures quoted in the ledger** (45/240, 33/240, 74/180): all three match `PROD-READINESS-4.md:404`, `:672`, `:702`.

## Findings

### 1 - P2. An uncancelled caller can be answered with `CancellationError` and no pass, and the ledger's coalescing sentence is false in that window

**Evidence.**
`CoalescingReminderScheduler.swift:140-144`: `waiterCancelled` cancels the abandoned follow-up's task but never clears `queued`.
`:85-91`: `join` hands any new caller the queued pass whenever `queued.task` exists, without checking `isCancelled`, increments its waiters, and logs `pass coalesced into queued pass`.
The corpse leaves the slot only when the in-flight pass finishes and the dead task's `execute` promotes itself and throws at `try Task.checkCancellation()` (`:123-131`), so the window is the whole remainder of the in-flight pass.
Probe A drives exactly this: pass 1 held in flight, caller 2 queued then cancelled (`probeQueuedTaskIsCancelled` observed true), caller 3 arrives uncancelled.
Result, deterministic on four runs of four: caller 3 throws `CancellationError`, `spy.passes` stays **1**, and no pass ever runs for caller 3's trigger.

`PROD-READINESS-5.md:150` states: "Callers arriving while a pass runs share ONE follow-up, and **every one of them is answered by that follow-up, a pass that starts after their calls**".
Caller 3 arrived while a pass was running and was answered by nothing.
`:153`'s "an abandoned follow-up whose waiters all cancelled never runs at all" is true and is precisely the mechanism that starves the later joiner.

**Production shape.** A pass is in flight (foreground open, store write or snooze), a background wake-up queues behind it, the `BGAppRefreshTask` expires and abandons the follow-up - the exact scenario `expirationSparesTheForegroundPass` ships - and then the user edits a subscription or snoozes again before the in-flight pass completes.
That caller's `NotificationStatusStore.reschedule()` lands in the `catch` arm and `apply(nil)` sets `lastPassFailed` (`NotificationStatusStore.swift:48-60`), so Today withdraws the coverage sentence for a healthy engine, and the reschedule the edit needed never happens until some later trigger.
A real scheduling pass takes long enough for this window to matter, and nothing logs the starvation - the gate logs a coalesce into a pass that will never run.

**What would make it right.** Clear the slot when abandoning it (`if pass === queued { queued = nil }` before `pass.task?.cancel()` in `waiterCancelled`), or have `join` refuse a queued pass whose task `isCancelled` and start a fresh follow-up; then a test in the shape of probe A, which currently fails and would pin the repair.

### 2 - P2. `expirationSparesTheForegroundPass` pins a publish order the code does not enforce, the simulator suite now fails ~40 % of runs, and the ledger asserts the same unenforced order as fact

**Evidence.**
`SchedulingGateIntegrationTests.swift:188-190` asserts `published.first??.scheduledCount == 1` and `published.last == nil`.
Both publishes are continuations resumed by the completion of the same foreground pass: the foreground's `runPass` resumes and calls `onOutcome(outcome)`, and the background's cancelled `work` resumes from `predecessor.value` inside the abandoned follow-up's task, gets its `CancellationError`, and calls `onOutcome(nil)` - and nothing orders the two resumptions.
Measured at the pristine head on the project's own simulator: **7 failures in 18 suite-scoped runs** (batches of 3, 5 and 10), **0 failures in 10 single-test runs** (the race needs sibling-suite contention, which is exactly how `verify` and CI run it), and **my one full simulator-suite run failed** - `✘ Test run with 56 tests in 10 suites failed after 3.013 seconds with 9 issues (including 7 known issues)`, `** TEST FAILED **`.
Every failure is the same two assertions inverted (`published.first` nil, `published.last` the outcome); `spy.passes == 1`, `cancelledPasses == 0`, `published.count == 2` and `completions == [false]` held in every failing run, so the behaviour the test exists to pin is right and only the asserted ordering is fiction.

`PROD-READINESS-5.md:160-161` states the ordering as the measured answer to the item's named open question: "the foreground pass completes uncancelled and publishes its outcome ... The background path **then** publishes nil for its own cancelled pass ... and is asserted rather than hidden".
The "then" is unenforced, the assertion of it is a coin flip, and the stage-head `TEST SUCCEEDED` this stage records was one sample of that flip (my measured pass rate makes three consecutive green suite runs roughly a one-in-four event).
The baseline dimension "simulator suite exit 0, `TEST SUCCEEDED`" is therefore worse than at `1b352f4`, and the project's own round-4 history (REVIEW-3 finding 1) is exactly about concluding order or rate from single runs of a scheduled race.

Secondary consequence, worth one sentence in the ledger when fixed: because the order races, the store's final published state after this scenario is also a coin flip between "coverage outcome" and "failed pass, coverage withdrawn" in production - not new to this stage, but the sentence claiming a fixed order should not survive.

**What would make it right.** Assert order-insensitively (count, membership, and that the background's own returned pass reported nil), or enforce the order if it is wanted, and rewrite `PROD-READINESS-5.md:160-161` to say the two publishes are unordered; then re-run the suite enough times to state a flake figure rather than a `TEST SUCCEEDED`.

### 3 - P3. The mutation table's counts are single-run samples again, one is wrong on every run I made, and the mutants' text is unrecorded

**Evidence.**
`PROD-READINESS-5.md:173` records the barrier-removal mutant as "**4 tests fail, 71 issues**".
Five full host runs of that mutant here: **5 tests fail on every run** (the recorded four plus `aFailedPassDoesNotPoisonTheFollowUp`), issues 72/73/73/73/73 - never 4, never 71.
`:174`'s "2 tests fail, 15 issues" for the in-flight-join mutant is not reproducible as stated either - my nearest formulation fails 4 tests with 17 issues, three times over - and unlike round 4's stage 3, the exact text of what was broken is recorded nowhere, so nobody can distinguish a different mutant from a wrong count.
M3 and M4 reproduce exactly (1 test/1 issue; 2 issues at the freshness assertion), so the table is half right, and every mutant is genuinely caught - the defect is in the record's precision, not the guard.
This is the pattern `reviews-4/REVIEW-3.md` finding 3 and `PROD-READINESS-4.md:703`'s lesson entry exist to stop: a stochastic quantity measured once and written as the property.

**What would make it right.** Record each mutant's exact text, re-run each at least three times, and record the stable part (which tests fail) separately from the sample part (issue counts).

### 4 - P3. The "most recent joiner's arguments" semantic is claimed, implemented, and untestable by every shipped test

**Evidence.**
`PROD-READINESS-5.md:151`: "The follow-up runs with the most recent joiner's arguments, the way the coordinator's `queued` trigger always overwrote."
Deleting the implementing line (`CoalescingReminderScheduler.swift:88`) leaves all 217 host tests green three times over, and the three simulator tests cannot catch it either: every caller in both new files passes the same fixture `now`/`today`/`timeZone`, so no assertion can distinguish first-joiner from last-joiner arguments.
The ledger's framing - the gate's semantics "each with a test named for it" - is one semantic short.

**What would make it right.** One host test where joiners pass distinguishable arguments and the spy records which set the follow-up ran with.

### 5 - P3. The serialisation guarantee is unguarded in the caller-during-the-follow-up window: a mutant that overlaps 58 of 60 iterations survives the host suite

**Evidence.**
Deleting `inFlight = pass` from the promotion (`CoalescingReminderScheduler.swift:125`) makes any caller arriving while the follow-up pass runs start a fresh concurrent pass - my probe measures overlap in **58 of 60** iterations - yet all 217 host tests stay green on three runs, because no shipped test sends a caller during the follow-up (the deterministic tests release all passes together, and `gateSerialises` uses only two callers).
The simulator's `threeEntryPointsSerialise` caught this mutant in 2 of 3 runs and missed it in the third, so the guard on the stage's central property is probabilistic where it exists at all.
The shipped code is correct in this window (probe B: 0 of 60, three times), so this is a coverage gap, not a defect.

**What would make it right.** A host test in probe B's shape: hold pass 1, queue a follow-up, wait for the follow-up to start, send a third caller, assert `peak == 1` and that the third caller got its own later pass.

### 6 - P3, process. Three round-opening commits sit outside every review range

**Evidence.**
The standing rule (`PROD-READINESS-5.md:204`) is that no commit may fall outside every review range and every range's START is the previous range's HEAD.
Round 4's terminal head is `9e73378`; this stage's range starts at `d7cbd37`; the merge `1b352f4` and the two round-opening commits `756b8b1` and `d7cbd37` are so far inside no stated range.
`BASELINE-5.md` verifies the merge added nothing beyond `.github/workflows/ci.yml` and mentions a merge review, but no review document in `reviews-5/` covers these commits by range.
Recorded so the round closes the gap explicitly rather than rediscovering it as it did with `aa92ca7`.

## Explicit checks

- **Fabricated or unreproducible findings.** The four-consumer enumeration, the round-4 quotations, the test-count deltas, and mutants M3/M4 all reproduce exactly. The pre-fix rates reproduce as a defect but not as a rate (11 and 25 of 180 here versus 62 and 39). M1's "4 tests, 71 issues" does not reproduce (finding 3). The `TEST SUCCEEDED` at the head reproduces only 6 times in 10 (finding 2).
- **Tests that cannot fail, or pass for the wrong reason.** None of the shipped assertions is tautological, and M1-M4 prove the suite bites. The inverse problem is present instead: one test fails for the wrong reason (finding 2), and two claimed semantics have no test that could fail (findings 4 and 5).
- **Actor-reentrancy hazards in the new actor.** `join` is synchronous on the actor, so no window exists between its checks and its writes; `execute` clears `queued` before its first suspension, so late joiners cannot miss argument freshness; a new caller landing between the predecessor finishing and the follow-up's `execute` hop joins the still-queued follow-up, which is correct; the promotion window is guarded by `pass === queued`. The one state-machine hole I found across suspension points is finding 1. Reentrancy of the gate from inside a pass would deadlock the chain, but no production path re-enters: `onOutcome` is synchronous and the action handler is never called from inside a pass.
- **Cancellation accounting.** A waiter cancelled after its pass finished is counted and ignored (the `!pass.finished` guard), a promoted follow-up keeps its waiters, and I could not make the refcount leak on the cancelled-then-completed path; the counting defect is the uncleared slot, finding 1.
- **The expiration answer, both halves.** The cancels-nothing-the-foreground-needs half is behaviourally true in every run including the failing ones; the still-cancels-a-background-only-pass half (`expirationCancelsABackgroundOwnedPass`) passed every run I made.
- **No feature, no schema, no config.** The range touches nothing under `OttoPersistence`, no `.swiftlint.yml`, no workflow; the one `Package.swift` line adds an existing internal target to a test target's dependencies, as disclosed. No user-facing copy changed.
- **Tests weakened.** None; the test diff is two new files, and the coordinator's nine tests are byte-identical at the head.
- **Log surface claims.** Both new notice lines exist at `join`'s two branches; the trigger-tagged wrapper still brackets every caller; the shared-pass bracketing caveat in the ledger is accurate. Finding 1 adds one inaccuracy: the coalesce line can name a pass that will never run.
- **Every commit in the range builds.** `eb4d2ae` plus a docs-only commit; verify.sh at the head builds and tests all three packages from a clean clone, exit 0.
- **The wrap-once claim.** True today by the single construction site; nothing structural prevents a second wrap, and the comment is the only guard - acceptable, recorded.

## What I could not check, and why

- **The stage's own pre-fix simulator numbers at `d7cbd37`.** I measured the same shapes at the head over a bare seam (comment-only diffs to the classes involved) rather than checking out `d7cbd37`; the defect reproduces, the rates differ, and neither rate is load-bearing.
- **Whether interleaved passes corrupt notification state.** Same position as `reviews-4/REVIEW-3.md`: overlap is proven and now prevented; harm from overlap was never established and is moot if the gate holds.
- **Release configuration, physical device, real `BGAppRefreshTask` expiration.** Debug, simulator, fake task protocol only, as in every prior round.
- **CI-runner behaviour of the ten `OSLogStore` readers.** Unchanged risk, still CANNOT ASSESS on this host.
