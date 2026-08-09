# Decisions

Rulings made during implementation, with rationale and the alternatives they displaced.
Spec-level rules live in `docs/Subscription-Tracker-Spec.md`; this file records the calls a wave made where the spec left room.

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

### Poll-until-rendered, and what it does NOT fix

`EmptyStateTests.settle` waited a fixed 300 ms; GitHub's runner took roughly 3× as long to render and every test in the suite failed with an empty accessibility tree.
It now polls up to 10 s for a caller-supplied condition naming the content that test is about to assert on - "any label at all" is insufficient, because a navigation bar vends labels before the list body exists.
**This lowers the probability of a spurious failure. It does NOT resolve the ambiguity recorded under Wave 10's defect-J entry.**
A hierarchy that never materializes still vends no accessibility elements, which stays indistinguishable from defect J having actually returned; on timeout the suite reports a failure it cannot attribute.
That limit is structural to hosting a view and reading its accessibility tree - the timeout only decides how long the suite waits before hitting it. Any future "the empty-state suite went red" must be diagnosed, never retried.

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

### Payment-methods copy: "billed to this card"

The inflection engine pluralizes English nouns but does not conjugate English verbs (verified empirically: "1 subscription bill to this card" survives inflection of the old copy).
The copy moved to a number-invariant participle instead of depending on verb agreement the engine cannot deliver.
