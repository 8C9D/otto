# Decisions

Rulings made during implementation, with rationale and the alternatives they displaced.
Spec-level rules live in `docs/Subscription-Tracker-Spec.md`; this file records the calls a wave made where the spec left room.

## Sync safety - the monotonicity decision (2026-08-16, user-approved)

The clock-monotonicity defect (`docs/sync-safety.md`, "Wall-clock timestamps are a merge input") was the last blocker before 6B.
Of the three recorded options the user approved **2 and 3 combined** - clamp on write, detect-and-repair at merge input - plus a future-stamp clamp at import; **option 1 (logical clocks / version counters) was rejected**.

### Why option 1 lost

CloudKit's field-level conflict resolution is SwiftData's, not ours: it cannot be fed a Lamport or hybrid-logical clock, so the largest option would rebuild ordering for the app-level decision sites while the deepest instance of the monotonicity assumption stayed untouched.
Held in reserve: if two-device damage is ever observed in practice, this decision reopens.

### What was built

- `monotonicStamp(_:notBefore:)` (`OttoDomain/Models/RecordStamps.swift`): every mutation stamp is `max(now, current updatedAt)`; every tombstone stamp is floored at the record's own `createdAt`.
  Applied at every stamping site found by exhaustive grep: domain transitions and verification folds, pause-episode resume, the rival-cancellation merge, the store's delete cascades, restore tombstoning, the reconciliation pass, and the service/store-model stamping sites (evidence notes, flow services, form models, the default-card unmark, which copied another record's stamp and could regress).
- `resolveImport` repairs stamps on BOTH sides, both strategies, before any comparison: `updatedAt`/`deletedAt` below `createdAt` are raised to it (`createdAt` is never moved - the ledger merge orders on it), then any stamp ahead of the import instant is clamped to it.
  Embedded children (trial, pause episodes, evidence notes) are repaired too, because a future `createdAt` on a pause episode is exactly what `SubscriptionReadRepair` would promote into a calendar day.
  Counted in two new `ImportSummary` fields - `timestampOrderRepairs`, `futureStampClamps` - and logged on `ExportService`'s `import end` line; no UI change.

### The calls inside the call

1. **Symmetric clamping** (current database side too, not just the file's): a locally stored future stamp is just as sticky as an imported one, and the write-time clamp is a `max` that can never lower it - the import is the only pass that can defuse stored future stamps. Deterministic given (snapshots, instant).
2. **Two existing test fixtures were corrected, disclosed here**: `selfImportIsNoOp` and the legacy round-trip test passed import instants that PRECEDED their own fixture data by ~25 years - a shape an honest import cannot produce and the new clamp rightly rejects. The instants were moved after the fixture stamps; every assertion was preserved, and `selfImportIsNoOp` gained four more (`removed == 0`, `skippedOlder > 0`, both new counts zero). No assertion was removed or weakened.
3. **The incident is a permanent test**: `ImportStampRepairTests` carries the real Gate Test instants (`createdAt` 2026-08-10T14:11:05Z, `deletedAt` 2026-08-08T17:32:09Z) so the repair is pinned to the data that motivated it.

### Accepted residuals, stated

- Honest cross-device clock skew still orders last-writer-wins wrongly (§8 prerequisite 4's documented residual; snapshot / kill switch / restore are the floor).
- A dishonest `createdAt` has no local reference to repair against, so §5.3's earliest-`createdAt` ledger merge can still crown the wrong twin; the clamps bound the damage without claiming to restore causal order.

Verified: OttoDomain 275 (was 265), OttoPersistence 130 (was 127), OttoUI 233 tests all passing; `swiftlint --strict` clean over 238 files.

## Gate 3 — delete-and-reinstall

### The import summary is correct, and was re-derived rather than screenshotted

The summary screenshot was missed, so the numbers were re-derived by running the real export through `importedSnapshot` and `resolveImport(strategy: .replace)`: **`subscriptions.added = 3`, `billingEvents.added = 3`, `paymentMethods.added = 1`**, against a file carrying 5 subscriptions (2 tombstoned), 12 charges (9 tombstoned), 1 payment method and 1 tombstoned cancellation episode.
That is the Wave 10 defect-H rule working exactly as specified: counts computed over LIVE ids only, tombstones counted nowhere.

### ⛔ The recovery path silently picks the one strategy that skips watermark reconstruction

`SettingsView.preview(_:)` runs an import against an empty database as `.merge` without asking, on the reasoning that *"an empty database has no merge-or-replace question to ask"*.
That reasoning is correct about RECORDS - against an empty database the two strategies produce identical record sets - and **wrong about watermarks**, because `ExportService.performImport` gives the strategy a second meaning the branch does not account for:

```swift
watermarks: strategy == .replace ? .reconstruct : .keep
```

So `.merge` leaves every watermark nil, and `materializeEvents` computes `windowStart = min(storedWatermark ?? today, today)` - **a nil watermark materializes from TODAY and skips the window between the last real charge and now.**
That is the v2.0/v2.1 founding hazard, reached by the default path.

**The empty database is not an edge case: it is the recovery case.** Fresh install after data loss is precisely when a user imports, so the branch that skips reconstruction is the branch a real recovery takes, and an empty watermark table is not a neutral starting state.
Observed live in the Gate 3 run: the device restored with three correct subscriptions and an entirely empty `ZSTOREDMATERIALIZATIONWATERMARK`.

Recommended fix (not applied here - recorded for the wave that owns it): run an empty-database import as `.replace`. The record outcome is identical by construction, and it is the only branch that reconstructs. Better still, decouple the watermark policy from the merge strategy, since they answer different questions and only one of them is the user's to decide.

### ⚠ The restored device does not match the verified export, and the code is not the reason

The device container holds 4 subscriptions / 7 billing events / 0 cancellation episodes; the verified export carries 5 / 12 / 1.
Subscription `42CE4448` ("Gate Test") and its entire tree - 5 events and 1 episode - are absent, while `FBB14FCE` ("Test"), also tombstoned, restored with all four of its events. Tombstone-ness is therefore not the discriminator.

**The code was cleared by reproduction, not by reading it.** Running the actual export file through the real domain and the real persistence layer:

- `decodeExport` / `importedSnapshot`: 5 / 12 / 1 - "Gate Test" present.
- `resolveImport(strategy: .replace)`: 5 / 12 / 1 - present.
- `OttoStore.restore(_:at:watermarks: .reconstruct)` into a real empty store: 5 / 12 / 1, **missing subs `[]`, missing events 0, missing episodes 0**.

So this build, given this file, preserves the record. The container re-pull was consistent, ruling out a torn read.
**The only remaining explanation is that the file imported on the phone was not the file that was verified on the Mac** - most likely an earlier export predating "Gate Test". Recorded as an open question for the owner rather than as a defect, because attributing it to the code would contradict the reproduction.

**The process lesson is the one worth keeping: verifying an artifact on the Mac does not verify the artifact that was used on the phone.** Same shape as Wave 4 (a report about a different tree than the one committed) and as `verify.sh` versus CI (the same code in a different environment). The gate should name the file by hash on both sides.

## Gate 2 — `BGAppRefreshTask` observed running

### `using: .main`, because `nil` means a background queue and the handler is main-actor isolated

The spec had carried *"`BGAppRefreshTask` not yet observed to run — by this spec's own standard it does not exist until it is"* since Wave 4.
When it was finally made to run, it **crashed the app on every attempt**: `register(forTaskWithIdentifier:using:)` was passed `nil`, which the SDK header documents as *"a default background queue"*, while the launch closure is formed inside a `@MainActor` type and calls main-actor state — so Swift 6 emits a runtime isolation check that traps the moment the system runs it off-main.
Three system-generated crash reports, faulting queue `com.apple.BGTaskScheduler (com.arthurzhang.otto.refresh)`, stack `_dispatch_assert_queue_fail ← dispatch_assert_queue ← _swift_task_checkIsolatedSwift ← closure #1 in NotificationCoordinator.start`.
The trap landed **before the first line of the handler body**, so `setTaskCompleted` was never reached on any path — which on a real launch is also what teaches iOS to stop granting the app wake-ups.
Checked and rejected as the cause: an SDK annotation mismatch. `BGTaskScheduler.h` carries no `NS_SWIFT_UI_ACTOR`, so the isolation was inferred from Otto's own type. This was Otto's defect.
Rejected fix: keeping `nil` and hopping to the main actor inside the closure — more code to say what the `queue` parameter already says, and it leaves the trap one careless edit away.

### ⭐ `dasd` scheduled a handler that could not survive being called

The strongest case this project has produced for the observed-not-inferred standard, and it deserves to be quotable.

While the background path was **completely dead**, the device's own scheduler daemon was doing everything right. From the unified log archive:

```
Otto  [BackgroundTasks:Framework] submitTaskRequest: <BGAppRefreshTaskRequest:
        com.arthurzhang.otto.refresh, earliestBeginDate: 2026-08-10 01:57:42 +0000>
dasd  [duetactivityscheduler] CANCELED: bgRefresh-com.arthurzhang.otto.refresh:94ED7E at priority 10
dasd  [duetactivityscheduler] Submitted: bgRefresh-com.arthurzhang.otto.refresh:041399
        at priority 10 (Sun Aug  9 21:57:42 2026 - Mon Aug 10 21:57:42 2026)
```

`dasd` **accepted** the activity, **priced** it at priority 10, **windowed** it across 24 hours, and **replaced** the stale one — for a launch handler that would trap on its first instruction.

Registration returned `true`. Submission succeeded. The daemon agreed and scheduled it. **Every available signal short of running the body said the feature worked**, and every one of them was worthless.
The spec's standard — *"it does not exist until it is observed"* — is usually read as pedantry about proof. This is the case that shows it is not: the difference between "the system accepted our request" and "our code ran" was the difference between a working feature and one that had never once worked, on the path the entire product depends on when the phone sits in a drawer.
**Corollary for anything later, CloudKit included: a subsystem reporting that it accepted your work is evidence about the subsystem, never about your code.**

### Expiration: a latch for completion, checkpoints for the work - both, because they fix different things

`setTaskCompleted` is now guarded by a lock-held latch that returns true for exactly one caller, and the pass checks cancellation between ledger subscriptions and before planning and reconciling.
Neither alone is sufficient: the latch stops the double completion but would leave the app writing after the OS reclaimed the task; the checkpoints stop the work but still race the latch on who completes.
A lock rather than main-actor confinement, because `BGTask` does not document which queue `expirationHandler` runs on - resting correctness on an undocumented queue assumption is exactly what produced the isolation crash this gate opened with.

**Aborting mid-pass is safe, and this was verified from the source rather than assumed** (the claim arrived as a prompt assertion, and the actual reason is stronger than the one offered):

- `materializeEvents` calls `modelContext.save()` **before** `setDeviceWatermark`, per subscription - so a watermark can never vouch for rows that were not written, which is the property that makes an interrupted loop safe. "Materialization is idempotent" is true but is not the load-bearing reason.
- Finished subscriptions are consistent; unstarted ones are merely behind and are caught up by the next pass's window, which reaches back to the stored watermark.
- `reconcile` never removes an identifier that is in the desired set, so stopping partway leaves a superset or a subset, never the empty set Wave 10's defect B produced.
- `scheduleNextBackgroundRefresh()` runs **before** the cancellable work, so a cancelled pass has already re-armed. Confirmed in code and in the device log: `launched` → `re-armed` → `pass begin`.

Checkpoints are placed at subscription boundaries rather than inside a subscription's invalidate-then-materialize pair, because the boundary is the only point the loop is consistent by construction.

**The scale ceiling, since today's numbers prove nothing about tomorrow's.**
The whole pass is 33-45 ms at three subscriptions, so it was never in danger of hitting the ~30 s background budget, and main-queue occupancy is not the concern people expect: `using: .main` holds the main queue only for the handler prologue (log, re-arm, spawn) - about 2.7 ms, constant, since the pass itself runs on the scheduler actor's executor (visibly a different thread in the log).
What scales is the ledger, at roughly 3-4 ms per subscription, and the planning phase with it.
The remaining uninterruptible stretch is `reconcile` itself: once entered it runs to completion, bounded by the 64-slot limit rather than by subscription count, which is why it is acceptable without an inner checkpoint.
**The reason expiration could not interrupt the pass was never that the pass was short - it was that it never yielded**, and a 45 ms pass simply made the consequence invisible. At a few hundred subscriptions the ledger alone approaches a second, and the log line `pass returned after expiration had already completed the task` is the tripwire: if its timestamp drifts far from the expiration's, the checkpoints have gone too sparse.

### Expiration was not a separate step; it was hidden behind the crash

Forcing expiration was impossible while the handler trapped on entry, because `task.expirationHandler` is assigned *inside* the body that never ran.
Fixing the isolation bug is what made the second defect observable at all, and it is recorded in §9a rather than fixed here: `work.cancel()` does not stop the pass, so expiration and normal completion both fire and `setTaskCompleted` is called twice.
Worth keeping as a rule: **a defect that makes a path unreachable also hides every defect on that path**, so "fixed the crash" is the beginning of testing that path, not the end.

## Gate 1 — the GitHub remote and the first CI run

### The runner label was never the risk; the host environment was

`runs-on: macos-26` is correct and needed no change - the label that three documents called "the ONLY unverified thing" in the workflow.
What the first run actually found, in about six minutes, was two tests that depended on the machine rather than on the app: a currency string pinned to this Mac's `en_CA`, and a fixed 300 ms render wait tuned to this Mac's speed.
The generalizable lesson is about `verify.sh`'s limits, not about CI's: **a clean clone proves the committed *code* builds and passes, and says nothing about the *environment* it passed in.**
Seventeen sessions of clean-clone discipline could not have caught either defect, because every one of them cloned into the same locale on the same hardware.
Rejected: treating both as CI configuration problems and pinning the runner's locale - that would have made CI agree with this Mac instead of making the tests independent of both.

### Notification copy takes a locale, the same way display copy already did

`NotificationContent.money` called `.formatted(.currency(code:))` against the ambient locale, so CAD rendered `$11.00` here and `CA$11.00` on a US runner.
`DisplayFormatting.currencyText` already had the seam (`.locale(locale)`, default supplied, tests pinning `en_CA`); notification copy was the one money-formatting site that never got it.
The scheduler now carries a `locale` provider defaulting to `.autoupdatingCurrent`, mirroring the `fireTimes` provider exactly and for the same stated reason - a background pass must see the current setting.
`displayDate` and `verificationBody` got the same parameter: `.month(.abbreviated)` is equally locale-dependent, and fixing only the money half would have left the identical defect one line away.
Rejected: computing the expected string in the test from the same formatter (tautological - it would pass even if `money` broke); asserting only on a substring (see below).

### `contains("$15.99")` was passing for the wrong reason

`NotificationReconciliationTests` asserted `body.contains("$15.99")`, which is satisfied by `CA$15.99` too - so it passed under **both** renderings and could not have detected either one changing.
It now asserts the full sentence against the pinned locale, plus an explicit `!contains("CA$")`.
This is the same class as a guard that stays green while asserting a dead schema version: a test that cannot fail is not evidence, and a test that passes for the wrong reason is worse than a missing one, because it is counted.
Verified by construction: flipping only the fixture's locale to `en_US` reproduces CI's exact failure on this `en_CA` machine, and both new assertions catch it.

### The empty-state suite: the accessibility tree needs a client, and the pixels do not

Two hypotheses were wrong before the evidence settled this, and the sequence is the point.

1. *"The runner is slow and the 300 ms `settle` is too short."* **Wrong.** After switching to poll-until-rendered, each test burned the full 10 s deadline and still found nothing.
2. *"A scene-less `UIWindow` does not render on a headless runner."* **Wrong.** Quitting Simulator.app, `simctl shutdown all`, and re-running locally passed in 1.6 s.

So the suite was made to report its own environment on timeout, and one run answered it: `scenes=0 elements=45 labels=0 blank=false`.
**The screen renders on CI.** Forty-five elements materialize and the pixels are non-uniform; not one element vends an `accessibilityLabel`, because UIKit populates the accessibility tree only when a client is listening and a fresh CI simulator has none.

**This supersedes the pessimism written earlier in this section and the "indistinguishable from defect J itself" line in the Wave 10 defect-J entry below.** That claim was disproved by the diagnostic: `isVisuallyBlank` and the element count **do** discriminate "this host cannot vend labels" from "defect J is back", because defect J was a screen with nothing drawn on it and this is a screen that drew 45 elements. **Only the label assertions are ambiguous.** The suite already computed `isVisuallyBlank` - it simply asserted it in one of four tests.

The resolution is both halves, not a choice between them:

- **Signals always.** Every test asserts `!isVisuallyBlank`, which needs no accessibility client and directly targets defect J's failure mode.
- **Labels where available.** The string assertions still run everywhere, but on a host with no accessibility client they run inside `withKnownIssue` carrying the diagnosis, so they are reported rather than silently skipped and cannot turn the job red for a reason that is not about the app.

Rejected: dropping the string assertions for pixel and element counts alone - that surrenders the **defect-I class entirely**, where the right number of elements renders with the wrong words in them, which no pixel check can see.
Rejected: `simctl spawn ... defaults write com.apple.Accessibility ApplicationAccessibilityEnabled` in CI - an undocumented write that becomes an unexplained four-test failure the day a runner image changes, and it makes CI agree with this Mac instead of making the suite independent of both.

The `settle` helper gives up early once pixels are present and labels are absent, so an accessibility-less host costs about 2 s per test rather than the full deadline.
**Standing rule: pixels present with labels absent is the accessibility-client diagnosis, never a product defect.** The failure text says so, so the next person does not re-derive it.

### `verify-*-failure.log` is now ignored

`verify.sh` copies a failing package's log to the repo root, and `.gitignore` did not cover it - which is how `verify-OttoPersistence-failure.log` reached a commit (added in `c8cf3f8`, removed in `3a69893`).
It is a build artifact, not a record. The pattern is ignored rather than the script changed, because writing the log where a human will find it is the useful behaviour.

### Otto logs to the unified log, deliberately, in a financial app

The app previously emitted **nothing** - no `os_log`, no `Logger`, no `print` anywhere in the app target or the service layer.
That made the `BGAppRefreshTask` gate unmeetable as specified: there was no log output to capture, only a debugger transcript, and the spec's standard for that gate is observation rather than inference.
Logging is therefore a real change rather than temporary instrumentation, so the gate observes the committed artifact instead of a one-off build - and so a missed reminder in the field stays diagnosable, which is the whole product.
What is logged: which §6.2 trigger began a pass, the reconciliation diff as **identifiers** (a count cannot distinguish a correct three-rung replacement from a remove-all), each subscription's watermark before and after, and which of `setTaskCompleted`'s two paths ran.
What is deliberately **not** logged: amounts, vendor names, payment methods, any subscription content.
A sysdiagnose is readable by anyone holding the phone, so the rule is that sensitive values stay out of the log entirely rather than being marked `.private` - redaction is a display rule, not a guarantee about what was written.
Rejected: temporary instrumentation reverted after the gate (the observed binary would not be the committed one, which is precisely the Wave 4 failure shape); LLDB-only observation (a transcript is real evidence, but it expires with the session and does nothing for a field failure).

## Wave 10 — Notification Delivery & Check-Date Fixes

### Catch-up interval: 5 seconds

`UNTimeIntervalNotificationTrigger` requires a strictly positive interval, so "instant" is not expressible.
5 seconds gives the reconciliation pass room to finish before anything fires (an in-flight add-over-the-top would otherwise race its own delivery) while still reading as "immediately" to the user who just opened the app.
Rejected: 1 second (no slack for the pass, and indistinguishable in value), 60 seconds (the user who entered the subscription at 10:03 may have locked the phone by 10:04 - the point is to land while the subscription is on their mind).

### Catch-up budget: plan members at their rung's own priority

Catch-ups occupy real slots, counted by being ordinary members of the plan inside the `64 - pendingSnoozes` budget.
The wave prompt proposed `64 - pendingSnoozes - pendingCatchups`, the shape snoozes use; that shape is correct for snoozes because they live *outside* the plan, but a catch-up IS a plan entry, so subtracting pending catch-ups on top of planning them would double-count every one.
Priority: a catch-up inherits its rung's kind priority (a late trial rung is still P1; a late usage check-in is still P4) and, being dated earliest, wins its band's nearest-first ordering.
Rejected: a blanket priority boost for lateness - a late usage check-in must not evict a live trial rung, because being late does not change what protects money.
Snoozes stay above everything (v1.4: an explicit user request outranks an inferred schedule).

### Catch-up rungs keep their original day

The first implementation re-dated past rungs to "today", which mints a fresh deterministic identifier every day and re-warns daily until the deadline - a nuisance §6.2 forbids, caught by an existing §6.4 test.
Keeping the original day makes the identifier stable across passes, which is the property the `getDeliveredNotifications` never-fire-twice check depends on.
This also retroactively fixes the same instability in the pre-existing renewal and pause-ending catch-ups.

### Tombstones in import counts: not reported at all

The summary counts live-record visibility transitions only; tombstone movements are counted nowhere rather than reported separately.
The summary's audience asks "did my restore work" - a "plus N tombstones" line is sync bookkeeping that invites exactly the misreading defect H shipped.
Rejected: a separate tombstone line (noise that reads as data), counting them in `added` (the defect itself).
A deletion that *propagates* (a newer tombstone winning a merge over a live record) does count, as `removed`, because a record the user could see stopped being visible.

### Announcement protection scope: its own day only

Reconciliation refuses to remove a pending conversion announcement dated today.
Rejected: protecting every pending announcement - a trial cancelled before conversion must take its future announcement down (no money will move), and a stale past-dated announcement saying "converted today" about yesterday is the dead-deadline dishonesty v1.4 legislated against.

### Defect J's tests live in the render suite, reading the accessibility tree (Verify-J follow-up)

The filtered/unfiltered empty states and the clear-filter behavior are tested in `OttoUITests` (simulator-hosted) by hosting the real `SubscriptionsView` in a `UIWindow` and asserting on the accessibility tree - the rendered strings a VoiceOver user hears - plus activating the clear-filter button through `accessibilityActivate()` and observing the injected `SubscriptionListModel`.
`SubscriptionsView` gained an injectable list model (defaulted, so the app is unchanged) because the filter was unreachable `@State` - the reason J shipped "verify by hand".
Rejected: a dedicated XCUITest target (heavier scaffolding, slower, and the render suite already exists as the simulator home); ViewInspector (a new dependency for what the accessibility tree already provides); pixel-only blankness assertions (an empty `List` is not uniformly blank, so the label assertions are load-bearing and the pixel check is a supplement).
Harness fact worth keeping: a DETACHED `UIHostingController` vends an empty hierarchy for a full screen - no accessibility elements, blank render - indistinguishable from defect J itself; the window plus main-actor suspension (`Task.sleep`, not `RunLoop.run`, which is unavailable in async contexts) is what makes the render real.
⚠ **Superseded in part at Gate 1 (Aug 2026):** "indistinguishable from defect J itself" was too strong and was disproved by a CI diagnostic. A detached or unrenderable host is blank with almost no elements; a host that renders but has no accessibility client shows `elements=45, labels=0, blank=false`. The pixel and element signals discriminate the two - only the label assertions are ambiguous. See "The empty-state suite" under Gate 1 above.

### Payment-methods copy: "billed to this card"

The inflection engine pluralizes English nouns but does not conjugate English verbs (verified empirically: "1 subscription bill to this card" survives inflection of the old copy).
The copy moved to a number-invariant participle instead of depending on verb agreement the engine cannot deliver.
