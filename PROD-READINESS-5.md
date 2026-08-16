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
| 3 | **N2-4** (reopened) | The reconcile failure list still truncates at the per-entry budget; round 2's closure was false | **RESOLVED pending review** - stage 3 |
| 4 | **N4-16** | `lastUsedDate` has no repair on a paused, trial or cancelled subscription | **RESOLVED** - stage 2; reviewed with item 2 (**PASS-WITH-FINDINGS**, `reviews-5/REVIEW-3.md`); the recorded falsification reproduced to the byte, and the flagged wording question's deferral was endorsed |
| 5 | **N4-1** | The export button's action is verified by nothing | open |
| 6 | **N4-10** | The §6.2 reconcile diff line has no executable guard | **RESOLVED pending review** - stage 3 |
| 7 | **N4-11** | A sibling's canary masks a deleted canary wherever tests share a log window | **RESOLVED pending review** - stage 3 |
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

**RESOLVED pending review**, stage 3 (run with items 6 and 7; one range, R4).

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

**RESOLVED pending review**, stage 3.

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

**RESOLVED pending review**, stage 3.

### Reconfirmed at the stage start by executing the defect

Both shapes at `e93dabb`, before any edit, each file restored byte-identical afterwards:

- `MappingLogPrivacyTests`' `emitCanary()` call deleted: the full OttoPersistence suite is **127 of 127 green** - in a `.serialized` target, because `OSLogStore.position(date:)` reaches ~15 seconds behind `since` and a sibling's identical literal is in the window.
- `SchedulingLogTests`' first `emitCanary(to:)` call deleted (the reconcile-failure test's): the full OttoUI host suite is **228 of 228 green**.

### What changed

Both `OttoLogProbe`s: `emitCanary` now mints, emits and returns `otto.test.canary.<UUID>`, and `requireDelivered(_:canary:)` proves THE TEST'S OWN canary was delivered.
All ten `requireDelivered` call sites pass their own token.
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
- Ten emission sites and ten `requireDelivered` sites updated in eight files, all test-side; no production code changed.

### Measured at the stage-3 head (`ebd85c9`) - all five

| measurement | at the R3 head (`cdb509e`) | at the stage-3 head | verdict |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 265 / 127 / 228 = 620 | exit 0, **265 / 127 / 227 = 619** | -1, the deleted `noFailures` ITEM 3 records |
| `swiftlint --strict` | clean, 230 files | **clean, 230 files** | unchanged |
| simulator suite | 133 / 72 / 63, 9 known issues, `** TEST SUCCEEDED **` | **132 / 72 / 63, 9 known issues, `** TEST SUCCEEDED **`** | the same -1, same 9 known issues |
| non-Gregorian harness | 1 / 1 / 5 | **1 / 1 / 5**, same five citations | unchanged |
| flake, twelve full host runs | 12 of 12 (228 tests per run) | **12 of 12** (227 tests per run) | unchanged |

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
| **R4** `cdb509e..` the stage-3 head | `773672c` (the review artifact) and `e93dabb` (the finding-routing commit, R3's record-only tail), then stage 3: `bba63cb` (item 3), `2f74aa8` (item 6), `ebd85c9` (item 7), and the commit adding this stage's ledger sections, which is the range's HEAD | **review pending** |

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
