# Wave 10 - Notification Delivery & Check-Date Fixes

Date: 2026-08-08

The wave the compressed-timeline device run demanded.
The ⛔ Wave 5 gate passed - the conversion announcement fired at 09:00 on a locked screen with the app never opened since the trial was entered two device-days earlier - and the same run surfaced four real code defects, all four in one place: the gap between the pure planner and actual delivery.
Every engine test ran against a fake whose `add` never throws; `LiveNotificationClient` and `NotificationCoordinator` had zero coverage.
That gap, not the four symptoms, is what this wave closes.
Numbered 10 because 0-8.5, 6A, the three 6B-Preps, and 9A are taken in the spec's wave table; the gate log lives in this directory.

## What exists after this wave

Four commits, each green on its own, in the ordered subjects:

1. *"Select the cancellation check date strictly after the cancellation day"* - defect G.
   `verificationCheckDate(for:cancelledOn:)` picks the first occurrence STRICTLY after the cancellation day (§5.4 v2.6); the paused rule composes (`max(pauseEndsOn - 1, cancellationDay)`).
   The parameter was renamed from `asOf today` to `cancelledOn` because the old name is part of how `>= today` read as correct.
   Pinned by the defect table as named tests (conversion-day cancel → next cycle; mid-cycle; during-trial → conversion charge; before-anchor → anchor), a same-instant-two-timezones test straddling a charge day, and a reachable-state property: no dispute summary's charge date may equal or precede its cancellation day.
2. *"Reconcile the notification plan by diff and protect the conversion-day announcement"* - defects B and C plus the seam.
   The reschedule diffs desired against pending: removes only unwanted identifiers, adds only missing-or-changed ones (same identifier replaces).
   A pending announcement dated its own conversion day is structurally exempt from removal.
   `UserNotificationCentering` seams `UNUserNotificationCenter` at the system boundary; `FakeUserNotificationCenter` records real `UNNotificationRequest` objects, and the translation tests assert trigger type, every date component (timezone deliberately nil - wall-clock semantics per §4.1), repeats, interruption levels, category and action identifiers with their foreground flags, and that a throwing `add` PROPAGATES.
3. *"Implement §6.2 immediate delivery with interval triggers and a delivered check"* - defect A.
   Passed-instant rungs become 5-second `UNTimeIntervalNotificationTrigger`s; the planner keeps past rungs (at their ORIGINAL day, for identifier stability) only while their protected deadline is ahead; `getDeliveredNotifications` is the never-fire-twice check.
   The trial-lead catch-up the planner never had exists now, bounded to strictly-before-cancel-by (the cancel-by day's own rungs own that day; the dailies own the buffer).
4. *"Count live records in import summaries, resolve inflection markup, and state the filtered empty list"* - D, H, I, J.
   The hard gate fixtures exist beside the easy one; import counts are live-record visibility transitions (preview included - it had the identical defect); `subscriptionCountText` actually runs the inflection engine and a test asserts on the RENDERED string; the filtered empty list states itself with a clear-filter action per §7.1.

Plus this documentation commit: spec v2.6, the corrected manual procedure, `DECISIONS.md`, and the next-wave pointer.

## The falsifications, as run

Every fix was confirmed by breaking it and watching the right failure:

- **G:** selector reverted to `>= today` → the Gate Test case failed wanting Sep 10, and the property test failed with `chargeDate 2026-08-10 == cancelledDay 2026-08-10` - the field values exactly.
- **B:** remove-all-then-re-add restored → the suspension test's device state came back `[]`: the empty device, the loss window itself.
- **C:** same reversion → the 09:01 and 23:59 conversion-day tests failed with the announcement gone (the 23:59 outcome was predicted before running: identical to 09:01, because protection keys on the date, not the hour).
- **A:** delivered-check disabled → the already-delivered rung was re-scheduled (the duplicate, observed); catch-up branch disabled → all seven catch-up tests failed with no interval spec anywhere, while the conversion-behind test stayed green (it pins the drop).
- **H:** live filter removed → the field-case test failed reading `added: 4` / `added: 11` - the run's exact wrong numbers.
- **I:** helper reverted to `String(localized:)` → the test failed with the literal `^[1 subscription](inflect: true)` - the screen's exact wrong string.
- **D:** the hard-case gate test fails on pre-Wave-10 code by construction (its assertions are the catch-up specs; they failed during A's falsification).
- **J:** no automated falsification - the empty state is SwiftUI-only and the OttoUI render suite is simulator-hosted. Verify by hand: filter a non-empty list to a status with no members.

The §6.2 implementation itself was falsified once by accident: the first attempt re-dated catch-up rungs to "today," and an existing §6.4 ladder test failed with a fifth rung - which is how the daily-re-warn nuisance and the identifier-stability requirement were caught before ever shipping.

## Phone-in-a-drawer coverage (the §5.2a/v1.5 standing requirement)

Tested against the drawer explicitly this wave: the diff reconciliation and the §6.2 catch-up delivery (new `PhoneInADrawerTests` entry: entered the hard way on the cancel-by day at 10:03, drawer past conversion, wake fires nothing about dead deadlines and reconciles the stale announcement away).
The check-date selector needs no drawer test of its own - it runs once, at cancellation, and the §5.4 roll-forward it feeds already has one.
The import-count, inflection, and empty-list changes are not time-dependent.

## Deliberately not done

- **`NotificationCoordinator` still has no direct tests.** It is `#if os(iOS)` and made of `BGTaskScheduler`, `UIKit` observers, and `UNUserNotificationCenterDelegate` - none reachable from a host-side `swift test`. The seam was placed under `LiveNotificationClient`, where both device defects lived; the coordinator remains thin wiring. An honest coordinator test needs the simulator target, where the Dynamic Type suite already lives - flagged for a later wave, not silently skipped.
- **`verify.sh`'s `PACKAGES`** - the prompt carried this as deferred work, but Wave 6B-Prep-3 already landed the derivation (proven then by committing a throwaway fourth package and watching it get picked up). Confirmed present; nothing to do.
- **Schema:** untouched. V3 frozen, as required; no fix needed one.
- **The `supplyingResumeDate` edge** (deferred check answered later with a resume date at or before the cancellation day) can still watch an already-landed occurrence. The domain cannot know the cancellation DAY there - the episode stores only the instant, §4.1 forbids converting it, and the schema is frozen so the day cannot be stored. Contradicts the deferred state's own premise (it exists because billing was NOT resumed at cancellation), so it is recorded rather than fixed.
