# Wave 4 - the notification engine

Date: 2026-08-07

## What exists after this wave

- The spec v1.3 reconciliation, committed before any Wave 4 code (`34e3063`):
  - `effectiveStatus(asOf:)` on `Subscription` (spec §5.2a), with `isConvertedTrial(asOf:)`, `billingAnchor(asOf:)`, and `billingAmountCents(asOf:)`.
    Conversion is derived, never awaited: a `.trial` whose conversion date has arrived IS active, anchored at the conversion date, at the converted amount.
    Consumers rewired: the reminder planner, the Today classifier, and the materializer all act on the effective status; nothing depends on a persisted flip or a user tap.
  - The §5.2b trial invariant enforced at construction: a `precondition` in `Subscription`'s memberwise init, a hand-written `Codable` implementation so decoding cannot bypass it, and a loud `MappingError` in the persistence mapping layer so the state never enters the domain from storage.
    The `.cancelled`-without-record invariant is cross-aggregate and cannot be construction-enforced; it surfaces as a distinct `needsReview` card in Today (§7.1).
  - §5.3 schedule-change invalidation: `invalidateOutdatedUpcomingEvents(for:asOf:at:)` tombstones live `.upcoming` rows that no longer match the effective sequence; rows in any other state are never touched.
    The materializer's dedup was adjusted to ignore tombstoned `.upcoming` rows, because §5.3 says the new sequence's rows are new records, not resurrections; tombstoned rows in any other state still block re-creation.
    `isBillingOccurrence(_:anchor:cycle:)` was added to the date engine as the membership test.
  - `CancellationRecord` gained `unansweredCheckCount` (stored optional, mapped nil to 0) and the `.needsManualReview` state; the planner stops generating verification reminders at three unanswered checks and the Today card carries the escalation.
  - `PriceChange.recordedAt` dropped everywhere; sorts use `createdAt`.
  - Today classification per v1.3 §7.1: converted-unacknowledged trials get a `trialConverted` needs-action card, indefinitely, dated at the conversion.
- The Wave 4 domain additions, all pure and tested:
  - New reminder kinds: `renewalDayOf`, `trialDaily`, `conversionAnnouncement`, with priorities (`trialDaily` and the announcement are P1) and `isTimeSensitive` (exactly the two cancel-by warnings and the announcement).
  - The full trial ladder (spec §6.3): lead, morning, evening, daily escalation, and the §5.2a announcement as the final rung, capped at 5 per trial; dailies drop furthest-from-conversion first, and the four named rungs never drop.
  - The §6.2 catch-up rule in the planner: a billing date still ahead whose lead day passed plans a reminder for today (one per subscription, the earliest un-warned charge); pause-ending warnings catch up the same way.
  - `FireTimePolicy` (09:00 preferred, 19:00 evening last-call), `NotificationPlanIdentifier` (`"<subscriptionID>|<ISO date>|<kind>"`, plus a `snooze.<kind>` namespace that carries the origin kind so a snoozed snooze still knows its deadline), and `snoozedReminderDay(from:deadline:)` - the §6.4 hard cap as a pure function.
- A new layer-4 target, `OttoServices` (in `Packages/OttoUI`), behind a `NotificationClient` protocol so the whole engine runs under `swift test` with no simulator:
  - `NotificationScheduler`: the idempotent full pass - permission check, ledger upkeep (invalidate then materialize, per subscription, one failure never silencing the rest), the pure plan, `budgeted()` under `64 - pendingSnoozes`, translation to calendar-trigger specs, cancel-planned-and-re-add.
    Snoozes live in their own identifier namespace and survive every reschedule.
    Returns a `ScheduleOutcome` with the permission and `coveredThrough` - the honest coverage statement.
  - `NotificationContent`: the copy, pure. The announcement is the FoodApp sentence: "Your X trial converted today. You're now being charged $N/cycle."
  - `NotificationActionHandler` (spec §6.4): `Keeping it` cancels the remaining escalation but never the announcement; `I'm cancelling` flips to `.cancellationPending`, creates the `CancellationRecord` (check date = the trial's conversion charge when cancelled mid-trial, the next sequence charge otherwise), and reschedules - all idempotent under redelivery; `Remind me later` schedules a snooze capped at the deadline, falling to the evening slot on the deadline day, or not at all.
  - `LiveNotificationClient`: the `UNUserNotificationCenter` translation, including category registration and the time-sensitive interruption level.
  - `NotificationCoordinator` (iOS-only): the §6.2 trigger wiring - foreground, delivery, action, `BGAppRefreshTask` (`com.arthurzhang.otto.refresh`, re-armed daily), timezone and significant-time-change observers.
- Store and UI wiring: `NotificationStatusStore` publishes permission and coverage; `SubscriptionsStore` fires a mutation hook after every successful save/delete (the create/edit/delete trigger); Today shows the denied banner at the top permanently, a not-determined enable button, a provisional notice, and the "Reminders scheduled through <date>" footer; a notification tap or follow-up opens the detail via the root sheet.
  The composition root assembles all of it; `project.yml` gained the `OttoServices` product and `BGTaskSchedulerPermittedIdentifiers`.
- 203 tests: 95 domain + 51 persistence + 54 host-side stores/services + 3 Dynamic Type on the simulator.

## The two wave gates

- **200-subscription fixture within 64 slots**: exercised twice - `budgeted()` at the domain level, and end-to-end through the scheduler against fake repositories: exactly 64 pending, all 50 trial rungs present, renewals dropped furthest-first, `truncatedAfter` surfaced and equal to `coveredThrough`.
- **A trial converts and announces with the app never opened**: `conversionAnnouncementPreScheduled` runs the scheduler exactly once, at creation, and asserts the announcement is pending, dated at the conversion, time-sensitive, correctly worded.
  `conversionAnnouncementSurvivesDerivedPath` then proves the derivation: the stored status still `.trial`, a full cancel-and-replan on the conversion morning, and the announcement is still pending alongside the paid sequence's renewals - nothing persisted, nothing tapped.

## Design decisions worth recording

- **The conversion announcement is the trial ladder's final rung.** §6.3's "repeat daily until the conversion date passes" and §5.2a's announcement would otherwise both claim the conversion day; making the announcement the conversion-day notification reconciles them, keeps the default-buffer ladder at exactly the cap of 5, and reads correctly - on the day money moves, the notification states that fact rather than nagging about a deadline that has passed.
- **The announcement is planned from the converted branch when today IS the conversion day.** A scheduler run on the conversion morning cancels all pending requests; without this the pre-scheduled announcement would be cancelled hours before its fire time and never replaced. This case has its own test.
- **"Keeping it" never cancels the announcement.** §5.2a says the conversion is announced "whether or not the user ever acknowledged anything"; acknowledging a deadline is not the same as being told money started moving.
- **Snoozes are pending-notification state, not database state.** They live in their own identifier namespace (`snooze.<kind>`, so re-snoozing keeps the right deadline cap), survive full reschedules by exclusion from the cancel set, and shrink the 64-slot budget beneath them. No schema addition; `UNUserNotificationCenter` persists them across launches.
- **A reminder dated today whose fire hour has passed is skipped, not fired late** - §6.2's own rule ("otherwise fire on the next scheduler run"), and a past-dated calendar trigger is undefined behaviour anyway.
- **Ledger upkeep (invalidate + materialize) runs on every scheduling pass**, not only on edit-saves. Invalidation is idempotent - it only removes rows the current effective sequence does not expect - so running it broadly costs nothing and also catches sequences that changed without a save, i.e. trial conversion moving the anchor.
- **"I'm cancelling" is a foreground action.** Opening the stored cancellation URL requires the app; the state work (status flip, record creation, verification scheduling) happens in the handler regardless, so the background-safety requirement holds for everything that matters.
- **Denied permission clears the planned requests.** They can never be delivered; leaving them pending would make a later grant inherit a stale plan instead of a fresh pass.

## How to test the background task

The refresh task cannot be triggered from the UI; verify it once on a device or simulator:

1. Run Otto from Xcode, background the app (the task is submitted on scene-active).
2. Pause execution and in the LLDB console run:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.arthurzhang.otto.refresh"]`
3. Resume; the scheduler pass runs, and `pendingNotificationRequests` (or the Today footer after foregrounding) reflects a fresh plan.
4. Expiration path: `_simulateExpirationForTaskWithIdentifier:` the same way; the task must complete without crashing.

This has NOT been verified in this wave - it needs a hands-on Xcode session, and a background task that was never observed to run is a feature that does not exist. It is flagged in the report as the first thing to verify manually.

## Deliberate limits (not bugs)

- "Keeping it" cancels pending requests but records nothing: the ledger has no acknowledged field (spec gap, reported), so the silenced reminders return on the next natural reschedule of a later cycle only because their dates move on - and a reschedule in the SAME cycle will replan them. True acknowledgement persistence needs a Wave 5 field.
- Verification and usage-check-in notifications carry no action buttons yet; their flows are Wave 5 and Wave 7.
- The Settings screen (notification hour, lead-day defaults) is Wave 8; `FireTimePolicy.standard` is the only policy in use.
- `NotificationCoordinator` is compiled only on iOS and is exercised manually, not by host-side tests - it contains wiring, no decisions.
- No CloudKit, no Insights, no cancellation/verification UI flows, per the wave boundary.
