# PROD-READINESS-5 - Otto, round 5

Bounded remediation of a frozen list, opened 2026-08-15, branch `prod-readiness-5/2026-08-15`, from commit `1b352f4` on `main`.

Baseline artifact: `reviews-5/BASELINE-5.md`.
Review trail: `reviews-5/`.

This is the first round to start from `main`.
The round-1 through round-4 stack was merged at `1b352f4` (parents `cd9778c` and `9e73378`); the merge is local and unpushed at opening.

**This is not a discovery sweep.**
Every item below was found, evidenced and adversarially reviewed in the four runs that produced `PROD-READINESS.md` through `PROD-READINESS-4.md` and their review trails.
This round's job is to close the P2 list that round 4 carried, honestly, and to say plainly what it cannot close.
No prior record is edited by this run.

Rounds 1 through 4's terminal states and scope constraints still bind.

---

## Baseline

`scripts/verify.sh` at `1b352f4`, from a clean clone: **exit 0 - OttoDomain 261, OttoPersistence 127, OttoUI 209, total 597**, `swiftlint --strict` clean over 225 files.
Simulator suite from `Packages/OttoUI/`: exit 0, `** TEST SUCCEEDED **`, **119 / 72 / 53, 7 known issues**.
Non-Gregorian harness: **1 / 1 / 5** under `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura`, the same five citations as every prior baseline.
Flake batch: **12 of 12 clean full `swift test --package-path Packages/OttoUI` runs.**

All five round-4 terminal figures reproduce exactly.
Full output, provenance and the environment table are in `reviews-5/BASELINE-5.md`.

**The `OSLogStore` reader count at this HEAD is ten** - seven in OttoUI, three in OttoPersistence, enumerated by call site in the baseline.
The standing rule is applied to the real number: **do not add an eleventh**.
The CI-runner delivery risk stays in CANNOT ASSESS.

---

## THE WORK LIST - frozen at opening

Every P2 carried open in `PROD-READINESS-4.md`'s NEXT ROUND section, and nothing else.
All P3s stay in NEXT ROUND.
Item 1 leads because N4-7 is the highest-value code fix on the carried list, and N4-3's own entry routes its fix through N4-7's.

| # | id | what | terminal state |
|---|---|---|---|
| 1 | **N4-7 + N4-3** | The reschedule coalescing gate is in the wrong class, and the background pass is outside it | **RESOLVED pending review** - stage 1 |
| 2 | **N4-2** | Negative-offset corrupt calendars still schedule reminders on wrong days, and no round has decided whether they should | open |
| 3 | **N2-4** (reopened) | The reconcile failure list still truncates at the per-entry budget; round 2's closure was false | open |
| 4 | **N4-16** | `lastUsedDate` has no repair on a paused, trial or cancelled subscription | open |
| 5 | **N4-1** | The export button's action is verified by nothing | open |
| 6 | **N4-10** | The §6.2 reconcile diff line has no executable guard | open |
| 7 | **N4-11** | A sibling's canary masks a deleted canary wherever tests share a log window | open |
| 8 | **N2-1** | Five locale-sensitive test citations fail under non-Gregorian hosts | open |
| 9 | **N3-5** | The gap card's copy is false for the implausible-days case, now including Indian/Saka | open |
| 10 | **N3-6b** | `NotificationCoordinator.start()` and the delegate have no test | open |

Terminal states are **RESOLVED** (with artifact evidence), **DEFERRED** (with reason), or **REJECTED TWICE** (reverted, objection recorded).
There are no others.

### Item 1 - N4-7 + N4-3: the reschedule gate is in the wrong class

Three callers share one `NotificationScheduler`: the coordinator's `rescheduleSoon` (gated by round 4's item 4), `handleBackgroundRefresh` (not gated), and `NotificationStatusStore.reschedule()` (not gated, and the most frequent in ordinary use).
Measured overlap with a coordinator pass: **45 of 240** iterations for the background path and **33 of 240** for the store path (`reviews-4/REVIEW-3.md`), re-measured at **74 of 180** for the background path with a spy modelling the real pass's suspension points.
`handleBackgroundRefresh` owns the completion latch and the expiration race and builds its own `Task`, so a background wake-up landing during a foreground pass runs a second, interleaved pass - F10 itself, still live on two of three entry points.
Closing this means putting the gate at the `ReminderScheduling` seam all three callers share, and it needs its own measurement of what `expirationHandler` then cancels.

### Item 2 - N4-2: wrong-day reminders from negative-offset corrupt calendars

Round 3's "closed for 11 of 13" was measured on Buddhist, the one calendar where the stored year is ahead and nothing is scheduled.
For every negative-offset calendar the planner still produces rungs from the corrupt anchor: Japanese, Minguo, Islamic and Persian each schedule **4 reminders on the wrong days** (measured at round 3's HEAD), and round 4 added Indian to that set.
The state closed for those calendars is "wrong reminders, disclosed", not "no reminders".
Whether to stop scheduling from an implausible anchor is a decision no round has taken; this round must take it or defer it explicitly.

### Item 3 - N2-4, reopened: the failure list still truncates

Round 2 recorded this fixed by giving the failure list its own log entry.
`reviews-4/REVIEW-AA92CA7.md` finding 1 measured the closure false: the entry sits under the same ~1024-byte per-entry budget, buying only the ~200 bytes of prefix.
The list still truncates from six subscriptions upward and names **16 of 64** failed rungs at the device ceiling, measured at `aa92ca7` and at round 4's tip.
The false closure propagated into `PROD-READINESS-3.md`; the propagation is recorded in round 4 and is not re-litigated here.

### Item 4 - N4-16: no `lastUsedDate` repair off the active state

The only control that writes `lastUsedDate`, "I used this today", is inside `if subscription.effectiveStatus(asOf:) == .active` (`PauseFlowView.swift:163` at round 4's tip).
A corrupt `lastUsedDate` on a paused, trial or cancelled subscription therefore cannot be repaired without first changing the subscription's status, which is a data change the user did not want to make.
`docs/next-wave.md` says so; the app offers nothing.

### Item 5 - N4-1: the export button's action is verified by nothing

Deleting the sole call from the Settings export button's tap to `AppModel.requestExport(_:)` leaves the whole simulator suite green.
Round 4's remediation shrank the untested surface to one closure with no logic in it and moved the state machine onto the model, where eight tests reach it - but the closure itself is unreachable by any test this project can run.
Closing it needs a UI-test target, which round 4 was not permitted to add; this round must either add that target deliberately or defer with the dependency named.

### Item 6 - N4-10: the reconcile diff line has no executable guard

Deleting the §6.2 reconcile diff log statement is green at `aa92ca7` (196/196) and still green at round 4's tip (209/209); the same deletion at `aa92ca7`'s parent fails.
The file split in `aa92ca7` is what removed the guard, and no reviewer saw that commit's diff for three rounds (`reviews-4/REVIEW-AA92CA7.md` finding 2).

### Item 7 - N4-11: a sibling's canary masks a deleted canary

`requireDelivered` answers "did the subsystem deliver for this process", which a sibling test's canary answers correctly - so the guard is sound and the **falsification** of it is what breaks wherever tests share a log window.
Found twice independently in round 4, in commits three rounds apart.
Every canary falsification in this tree needs `--filter` or a suppressed subsystem, and none of the canary sites says so.
The general form is recorded in round 4: this tree has no way to prove a log line came from a particular test, only to make collision unlikely.

### Item 8 - N2-1: the five locale-sensitive citations

`DisplayFormattingTests.swift:49`, `:59`, `:68`, `:69` and `NotificationReconciliationTests.swift:170` fail under the harness locales - `:49` on any non-Gregorian host, `:170` where the month disagrees, and the three numbering-system cases under `ar_SA` alone.
Unmoved at every baseline since round 2, including this one.

### Item 9 - N3-5: the gap card's copy is false for the implausible-days case

The card's copy does not survive the implausible-days case, and round 4's Indian/Saka detection widened the set of subscriptions the false copy covers.
Re-wording it is new user-facing copy; round 4's user-facing exception was granted for the export item only, so the item stayed open.

### Item 10 - N3-6b: `start()` and the delegate have no test

`BGTaskScheduler.register`, `UNUserNotificationCenter.current()`, `UNNotification` and `UNNotificationResponse` still have no test-safe construction, so `NotificationCoordinator.start()` and the delegate methods remain untested (round 4 added four simulator-hosted coordinator tests around them; the entry points themselves are still unreached).

---

## ITEM 1 - N4-7 + N4-3, the gate moves to the seam

**RESOLVED pending review**, stage 1.
The adversarial review of this stage's range has not happened yet; nothing in this section is final until it has.

### Reconfirmed at the stage start by executing the defect

Round 4's overlap measurement, re-run at `d7cbd37` through the real entry points on the simulator, with the six-suspension spy `PROD-READINESS-4.md` ITEM 4 describes, three runs of sixty iterations each:

```
background vs foreground   22 / 18 / 22 of 60   = 62 of 180
store vs foreground        15 /  8 / 16 of 60   = 39 of 180
```

Round 4 measured 74 of 180 and 33 of 240 for the same two shapes.
The defect executes: two full scheduling passes inside the scheduler at once, from entry points the coordinator's F10 gate never sees.

### The caller count in the ledger was wrong, and the corrected figure is here

Item 1's own description says three callers share the scheduler.
Measured by enumerating the call sites of `reschedule` on `any ReminderScheduling`: **four consumers** - the coordinator's `rescheduleSoon` chain, its `handleBackgroundRefresh`, `NotificationStatusStore.reschedule()`, and **`NotificationActionHandler`**, which round 4's entries never counted and which calls the scheduler directly at five `.notificationAction` sites (snoozes and action-button state work).
The composition root hands all four the same instance, so the seam fix below covers the fourth at no extra cost - but the record should say four, and now does.

### What changed

`CoalescingReminderScheduler`, a new actor in OttoServices, wraps any `ReminderScheduling` and is what the composition root now builds: the store, the coordinator and the action handler all receive the one gated instance, and the wrap happens exactly once (`OttoApp.swift` says so at the wrap site).
The coordinator's F10 gate is untouched above it and its nine tests are green unmodified; a coordinator built over a bare scheduler, as the spy tests build it, still has only its own gate.

The gate's semantics, each with a test named for it:

- **Serialised.** A pass starts only after the pass before it has finished - the follow-up's task awaits its predecessor before touching the base scheduler - so overlap is inexpressible rather than unlikely.
- **Coalesced with a freshness guarantee.** Callers arriving while a pass runs share ONE follow-up, and every one of them is answered by that follow-up, a pass that starts after their calls - so the outcome a store write publishes describes a pass that read the store at or after the write.
  The follow-up runs with the most recent joiner's arguments, the way the coordinator's `queued` trigger always overwrote; the staleness bound is the remainder of the in-flight pass.
  An abandoned follow-up vacates its slot when it is cancelled, so a caller arriving in the remainder of the in-flight pass starts a fresh follow-up rather than inheriting the corpse's `CancellationError` - the window in which the first sentence of this bullet was FALSE at `c26b2a7`, found by `reviews-5/REVIEW-1.md` finding 1 and closed in the remediation below.
- **Cancellation is counted, not forwarded.** A caller's cancellation cancels the underlying pass only when every caller waiting on that pass has been cancelled.
  A cancelled caller whose pass survives keeps waiting and returns the shared outcome; an abandoned follow-up whose waiters all cancelled never runs at all.

### The expiration question, answered by measurement

The open design question the round-4 ledger attached to this fix - what does `expirationHandler` cancel once the background path routes through the gate - has this answer, each half pinned by a simulator test:

- **Expiring the background task while the foreground owns the running pass cancels nothing the foreground is counting on.**
  The background's queued follow-up - a pass only it is waiting on - is abandoned unrun, the foreground pass completes uncancelled and publishes its outcome, and the `BGAppRefreshTask` is completed exactly once, unsuccessfully, by the latch.
  The background path publishes nil for its own cancelled pass - R4-2's failed-pass rule unchanged - and the two publishes are **unordered**: both continuations are resumed by the same pass completion and nothing orders them, so the store's final published state after this scenario is a coin flip between the coverage outcome and the failed-pass state, in the test and in production alike.
  An earlier version of this paragraph stated the foreground-then-background order as fact and the test asserted it; `reviews-5/REVIEW-1.md` finding 2 measured that assertion failing 7 of 18 suite-scoped simulator runs, and both the sentence and the assertion now state the membership - two publishes, one the foreground's outcome and one nil - which is what the code guarantees.
- **A pass only the background wake-up is waiting on is still the expiration's to cancel** - the round-4 behaviour the gate must not lose.
  The base scheduler observes the cancellation, the task completes once as a failure, and the gate reopens for the next caller.

### Measured after the fix

The same three-entry-point shape - foreground, background refresh and a store write fired together - through one gate, three runs of sixty iterations: **0 of 180**, asserted per iteration rather than summed, because under the gate `peak == 1` is structural.

### Falsified four ways, and one of them survived first

The table that stood here recorded single-run issue counts, one wrong on every reviewer run, and no mutant text (`reviews-5/REVIEW-1.md` finding 3).
The remediation's seven-mutant battery - exact diffs, three full host runs each - replaces it below.
The story the original told remains true and is worth keeping: the promotion-keeps-queued mutant survived the suite as first shipped, answering every caller after a coalesced episode with the stale follow-up outcome forever, and the assertion added to catch it is recorded in the test's own comment.

### The log surface, stated against N4-8

The gate emits two new `scheduling` notice lines - `pass deferred behind in-flight pass` and `pass coalesced into queued pass` - so a coalescing decision at the seam is visible where the coordinator's own gate leaves none.
The per-caller `pass begin` / `pass end` lines from the trigger-tagged wrapper still surround every call, which means a begin/end pair can now bracket a SHARED pass: two callers' pairs may describe one execution of the scheduler, distinguishable by the gate's own lines between them.
N4-8 itself - the coordinator's gate swallowing coalesced triggers' lines - is neither fixed nor worsened here.

### Cost and surface, stated as the standing rules require

- Eleven host tests (eight at `c26b2a7`, three added by the remediation) and three simulator-hosted integration tests; **no `OSLogStore` reader added** - the count stays ten.
- The gate exposes three internal test probes read through `@testable` (the R4-2 precedent), so the deterministic tests await a state instead of sleeping; production reads none of them.
  A fourth probe watched the abandoned corpse's cancelled task, a mechanism the finding-1 fix removed, and was deleted with it.
- `OttoUITests` now declares the `OttoStores` dependency it uses; no new package, product or external dependency.
- Host suite 209 -> 220; simulator OttoUITests 53 -> 56; the coordinator's nine R4-2/F10 tests run byte-identical.
  Two of this stage's own new tests changed in the remediation: their synchronisation probes watched the corpse mechanism and now watch the vacated slot, every behavioural assertion in both is unchanged, and the ordering assertions finding 2 rejected are replaced by membership assertions.

### What this deliberately does not do

- It does not route `handleBackgroundRefresh` through `rescheduleSoon`: the background path keeps the completion latch and the expiration race it owns, and gains serialisation from the seam below instead.
- It does not change `NotificationScheduler` internals, the R4-2 nil-publish rule, or the coordinator's trigger coalescing.
- It does not touch N4-8, and it leaves the store path's `.stateChange` trigger tagging exactly where it was.

### Remediation after `reviews-5/REVIEW-1.md` (REJECT)

Verdict **REJECT** - a real starvation defect in the gate and a flaky ordering assertion, both inside the expiration-and-cancellation territory this item existed to settle.
First REJECT cycle on this range; the cap is two.
What each finding got:

- **Finding 1 (P2) - fixed at `124ec44`.**
  `waiterCancelled` now vacates the `queued` slot before cancelling an abandoned follow-up, so an uncancelled caller arriving in the remainder of the in-flight pass starts a fresh follow-up instead of joining the corpse and inheriting `CancellationError` with no pass run for its trigger.
  The reviewer's probe shape is a permanent host test, "a caller after an abandoned follow-up gets a fresh pass, not the corpse"; M7 below deletes the fix and that test kills it on every run.
  The coalescing bullet above carries the correction and names the window in which it was false.
- **Finding 2 (P2) - the decision is to assert the guarantee, not an order, fixed at `83f9717`.**
  The code does not order the two publishes - both continuations are resumed by the same pass completion - and enforcing an order would be a production-semantics change outside this item's scope, so the test now asserts the membership (two publishes: the foreground's outcome and one nil) and the ledger sentence above says "unordered" instead of "then".
  Evidence at the remediation head: **18 of 18 suite-scoped simulator runs green** (`-only-testing:OttoUITests`, the reviewer's contention shape, which failed 7 of 18 at `c26b2a7`), plus the full simulator suite `** TEST SUCCEEDED **` in the five-dimension table below.
- **Finding 3 (P3)** - the battery below: exact diffs, three full host runs per mutant, the stable part (which tests fail) recorded separately from the sample part (issue counts).
- **Finding 4 (P3)** - the latest-joiner-arguments semantic is pinned by "the follow-up runs with the most recent joiner's arguments", whose callers pass three distinguishable days and whose spy records which day each pass ran with; M5 deletes the implementing line and only that test fails.
- **Finding 5 (P3)** - the spy gained a staged release (`release(upTo:)`) so "a caller during the follow-up pass queues behind it" holds the follow-up mid-run deterministically; M6, which overlapped 58 of 60 in the reviewer's probe while surviving the shipped suite, now dies on every run.
- **Finding 6 (P3)** - the REVIEW RANGES section below; R0 is declared with its honest review status rather than left implicit.

#### The seven-mutant battery - exact change, three full host runs each, 220 tests

| # | exact change | failing tests, identical set all three runs | issues per run |
|---|---|---|---|
| M1 | the serialisation barrier `if let predecessor { _ = try? await predecessor.value }` replaced by `_ = predecessor` | 8 tests - every deterministic gate test | 85 / 85 / 85 |
| M2 | the queued-follow-up branch of `join` replaced by joining `inFlight` (`waiters += 1`, arguments overwritten, in-flight task returned) | 7 tests - all but the two-caller serialisation test | 30 / 30 / 30 |
| M3 | `guard pass.cancelledWaiters >= pass.waiters` weakened to `>= 1` | "a shared pass survives one waiter's cancellation" | 2 / 2 / 2 |
| M4 | `queued = nil` deleted from the promotion in `execute` | "a caller during the follow-up pass queues behind it", "three callers during a pass share one follow-up" | 4 / 4 / 4 |
| M5 | `queued.arguments = arguments` deleted from `join` | "the follow-up runs with the most recent joiner's arguments" | 1 / 1 / 1 |
| M6 | `inFlight = pass` deleted from the promotion in `execute` | "a caller during the follow-up pass queues behind it" | 3 / 3 / 3 |
| M7 | the finding-1 fix `if pass === queued { queued = nil }` deleted from `waiterCancelled` | "a caller after an abandoned follow-up gets a fresh pass, not the corpse", "a follow-up all of whose waiters cancelled never runs" | 3 / 3 / 3 |

Every mutant was applied by a script that asserted the target text occurred exactly once, and the pristine file was restored and byte-compared after each; the suite ran green on the restored file.
The failing-test set was identical on every run of a given mutant, and this time the issue counts were too - both are recorded because the standing lesson is that they need not be.
M5 and M6 are `reviews-5/REVIEW-1.md`'s own surviving mutants, now killed 3 of 3; M4's counts supersede the single-run "2 issues" the original table carried.

#### Measured at the remediation head (`83f9717` plus this ledger commit) - all five

| measurement | `reviews-5/BASELINE-5.md` (`1b352f4`) | at the remediation head | verdict |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 261 / 127 / 209 = 597 | exit 0, **261 / 127 / 220 = 608** | +11 |
| `swiftlint --strict` | clean, 225 files | **clean, 228 files** | +3 files, the stage's three |
| simulator suite | 119 / 72 / 53, 7 known issues, `TEST SUCCEEDED` | **130 / 72 / 56, 7 known issues, `** TEST SUCCEEDED **`** | +14, and the finding-2 regression is gone |
| non-Gregorian harness | 1 / 1 / 5 | **1 / 1 / 5**, same five citations | unchanged |
| flake, twelve full host runs | 12 of 12 | **12 of 12** (220 tests per run) | unchanged |

The suite-scoped simulator dimension finding 2 added: **18 of 18 green** at this head, against 11 of 18 at `c26b2a7`.

---

## STANDING RULES - carried forward, binding on every stage of this round

- **Review ranges**: every review range's START is the previous range's HEAD, stated by sha in the review; no commit may fall outside every range (the `aa92ca7` lesson, N3-4).
- **`OSLogStore` readers**: ten in the tree at this baseline; do not add an eleventh.
  Every canary falsification must state its `--filter` or suppression (item 7 is the fix for this rule's blind spot).
- **Flake discipline**: any claim about a test's stability requires twelve full unmutated `swift test --package-path Packages/OttoUI` runs; a single run - green or red - proves nothing about an intermittent event.
- **Terminal vocabulary**: RESOLVED with artifact evidence, DEFERRED with reason, REJECTED TWICE with the revert and the objection recorded; two REJECT cycles on a range is the cap.
- **Measurement before edit**: every item is reconfirmed by executing the defect before it is touched.
- **No prior record is edited**; corrections to this round's own record name what they correct.
- **Scope**: nothing outside the ten items above may be changed except as a reviewed remediation of this round's own work; all P3s and the non-P2 residuals (R0-7's repair and the Ethiopic residual, Round 0 §4's two items, N4-18, and the rest of round 4's NEXT ROUND) stay in NEXT ROUND.

## REVIEW RANGES

Every range's START is the previous range's HEAD, stated by sha, and no commit of this round may fall outside every range.
This section exists because `reviews-5/REVIEW-1.md` finding 6 found the round's first three commits outside all of them - the same gap `aa92ca7` hid for three rounds.

| range | commits | review |
|---|---|---|
| **R0** `9e73378..d7cbd37` | `1b352f4` (the merge; parents `cd9778c` and `9e73378` - `cd9778c` is main's CI-workflow commit and enters the tree here), `756b8b1`, `d7cbd37` | **no dedicated adversarial review.** The merge's diff against `9e73378` is nine lines of `.github/workflows/ci.yml`, measured at merge time and re-verified by `reviews-5/BASELINE-5.md`; `756b8b1` and `d7cbd37` are docs-only, and the baseline measured the tree they describe. Declared honestly as reviewed-by-measurement only, and flagged for the round's terminal reconciliation |
| **R1** `d7cbd37..c26b2a7` | `eb4d2ae`, `c26b2a7` | `reviews-5/REVIEW-1.md` - **REJECT** |
| **R2** `c26b2a7..` the remediation head | `3173ba4` (the review artifact itself), `124ec44`, `83f9717`, and the commit adding this section, which is the range's HEAD | **re-review pending**; the first REJECT cycle's remediation |

## NEXT ROUND

Opens empty.
Round 4's NEXT ROUND section remains the ledger of record for everything this round's work list does not name.
