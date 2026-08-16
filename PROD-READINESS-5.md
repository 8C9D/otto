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
| 1 | **N4-7 + N4-3** | The reschedule coalescing gate is in the wrong class, and the background pass is outside it | **RESOLVED** - stage 1; one REJECT cycle (`reviews-5/REVIEW-1.md`), remediated, re-review **PASS-WITH-FINDINGS** (`reviews-5/REVIEW-2.md`) |
| 2 | **N4-2** | Negative-offset corrupt calendars still schedule reminders on wrong days, and no round has decided whether they should | **RESOLVED** - stage 2; review **PASS-WITH-FINDINGS** (`reviews-5/REVIEW-3.md`), three P3s: one corrected in place, two carried (N5-4, N5-5) |
| 3 | **N2-4** (reopened) | The reconcile failure list still truncates at the per-entry budget; round 2's closure was false | **RESOLVED** - stage 3; review **PASS-WITH-FINDINGS** (`reviews-5/REVIEW-4.md`), two P3s: the census corrected in place, the `failedCount=` guard strengthened in R5 |
| 4 | **N4-16** | `lastUsedDate` has no repair on a paused, trial or cancelled subscription | **RESOLVED** - stage 2; reviewed with item 2 (**PASS-WITH-FINDINGS**, `reviews-5/REVIEW-3.md`); the recorded falsification reproduced to the byte, and the flagged wording question's deferral was endorsed |
| 5 | **N4-1** | The export button's action is verified by nothing | **DEFERRED** - the user's decision, the UI-test-target dependency named in ITEM 5 below |
| 6 | **N4-10** | The §6.2 reconcile diff line has no executable guard | **RESOLVED** - stage 3; review **PASS-WITH-FINDINGS** (`reviews-5/REVIEW-4.md`) |
| 7 | **N4-11** | A sibling's canary masks a deleted canary wherever tests share a log window | **RESOLVED** - stage 3; review **PASS-WITH-FINDINGS** (`reviews-5/REVIEW-4.md`), the site census corrected in place |
| 8 | **N2-1** | Five locale-sensitive test citations fail under non-Gregorian hosts | **RESOLVED** - stage 4; review **PASS**, no findings (`reviews-5/REVIEW-5.md`); the harness is 0 / 0 / 0 for the first time since round 2, and the review confirmed it under two locales the stage never ran |
| 9 | **N3-5** | The gap card's copy is false for the implausible-days case, now including Indian/Saka | **RESOLVED** - stage 4; review **PASS**, no findings (`reviews-5/REVIEW-5.md`); the approved copy verified verbatim against the decision record |
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

**RESOLVED**, stage 1.
The stage's range was REJECTED by `reviews-5/REVIEW-1.md` (a starvation defect in the gate and a flaky ordering assertion, both P2), remediated in `124ec44..c94dbbd`, and the re-review `reviews-5/REVIEW-2.md` (`fedb636`) verified every finding closed by execution and passed the remediation with three P3 residuals, routed to NEXT ROUND below.

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
  Evidence at the remediation head: **18 of 18 suite-scoped simulator runs green** at `-only-testing:OttoUITests`; the reviewer's own contention shape was a narrower suite scope, which failed 11 of 18 at `c26b2a7` and is also 18 of 18 green at the re-review (`reviews-5/REVIEW-2.md` finding 3 corrected the attribution this sentence originally made), plus the full simulator suite `** TEST SUCCEEDED **` in the five-dimension table below.
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

## ITEM 2 - N4-2, detected corruption stops scheduling

**RESOLVED**, stage 2 (run jointly with item 4; one range).
The R3 range (`c94dbbd..cdb509e`) was reviewed at `773672c`: **PASS-WITH-FINDINGS** (`reviews-5/REVIEW-3.md`), three P3 findings - finding 2 is corrected in place below, findings 1 and 3 are disclosed below and carried as N5-4 and N5-5.

**The decision this item was waiting on has been taken - by the user, not by this run**: a detected-implausible anchor stops scheduling entirely (option 2 of the five presented), paired with item 4 so the repair is reachable, because stopping without a repair path strands the user.
**Correction after `reviews-5/REVIEW-3.md` finding 2** - the sentence above names the anchor, and the shipped guard silences on ANY detected-implausible stored field: anchor, trial dates, `pauseEndsOn` and `lastUsedDate`.
The per-field extension is this stage's own inference, not part of the option-2 sentence: the ledger loop has treated any implausible stored day as a per-subscription failure since round 3, so the planner now agrees with the ledger it already skipped on, and a partially-wrong plan is indistinguishable from a healthy one - the defect class this item exists to kill.
Owned here so no future reader quotes "the user decided" for a rule wider than the decision sentence states.

### Reconfirmed at the stage start by executing the defect

Per-calendar sweep through the real scheduler at `bb0c0f9`, one corrupt anchor per detected calendar family (the day a pre-F1 build stored for Gregorian 2026-08-06), before any edit:

| family | stored year | scheduled | wrong-day fire dates |
|---|---|---|---|
| buddhist (+543) | 2569 | 0 | - |
| hebrew (+3760) | 5786 | 0 | - |
| japanese (-2018) | 8 | **4** | 9-3, 9-16, 10-3, 11-3 |
| chinese (-1983) | 43 | **4** | 9-3, 9-19, 10-3, 11-3 |
| coptic (-284) | 1742 | **4** | 9-3, 9-16, 10-3, 11-3 |
| islamic (-578) | 1448 | **4** | 9-3, 9-5, 10-3, 11-3 |
| persian (-621) | 1405 | **4** | 9-3, 10-3, 10-19, 11-3 |
| minguo (-1911) | 115 | **4** | 9-3, 10-3, 10-6, 11-3 |
| indian (-78) | 1948 | **4** | 9-3, 9-16, 10-3, 11-3 |

Healthy control: 4 on the right days (9-3, 10-3, 11-3, 11-4).
So the round-4 ledger's "Japanese, Minguo, Islamic and Persian" understated the set: **all seven behind-offset families** scheduled four wrong-day reminders, coptic and chinese included.

Two further shapes the sweep measured that no ledger entry had named:

- A corrupt `lastUsedDate` beside a healthy anchor: Buddhist-written planned **3** (check-in suppressed), Indian-written planned **4 with a wrong-day check-in** (9-23) - a partially-wrong plan indistinguishable from a healthy one.
- **A behind-offset `pauseEndsOn` silently un-paused the subscription**: effective-status derivation read the 1948 resume date as long past, derived `.active`, and planned four rungs identical to a healthy control's. The user paused it; the corruption resumed it.

### What changed

One guard, at the top of the domain planner (`ReminderSchedule.swift`), on the same `implausibleStoredDays(asOf:)` predicate the ledger loop already skips on: any detected-implausible stored day means the subscription plans **nothing**.
The scheduler is untouched - its own doctrine says decisions belong in the domain, and the ledger half of this rule (skip materialization, record the failure, log the days) has lived there since round 3.

Measured after, same sweep: **0 scheduled / 0 pending for every detected family and every corrupt field, `ledgerFailures` names the subscription, `canClaimCoverage` is false**; the healthy control is untouched at 4.

### Disclosure

- The `SKIPPED reason=implausibleStoredDays days=[...]` log line is emitted by the untouched ledger loop and still names the exact days; `SchedulingLogTests` guards it as before. No log surface changed and no `OSLogStore` reader was added.
- `docs/next-wave.md` is rewritten where this change falsified it (`22f2a72`): all nine detected families now send nothing, **silence plus the coverage-gap card is the corruption signal**, and Ethiopic - undetectable, so unreachable by this policy - still sends wrong-day reminders with no card. The claim "reminders do arrive - on the wrong days" is gone because it is no longer true.
- The gap card now appears with zero reminders on every detected calendar, which makes its presence more consistent than before; its COPY is still item 9's business (N3-5) and is not touched here. This change does not make the copy more false: the card's trigger set is unchanged.
- **The silencing has one carve-out, measured by the review (`reviews-5/REVIEW-3.md` finding 1)**: reconcile spares snoozes by design (`NotificationScheduler+Reconcile.swift:36`), so a wrong-day snooze created on a pre-guard build survives every silencing pass, and `snooze` checks no plausibility, so remind-me-later on an already-delivered wrong-day notification schedules one new request. `docs/next-wave.md` now discloses it; whether the pass should also drop snoozes for ledger-failed subscriptions is a behaviour change no round has decided - carried as **N5-4**.

### Tests

- `ImplausibleDayPlanningTests` (OttoDomain, host, counted by `verify.sh`): every detected family plans nothing; corrupt `lastUsedDate` silences the whole subscription; the corrupt-resume pause plans nothing; and the boundary cases keep planning - a day exactly 70 years back, and an Ethiopic-written day, because the guard must not reach past the rule it applies.
- `ImplausibleStoredDayTests` (scheduler level): a behind-offset anchor leaves the notification center empty; the existing Indian test's `scheduledCount == 4` expectation became `== 0` **as the decided policy change, stated in the test comment** - the old comment said "this does NOT stop the wrong-day reminders", and stopping them is what this item is.
- `RecordUsageTests.repairRestoresScheduling`: the full arc - corrupt day silences, repair writes, next pass schedules again.

### What this deliberately does not do

- It does not repair, reinterpret or cross-check the corrupt day (round 3's reasoning stands; the `createdAt` detector remains declined per item 3 of round 4).
- It does not reach Ethiopic: undetectable stays undetected, wrong-day reminders and all - the recorded residual (R0-7).
- It does not decide what the §5.2a effective-status derivation should do with an implausible `pauseEndsOn` outside planning (list rows, detail screens and the §7.2 report still derive from it); that surface is disclosed here and carried as **N5-3**.

## ITEM 4 - N4-16, the lastUsedDate repair is reachable

**RESOLVED**, stage 2 (run jointly with item 2; one range); reviewed in R3 - **PASS-WITH-FINDINGS**, `reviews-5/REVIEW-3.md`.
The review reproduced the recorded pixel falsification to the byte (gate reverted -> byte-identical 34,674-byte windows; restored -> pass), confirmed `recordUsage` carries no status gate, and answered the flagged wording question: the deferral is correct, and the re-wording belongs with item 9's copy work.

### Reconfirmed at the stage start by executing the defect

The only control writing `lastUsedDate` is "I used this today", inside `if subscription.effectiveStatus(asOf:) == .active` in `UsageSectionView` (`PauseFlowView.swift`, the ledger's `:163` now at `:164` after round 4).
Executed rather than read: the new rendering test, run against the unfixed view on the simulator, captures byte-identical windows for a corrupt-paused and a healthy-paused subscription - the section draws for neither - and `recordUsage` itself (`SubscriptionFlowService`) has **no status gate**, so the unreachability was entirely the view's.

### The affordance decision

The minimal honest one: the existing Usage section, with its existing button and copy, now also appears when the stored `lastUsedDate` is detected-implausible - on **any** status - via an extracted, tested visibility rule (`UsageSectionView.isShown(for:asOf:)`).
Writing *today* is a correct repair for this field on every status, because the button's semantics ("I used this on this day") are exactly what the field records and today is the one day the user can truthfully assert from the screen.
`nil` is not corruption and offers no repair; a plausible day off the active state stays hidden - §7.3's rule is otherwise unchanged.
**Flagged for review rather than decided here**: whether the button deserves repair-specific wording on a non-active subscription ("I used this today" on a cancelled subscription is a semantically odd sentence for a correct action). No new user-facing copy was added; re-wording is new copy and this stage did not grant itself that exception.
**Decided since**: asked directly after the R3 review endorsed the deferral, the user kept "I used this today" as the single label on every status; no re-wording ships.

### Tests, layered the way this rig can falsify them

- `VisibilityRuleTests` (host, deterministic, counted everywhere): the full status-by-plausibility matrix on the extracted rule, plus the boundary case pinning the rule to `isPlausibleStoredDay` rather than a private threshold.
- `RecordUsageTests` (host): `recordUsage` writes today over a corrupt day on paused, trial and cancelled, changing nothing else - the model half, pinned so a status gate added there later cannot silently hollow out the view fix.
- `UsageRepairRenderingTests` (simulator): the corrupt-paused window must render and must differ pixel-for-pixel from the healthy-paused control (the `layer.render` floor, `EmptyStateTests`' method after `drawHierarchy` captured blank), with the label and activation halves asserted through the accessibility tree where a client exists.
  **Falsified before trusting**: with the view gate reverted to active-only, the pixel assertion fails on byte-identical 34,674-byte windows; restored, it passes.
- **Cost, stated**: this rig's simulator attaches no accessibility client (the standing condition behind `EmptyStateTests`' 7 known issues), so the label/activation halves record **2 new known issues** here and assert for real only where a client exists. The simulator dimension's expected figure moves from "7 known issues" to "9 known issues"; the deterministic guards above are the ones that bite everywhere.

### What this deliberately does not do

- No new flow, screen, or copy; no UI-test target (still item 5's question).
- The other unreachable repair the round-4 ledger names - `pauseEndsOn` on an already-paused subscription has no picker (`docs/next-wave.md` row 3's resume-and-re-pause workaround) - is out of this item's scope; it is N4-16's sibling, not N4-16.

### Measured at the stage-2 head (`bc2256c` plus this verification commit) - all five

| measurement | at the R2 head (`c94dbbd`) | at the stage-2 head | verdict |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 261 / 127 / 220 = 608 | exit 0, **265 / 127 / 228 = 620** | +4 OttoDomain, +8 OttoUI - the stage's host tests |
| `swiftlint --strict` | clean, 228 files | **clean, 230 files** | +2 files, the stage's two new test files |
| simulator suite | 130 / 72 / 56, 7 known issues, `** TEST SUCCEEDED **` | **133 / 72 / 63, 9 known issues, `** TEST SUCCEEDED **`** | +3 / 0 / +7; the 2 new known issues are exactly the label/activation halves ITEM 4's cost paragraph pre-declared |
| non-Gregorian harness | 1 / 1 / 5 | **1 / 1 / 5**, same five citations | unchanged |
| flake, twelve full host runs | 12 of 12 (220 tests per run) | **12 of 12** (228 tests per run) | unchanged |

---

## ITEM 3 - N2-4 reopened, every failed rung is named

**RESOLVED**, stage 3 (run with items 6 and 7; one range, R4).
The R4 range (`cdb509e..7b6df8c`) was reviewed at `3c47505`: **PASS-WITH-FINDINGS** (`reviews-5/REVIEW-4.md`), two P3 findings.
Finding 2 was this item's edge: `failedCount=` on the diff line - the field this section's aggregate-drop rationale cites as keeping the total - was executable-guarded only at zero, so hardcoding it survived the suite.
**The strengthening landed in R5 (stage 4, `4e23288`), reproduced and falsified by execution**: before the edit, `failedCount=\(failures.count)` hardcoded to `failedCount=\(0)` ran the full host suite green (227 of 227); the pin now lives inside `everyFailedRungIsNamedAtTheCeiling`'s already-open window - the ceiling pass is the one place the real count is forced to 64 - as a same-line `desired=64` + `failedCount=64` match, at no new `OSLogStore` reader; the same mutant now fails exactly that test on all three full host runs (1 / 1 / 1 issues).

### Reconfirmed at the stage start by executing the defect

A temporary probe test at `e93dabb`, before any edit: 64 subscriptions through the real `SchedulerFixture`, every add refused, one pass, one read of the process's own `scheduling` category.
Measured: **64 rungs failed, the single `reconcile failed=[...]` entry pinned at 1037 characters and named 15 of 64**, tail cut mid-identifier (`... 00000000-0<…>]`), each failed-rung token exactly 66 bytes.
The round-4 numbers (`reviews-4/REVIEW-AA92CA7.md`: ~1037, 15-16 named at the ceiling) reproduce at this stage's start; the probe was deleted after recording.

### What changed

`reconcile` now emits **one `reconcile failed <id>=ErrorType` error entry per failed rung** - the shape `OttoStore.watermarkDay`'s unreadable-row lines and the ledger loop's SKIPPED lines already use - so no per-entry budget can reach a tail at any scale the 64-slot ceiling allows.
`OttoLog.failures(_:)`, the joined-list renderer, is replaced by `OttoLog.failedRung(_:_:)`, which renders one pair.

**The aggregate entry is dropped, not kept alongside.**
Recorded reason: a knowingly-truncating list that reads as complete is precisely the defect class this item reopens - the code's own acceptance line says a rung that fails and is then not named is the exact loss RF-3 exists to repair - and keeping a second, lying copy of the record invites the next reader to quote it.
The diff line's `failedCount=` keeps the total, and identifiers-never-counts (DECISIONS.md) is intact: every name still reaches the log, one entry each.

### Measured after

The same 64-rung shape: **64 of 64 failed rungs named**, each on its own complete 83-character entry, asserted byte-for-byte by the permanent test below on every suite run.

### Tests, and what moved to follow the emission shape

- `everyFailedRungIsNamedAtTheCeiling` replaces `theEmittedReconcileLineCarriesReasons` at the same already-open `OSLogStore` query: 64 subscriptions the test owns (indices 9_100-9_163, used nowhere else in the package), the expected set calibrated from the fake's own `addCalls` (asserted `== 64`, the device ceiling), and for every attempted rung one byte-for-byte entry `reconcile failed <id>=AddRefused` - a prefix or contains match could still be satisfied by a truncated tail.
- `failuresCarryReasonsPerRung` became `failedRungCarriesItsReason`: the per-rung-reason and type-never-value assertions survive on the new renderer, the joined-and-sorted rendering it also asserted no longer exists, and the changed test's comment says what it followed.
- `noFailures` (`OttoLog.failures([]) == "-"`) is **deleted with the helper**: the dash was the empty aggregate's rendering, and nothing renders an empty list any more.
  The behavioural half - a clean pass emits no failure entry and reports `failedCount=0` - is asserted at emission level inside item 6's extension of the skip test, pinned to identifiers that test owns.
  This is the stage's one test-count change: the OttoUI host suite goes 228 -> 227, and every dimension figure below moves by exactly that one.

### Falsified

Battery discipline as ITEM 1's: each mutant applied by a script asserting the target text occurs exactly once, pristine file restored and byte-compared after each, failing-test set quoted as the stable property and issue counts as samples (N5-2).

| # | exact change | failing tests, identical set all three full host runs | issues per run (sample) |
|---|---|---|---|
| M1 | the per-rung loop replaced by the round-2 aggregate - sorted join, one `reconcile failed=[...]` entry | `everyFailedRungIsNamedAtTheCeiling` | 64 / 64 / 64 |
| M2 | `for failure in failures` capped to `failures.prefix(15)` | `everyFailedRungIsNamedAtTheCeiling` | 49 / 49 / 49 |

### What this deliberately does not do

- It does not change what `reconcile` throws (still the first failure only) or any field of the diff line.
- It does not touch the emission level or content of any other line; N4-18's territory is untouched.

### Cost and surface

- **No `OSLogStore` reader added - the count stays ten**: the ceiling test inherits its predecessor's read call site (`schedulingLogLines`, the same one query per test).
- A worst-case failing pass emits 64 short error entries instead of one truncated one; a healthy pass emits nothing new.
- Host tests 228 -> 227, for the reason recorded above.

## ITEM 6 - N4-10, the diff line has an executable guard

**RESOLVED**, stage 3; reviewed in R4 - **PASS-WITH-FINDINGS**, `reviews-5/REVIEW-4.md`.
The review's own field-level mutants confirmed the guard catches a deleted `removed=[...]` as well as wholesale deletion; the `failedCount=` zero-only gap is REVIEW-4 finding 2, routed through ITEM 3's note above.

### Reconfirmed at the stage start by executing the defect

At `e93dabb`, before any edit: the §6.2 diff statement (`NotificationScheduler+Reconcile.swift`) deleted by script, the full host suite run - **228 of 228 green** - and the file restored byte-identical (`cmp`).
The defect is the one `reviews-4/REVIEW-AA92CA7.md` finding 2 measured: `aa92ca7`'s file split narrowed the only predicate reading `reconcile ` to `reconcile failed=[`, and no test had read the diff line since.

### What changed

No production change.
`theEmittedSkipLineNamesTheDays` - whose window already contains a successful pass - now seeds a healthy subscription of its own (index 6_610, used nowhere else in the package) so the pass ADDS rungs, and asserts in its already-fetched lines: the diff line exists (`#require`), pinned to the owned identifier inside `added=[...]`, and carries `desired=`, `snoozesSpared=`, `removed=[-]` and `failedCount=0`.
The same block asserts that no per-rung failure entry names the owned identifier - the no-failure half of item 3's emission shape.
The R4-3 precedent applies verbatim: this query is already open, so the guard costs no new reader.

### Falsified

| # | exact change | failing tests, identical set all three full host runs | issues per run (sample) |
|---|---|---|---|
| M3 | the diff `notice` statement deleted - the exact edit that was green at the stage start | `theEmittedSkipLineNamesTheDays` (the diff-line `#require` returns nil) | 1 / 1 / 1 |

### What this deliberately does not do

- It does not pin `pending=`/`desired=` numeric values: those follow planner policy, and this guard's job is that the line exists and its identifier lists are real.
- It does not restore a broad `hasPrefix("reconcile ")` predicate anywhere: the pin is the line's own prefix plus identifiers the test owns, per the `reviews-4/REVIEW-6.md` lesson about unpinned assertions passing on siblings' lines.

## ITEM 7 - N4-11, the canary is per-test

**RESOLVED**, stage 3; reviewed in R4 - **PASS-WITH-FINDINGS**, `reviews-5/REVIEW-4.md`.
**Correction after `reviews-5/REVIEW-4.md` finding 1** - this section originally counted "ten" emission and `requireDelivered` sites; measured by enumeration there are ELEVEN emission sites at both ends of the range (`BoundaryLogTests` emits twice into one window) and eleven `requireDelivered` sites at the head (ten at the range start; that file's one check became two).
The "ten" that is true is the `OSLogStore` reader count, which this section had let stand in for the site census - the same off-by-one population class `reviews-4/REVIEW-AA92CA7.md` findings 3 and 6 record.
The two sentences below are corrected in place and name this correction.

### Reconfirmed at the stage start by executing the defect

Both shapes at `e93dabb`, before any edit, each file restored byte-identical afterwards:

- `MappingLogPrivacyTests`' `emitCanary()` call deleted: the full OttoPersistence suite is **127 of 127 green** - in a `.serialized` target, because `OSLogStore.position(date:)` reaches ~15 seconds behind `since` and a sibling's identical literal is in the window.
- `SchedulingLogTests`' first `emitCanary(to:)` call deleted (the reconcile-failure test's): the full OttoUI host suite is **228 of 228 green**.

### What changed

Both `OttoLogProbe`s: `emitCanary` now mints, emits and returns `otto.test.canary.<UUID>`, and `requireDelivered(_:canary:)` proves THE TEST'S OWN canary was delivered.
All eleven `requireDelivered` call sites at this head pass their own token (corrected from "ten" per the note above).
`BoundaryLogTests` strengthens in passing: its one read spans two categories, the shared literal let EITHER category's delivery satisfy the single check, and it now calls `requireDelivered` once per category token, so both must deliver.
This is the structural fix for the round-4 general form: for the one line class tests themselves emit, the tree can now prove a log line came from a particular test instead of merely making collision unlikely, and the standing rule's per-falsification `--filter` disclosure becomes unnecessary for canaries.

### Falsified - in full-suite runs, no `--filter`

Plain deletion of an emission call is now **inexpressible**: the returned token is what `requireDelivered` takes, so both deletion mutants fail to compile (`cannot find 'canary' in scope`, demonstrated once per host).
The executable mutant is therefore mint-without-emit - the token exists, the emission is gone - which models the masked deletion exactly:

| # | exact change | suite | failing tests, identical set all three FULL-suite runs | issues per run (sample) |
|---|---|---|---|---|
| M4 | the ceiling test's `emitCanary(to:)` replaced by a bare minted literal | full OttoUI host | `everyFailedRungIsNamedAtTheCeiling`, at `requireDelivered` | 1 / 1 / 1 |
| M5 | `MappingLogPrivacyTests`' `emitCanary()` replaced by a bare minted literal | full OttoPersistence | `theEmittedLineIsRedacted`, at `requireDelivered` | 1 / 1 / 1 |

The stage-start reproductions - the same deletions that ran green before the fix - are the falsification's baseline; both now fail their own test or refuse to compile, with no `--filter` and no suppressed subsystem.

### What this deliberately does not do

- N4-18's territory is untouched, and this item brushes it in one place, stated as the work list requires: the canary emissions keep their existing levels - `notice` in OttoUI, `error` in OttoPersistence - so the notice-versus-error mismatch N4-18 records is exactly as it was, neither fixed nor worsened.
- The canary still proves delivery for the window, not emission-side correctness of any production line; `requireDelivered`'s failure message still names the environment causes, now alongside the masking the per-test token ends.

### Cost and surface

- No `OSLogStore` reader added, no query added, no test added or removed; the count stays ten and every canary rides the window its test already opens.
- Eleven emission sites and eleven `requireDelivered` sites at the head (ten `requireDelivered` at the range start) updated in eight files, all test-side; no production code changed (corrected from "ten" per the note above).

### Measured at the stage-3 head (`ebd85c9`) - all five

| measurement | at the R3 head (`cdb509e`) | at the stage-3 head | verdict |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 265 / 127 / 228 = 620 | exit 0, **265 / 127 / 227 = 619** | -1, the deleted `noFailures` ITEM 3 records |
| `swiftlint --strict` | clean, 230 files | **clean, 230 files** | unchanged |
| simulator suite | 133 / 72 / 63, 9 known issues, `** TEST SUCCEEDED **` | **132 / 72 / 63, 9 known issues, `** TEST SUCCEEDED **`** | the same -1, same 9 known issues |
| non-Gregorian harness | 1 / 1 / 5 | **1 / 1 / 5**, same five citations | unchanged |
| flake, twelve full host runs | 12 of 12 (228 tests per run) | **12 of 12** (227 tests per run) | unchanged |

---

## ITEM 8 - N2-1, the formatters honor the requested locale

**RESOLVED**, stage 4 (`1f6b2f7`); reviewed in R5 - **PASS**, no findings (`reviews-5/REVIEW-5.md` at `07c00b2`).
The review reproduced the pre-fix 1/1/5 at `7b6df8c`, measured 0 issues under `he_IL@calendar=hebrew` and `fa_IR@calendar=persian` in addition to the three declared locales, and probed that `.current` defaults still render the process calendar and numerals - the decision's no-user-visible-change half, held.

**The decision this item was waiting on has been taken - by the user, not by this run, 2026-08-15**: formatters fully HONOR THE REQUESTED LOCALE - calendar and numbering system included - with the locale threaded through `cycleText`/`subscriptionCountText` (default `.current`), and NOT the pin-to-Gregorian option.
A Buddhist device must still render Buddhist years through `.current`; only an explicitly passed locale is honored completely.
Call sites and device rendering are unchanged: every new parameter defaults to `.current`.

### Reconfirmed at the stage start by executing the defect

The harness at the stage start, before any edit: **1 / 1 / 5**, the same five citations as every baseline since round 2, with the rendered wrongness on record:

- `th_TH@calendar=buddhist` - `DisplayFormattingTests.swift:49`: "Aug 15, 2569 BE".
- `ja_JP@calendar=japanese` - `:49`: "Aug 15, Reiwa 8".
- `ar_SA@calendar=islamic-umalqura` - `:49` "Rab. I 2, 1448 AH"; `:59` "Every ٤٥ days"; `:68` "١ subscription"; `:69` "٣ subscriptions"; `NotificationReconciliationTests.swift:170` "FoodApp charges $15.99 on Rab. I 12." against a pinned en_CA fixture.

The cause in both classes is the process locale leaking through an explicit request: `Date.FormatStyle` renders through the process calendar and a `.locale()` call does not override it, and `String(localized:)`/`AttributedString(localized:)` format interpolated numbers through the process numbering system.

### What changed

- `DisplayFormatting.swift`: `displayText` and `spokenText` build their `Date.FormatStyle` with `locale:` AND `calendar: locale.calendar` - the RENDERING calendar is the requested locale's.
  The `calendar:` PARAMETER on both stays the day-to-`Date` CONVERSION calendar, a different axis; the two are documented against each other at the seam.
  `cycleText` and `subscriptionCountText` gained `locale: Locale = .current`, threaded into `String(localized:locale:)` and `AttributedString(localized:locale:)`, so interpolated counts format through the requested locale and the Wave-10 inflection still resolves (the no-markup-residue loop keeps the `.current` default on purpose and stays green).
- `NotificationContent.swift`: `displayDate` and `verificationBody` pass `calendar: locale.calendar` into their styles - the `:170` cause; the notification body's date now renders through the locale the scheduler passes.
- Tests: `:59`/`:68`/`:69` now request en_CA explicitly - their expected strings are untouched, and the harness is where they prove the fix; `:49` is untouched entirely, the fix alone makes it pass.
  `requestedLocaleIsHonoredCompletely` is new, and is the half a Gregorian host CAN falsify: an explicit Buddhist locale renders 2569 and an explicit ar_SA locale renders "Every ٤٥ days" / "٣ subscriptions" on every host - before it, reverting the fix was invisible to `verify.sh` and CI, the blind spot `.swiftlint.yml`'s F1 paragraph records for the conversion axis.
- `CalendarEraTests.swift`: the header's "does not exit 0" paragraph is rewritten as the executed fact it now falsifies, and the two instant-comparison tests build their expected side with the same locale-honoring style; their assertions stay in instant-comparison form because what that file pins is the conversion.

### The sweep, recorded either way

- Currency: `currencyText`, `monthlyEquivalentText` and `NotificationContent.money` go through `.currency(...).locale(locale)`, and number format styles already follow the passed locale's numbering - measured, not assumed: the en_CA-pinned `currency` test passed under ar_SA at every baseline including this stage's start, while the `String(localized:)` interpolations beside it failed.
- `spokenText`'s sentence templates (`String(localized:)` without a locale): every interpolated value is a pre-rendered string, so there is no numbering leak; table selection follows the process locale and only the base English table exists.
  Deliberately not threaded - it is outside the decision sentence.
- View-level `.formatted(date:...)` calls (`CancellationSectionView`, `InsightsView.monthText`) take no locale parameter at all: no requested-locale axis exists there, and they render through the device, which the decision keeps.

### Measured after

The harness: **0 / 0 / 0 - exit 0 under all three locales, for the first time since the file's baseline was recorded at `7a3cf54`** (228 tests per locale at the item-8 commit; the terminal figure below includes item 9's additions).
Nothing other than the five citations changed state under the harness.

### Falsified - the battery discipline of items 1 and 3

Each mutant applied by a script asserting the target text occurs exactly once, pristine file restored and byte-compared after each, the failing-test set quoted as the stable property and issue counts as samples (N5-2); the suite ran green on the restored files (232 of 232).

| # | exact change | verdict, identical all three runs | issues per run (sample) |
|---|---|---|---|
| M1 | `displayText`'s style rebuilt as `Date.FormatStyle(date: style).locale(locale)` - the pre-fix form | `requestedLocaleIsHonoredCompletely` fails, full host suite | 1 / 1 / 1 |
| M2 | `cycleText`'s day-interval branch drops `locale: locale` | `requestedLocaleIsHonoredCompletely` fails, full host suite | 1 / 1 / 1 |
| M3 | `subscriptionCountText` drops `locale: locale` | `requestedLocaleIsHonoredCompletely` fails, full host suite | 1 / 1 / 1 |
| M4 | `NotificationContent.displayDate` drops `calendar: locale.calendar` | `changedContentReplacesInPlace` (`NotificationReconciliationTests.swift:170`) fails under the ar_SA harness, exit 1, three helper runs | 1 / 1 / 1 |

M1-M3 are the Gregorian-host falsifications this item never had; M4 is the harness's own.

### What this deliberately does not do

- No pin-to-Gregorian anywhere: `.current` device rendering is untouched on every surface - the user's explicit instruction.
- It does not thread a locale into `spokenText`'s sentence-template lookups (no numeric interpolation, base English table only) or into view-level device rendering.
- It does not touch the F1 conversion seam: `CalendarDay.conversionCalendar` defaults and the `device_calendar_outside_conversion_seam` lint rule are exactly as they were.

### Cost and surface

- No `OSLogStore` reader added - the count stays ten; no new package, product, target or dependency.
- Host tests +1 (`requestedLocaleIsHonoredCompletely`); the five citations keep their assertions, three of them now requesting en_CA explicitly at the call.
- Two production files touched (`DisplayFormatting.swift`, `NotificationContent.swift`); no call site anywhere passes anything new.

## ITEM 9 - N3-5, the gap card tells deliberate silencing from failure

**RESOLVED**, stage 4 (`d8ac728`); reviewed in R5 - **PASS**, no findings (`reviews-5/REVIEW-5.md` at `07c00b2`).
The review retyped the approved sentences from the decision record rather than the source and matched all four branches verbatim, executed the mixed-pass subset membership, and reproduced the pixel falsification to the byte.

**The copy is the user's, approved 2026-08-15, and ships verbatim**: the corrupt-date headline is `"\(subscriptionCountText(N)) with unusable dates"`; the corrupt-date detail is "Their stored dates aren't real calendar days, so Otto has stopped their reminders on purpose. Nothing was deleted. Open each subscription and fix its dates - reminders resume automatically once every date is fixed."; the existing transient copy stays for genuine failures; a mixed pass shows the corruption sentence too, as the actionable half.
The surrounding copy is number-invariant by design - the inflection engine does not conjugate verbs.

**Owned here, not part of the decision sentence** (ITEM 2's correction discipline):

- The outcome carries IDENTIFIERS - `ScheduleOutcome.implausibleDayFailures: [UUID]`, a subset of `ledgerFailures` - and the card renders a COUNT.
  Identifiers-not-counts is a LOG rule (DECISIONS.md), and the SKIPPED log lines already name the ids; the card's own doc comment has said "a count and nothing else" since R4-1, and identifiers at the outcome keep the subset relationship checkable and the ids available to any future surface.
- The mixed composition: the transient headline with the TOTAL count (none of the N was updated), the transient detail verbatim, then the corruption sentences minus the duplicated "Nothing was deleted." - every rendered sentence is from the approved set, and the corrupt-only detail carries the approved paragraph whole.
- Disclosed: in the mixed rendering, "Their stored dates" follows a headline that counts all failures, so the pronoun sweeps the transient failures in; a composition artifact of the approved sentences, visible only on a pass that has both failure kinds at once.

### Reconfirmed at the stage start by executing the defect

A temporary probe (test-shaped, deleted after recording): a real `NotificationScheduler` pass over one subscription whose anchor is 2569-08-06 - the deliberate-silencing case, `ledgerFailures.count=1`, `scheduledCount=0` - fed to the real card:

```
headline: 1 subscription couldn't be updated
detail:   Otto couldn't refresh their reminders on its last check, so some may be missing.
          Nothing was deleted, and it will try again.
```

Both sentences false: Otto refreshed fine and silenced on purpose, and it will "try again" forever without effect until the user repairs the dates - so waiting, which the copy recommends, is exactly wrong, on a card that is itself the corruption signal (`docs/next-wave.md`).

### What changed

- `ScheduleOutcome.implausibleDayFailures`, populated by the ledger loop's implausible-day branch (`NotificationScheduler.reconcileLedger` returns both lists); the scheduler's behaviour is otherwise untouched and the log surface is unchanged.
- `CoverageGapCard` gained `implausibleCount` (default 0) and the four-branch copy matrix: whole-pass-failed and transient-only wordings byte-identical to before, corrupt-only and mixed per the approved copy.
  `headline`/`detail` stay non-private and host-testable - the R4-1 reasoning, now covering four wordings instead of two.
  The card moved to `CoverageGapCard.swift` when the matrix pushed `TodayView.swift` past SwiftLint's 400-line file_length - the `TodaySectionPlan.swift` seam, drawn again.
- The section-plan trigger set is unchanged: the same passes show the card as before (ITEM 2's disclosure anticipated exactly this split); only the words branch.
- `docs/next-wave.md`'s quoted card headline is updated where this change falsified it.
- Tests: the card's copy suite moved to `CoverageGapCardTests.swift` (the same file-length cap, on the test side) and grew corrupt-only, mixed and whole-pass-unchanged tests; `ImplausibleStoredDayTests` pins the subset at the scheduler (including `transientFailureIsNotMarkedImplausible`, a mixed pass through the real scheduler over a new `failMaterialize` knob on the fake ledger); `DynamicTypeTests` grows the two new wordings.

### UI verification

`CoverageGapRenderingTests` (simulator, `EmptyStateTests`' method via ITEM 4's): the corrupt-only card must draw and must differ pixel-for-pixel from the transient card it replaced, with the strings asserted through the accessibility tree where a client exists.
**Pre-declared cost, ITEM 4's condition**: this rig's simulator attaches no accessibility client, so the string half records **1 new known issue** and asserts for real only where a client exists; the simulator dimension's expected figure moves from 9 to 10 known issues.

### Falsified - including the two the work order names

| # | exact change | verdict, identical all three runs | issues per run (sample) |
|---|---|---|---|
| M5 | the headline's corrupt-only condition `implausibleCount == failureCount` swapped to `!=` - corrupt copy for transient failures | `aPartialFailureNamesTheCount`, `aCorruptOnlyPassGetsTheCorruptionCopy`, `aMixedPassCarriesBothHalves` fail, full host suite | 7 / 7 / 7 |
| M6 | the detail's corrupt-only condition swapped to `!=` | the same three tests | 8 / 8 / 8 |
| M7 | the mixed-pass corruption sentence deleted (`guard implausibleCount > 0 else { return transient }` replaced by `return transient`) | `aMixedPassCarriesBothHalves` | 1 / 1 / 1 |
| M9 | the ledger loop never populates the subset (`implausibleDayFailures.append` deleted) | `coverageIsNotClaimed`, `transientFailureIsNotMarkedImplausible` | 2 / 2 / 2 |

And the rendering guard, ITEM 4's shape: with the whole wording rule reverted (M10, three targets, applied together), the pixel assertion fails on **byte-identical 107,396-byte captures** - the corrupt card renders the transient card exactly - and on the restored file the suite passes with the one pre-declared known issue, `** TEST SUCCEEDED **`.

### What this deliberately does not do

- The `TodayView` call-site plumbing (outcome counts into the card's initializer) sits in a view body no test can reach - the same pre-existing shape as `failureCount` at the same call site since R4-1, neither widened nor narrowed here.
- No deep link from the card to the affected subscriptions, and no vendor names: the card stays a count by its own doctrine.
- N5-3, N5-4 and N5-5 - the display surfaces that read corrupt days raw, and the snooze carve-out - are untouched.

### Cost and surface

- No `OSLogStore` reader added - the count stays ten; no new package, product, target or dependency.
- `ScheduleOutcome` gains one field with a defaulted initializer parameter; every existing construction compiles unchanged.
- Host tests +4 (three copy tests net of the move, `transientFailureIsNotMarkedImplausible`); simulator additionally runs the rendering test and the two new Dynamic Type wordings.
- Lint files 230 -> 232: `CoverageGapCard.swift` and `CoverageGapCardTests.swift`, both file-length splits.

### Measured at the stage-4 head (`4e23288` plus this ledger commit) - all five

| measurement | at the stage-3 head (`ebd85c9`) | at the stage-4 head | verdict |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 265 / 127 / 227 = 619 | exit 0, **265 / 127 / 232 = 624** | +5 OttoUI host - the stage's tests, net of the file moves |
| `swiftlint --strict` | clean, 230 files | **clean, 232 files** | +2 files, the two file-length splits |
| simulator suite | 132 / 72 / 63, 9 known issues, `** TEST SUCCEEDED **` | **133 / 73 / 67, 10 known issues, `** TEST SUCCEEDED **`** | +1 / +1 / +4; the 1 new known issue is exactly the rendering label half ITEM 9's cost paragraph pre-declared |
| non-Gregorian harness | 1 / 1 / 5 | **0 / 0 / 0 - exit 0 under all three locales, 232 tests each** | the five citations, closed by item 8; the first 0 / 0 / 0 since the harness existed |
| flake, twelve full host runs | 12 of 12 (227 tests per run) | **12 of 12** (232 tests per run) | unchanged |

---

## ITEM 5 - N4-1, the export button's closure

**DEFERRED**, by the user's decision, taken this round on 2026-08-15, with the dependency named.

The defect is real and unchanged: deleting the sole call from the Settings export button's tap to `AppModel.requestExport(_:)` leaves the whole simulator suite green.
Round 4 moved the export state machine onto the model, where eight tests reach it, so the untested surface is one closure with no logic in it - and that closure is unreachable by any test this project can run.
Closing it requires a UI-test target driving the real Settings screen; rounds 4 and 5 were not permitted to add one by default, and asked directly this round, the user chose deferral over adding it.
The dependency, named for whoever picks this up: an `OttoUITests` UI-testing bundle target (a new target, new scheme membership, a slower suite), and nothing smaller closes the gap.

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
| **R2** `c26b2a7..` the remediation head | `3173ba4` (the review artifact itself), `124ec44`, `83f9717`, and the commit adding this section, which is the range's HEAD (`c94dbbd`) | **PASS-WITH-FINDINGS** at `fedb636` (`reviews-5/REVIEW-2.md`); the re-review artifact and the terminal-stamping commit after it are record-only and carry no code |
| **R3** `c94dbbd..cdb509e` | `fedb636` and `bb0c0f9` (R2's record-only tail, inside a stated range per REVIEW-1 finding 6), then stage 2: `fa9b3f4` (item 2), `617e7c6` (file split), `13082eb` (item 4), `22f2a72` (user doc), `bc2256c` (the ledger record), `cdb509e` (the five-dimension stamp, the range's HEAD) | **PASS-WITH-FINDINGS** at `773672c` (`reviews-5/REVIEW-3.md`) |
| **R4** `cdb509e..7b6df8c` | `773672c` (the review artifact) and `e93dabb` (the finding-routing commit, R3's record-only tail), then stage 3: `bba63cb` (item 3), `2f74aa8` (item 6), `ebd85c9` (item 7), `7b6df8c` (the stage's ledger sections, the range's HEAD) | **PASS-WITH-FINDINGS** at `3c47505` (`reviews-5/REVIEW-4.md`) |
| **R5** `7b6df8c..ff554cf` | `3c47505` (the review artifact) and `b99d8dc` (the stamping commit, R4's record-only tail), then stage 4: `1f6b2f7` (item 8), `d8ac728` (item 9), `4e23288` (the REVIEW-4 finding-2 strengthening), `ff554cf` (the stage's ledger sections, the range's HEAD) | **PASS** at `07c00b2` (`reviews-5/REVIEW-5.md`), no findings |
| **R6** `ff554cf..` the stage-5 head | `07c00b2` (the review artifact) and the stamping commit that carries this row (R5's record-only tail), then stage 5: item 10, and the ledger commit that is the range's HEAD | **review pending** |

## NEXT ROUND

Round 4's NEXT ROUND section remains the ledger of record for everything this round's work list does not name.

- **N5-1 (P3) - the expiration-during-foreground coin flip is disclosed and tracked by nothing.**
  When a background wake-up expires while a foreground pass runs, the two publishes are unordered, so Today's final state is a coin flip between the foreground outcome and the background's nil (`reviews-5/REVIEW-2.md` finding 1).
  The general form is R4-2's nil-publish rule itself: an expired background pass can overwrite a fresh foreground outcome with the failed-pass state.
  Reviewed round-4 behaviour, stated in ITEM 1's record; whether to order the publishes is a decision no round has taken.
- **N5-2 (P3) - the mutant battery's issue-count columns are samples, not properties.**
  M1 and M7 reproduce with counts varying by one across runs (`reviews-5/REVIEW-2.md` finding 2); the stable property is each mutant's failing-test set, which reproduced identically on every run of both hosts.
  Whoever quotes the battery should quote the failing-test sets.
- `reviews-5/REVIEW-2.md` finding 3 - the contention-shape attribution - is corrected in place under the finding-2 remediation entry above, not carried.
- **N5-3 (P3) - the §5.2a derivation still reads an implausible `pauseEndsOn` outside planning.**
  Stage 2 measured a behind-offset resume date silently deriving a paused subscription to `.active`; the planner guard stops the phantom reminders, but list rows, detail screens and the §7.2 report still derive status from the corrupt date, so a subscription the user paused can still DISPLAY as active until the date is repaired.
  Whether the derivation itself should consult plausibility is a §5.2a design question, not a patch.
- **N5-4 (P3) - whether the silencing pass should also drop snoozes for ledger-failed subscriptions.**
  `reviews-5/REVIEW-3.md` finding 1, executed: a pre-guard wrong-day snooze survives every silencing pass (reconcile spares snoozes by design), and remind-me-later on an already-delivered wrong-day notification schedules one new request with its deadline cap computed from the corrupt anchor.
  Disclosed in ITEM 2 and in `docs/next-wave.md`; cancelling user-created state from a corruption guard is its own decision, taken by no round.
- **N5-5 (P3) - the §7.2 zombie report reads a corrupt `lastUsedDate` raw.**
  `reviews-5/REVIEW-3.md` finding 3, executed: a behind-offset day puts a subscription IN the report (~78 years unused) and an ahead-offset day keeps a genuinely unused one OUT, both wrong until the item-4 button is tapped.
  The `lastUsedDate` sibling of N5-3's `pauseEndsOn` display surface; pre-existing, mitigated by item 4 making the repair reachable.
