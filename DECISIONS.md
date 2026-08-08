# Decisions

Rulings made during implementation, with rationale and the alternatives they displaced.
Spec-level rules live in `docs/Subscription-Tracker-Spec.md`; this file records the calls a wave made where the spec left room.

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
