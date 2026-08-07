# Wave 1 - domain layer and date engine

Date: 2026-08-06

## What exists after this wave

- All spec §5 types as pure value types in `Packages/OttoDomain/Sources/OttoDomain/Models`: `Subscription`, `TrialTerm`, `BillingEvent`, `CancellationRecord`, `PriceChange`, `PaymentMethod`, `Category`, `SubscriptionStatus`, plus `CalendarDay` and `BillingCycle`.
- The date engine in `DateEngine/BillingDates.swift`: `billingDate(occurrence:anchor:cycle:)`, `nextBillingDate(after:anchor:cycle:)`, and `anchor(fromNextBillingDate:cycle:)`, implementing the Stripe clamp-without-drift rule from spec §4.2.
- The reminder planner and slot budget in `Scheduling/`: `reminderSchedule(for:cancellation:from:horizonDays:)`, `PlannedReminder` with kinds and P1-P4 priorities, and `budgeted(_:limit:)`.
- Monthly-equivalent normalisation in `Models/MonthlyEquivalent.swift`, with the rounding rule documented where the rounding lives.
- 50 tests in 11 suites, covering every spec §4.4 case, the required property test, trials, slot budgeting, reminder planning, and validation.

## Design decisions worth recording

- `CalendarDay` does its own Gregorian arithmetic through a proleptic day number (`ordinalDay`) instead of `Foundation.Calendar`, so day arithmetic is provably timezone-free; Foundation appears only at the `fireDate(hour:minute:in:)` boundary and in `DateComponents` conversion.
- Occurrence 0 of `billingDate` is the anchor itself; occurrence N advances N whole intervals from the anchor and clamps the day, never touching a previously computed date.
- `anchor(fromNextBillingDate:cycle:)` returns the entered date unchanged, deliberately: the entered date is a real billing occurrence, stepping backwards would manufacture a wrong clamped anchor, and a clamped next-charge date cannot reveal the vendor's true anchor day.
- `Subscription` stores the anchor only as `cycleStartDay` (a `let`); spec §5.1's `anchorDay` and `anchorMonth` are computed properties so the three fields can never disagree.
- A `pauseEnding` reminder kind was added beyond the prompt's kind list because `pauseEndsOn` must fire a resume reminder and no listed kind describes it; it budgets at P3.
- `budgeted` defines `truncatedAfter` as the day before the earliest dropped reminder - the last day through which the plan is fully scheduled, matching the "reminders scheduled through X" UI promise.
- Validation lives in failable initialisers and is re-enforced in custom `Codable` decoding for `CalendarDay`, `BillingCycle`, and `TrialTerm`, so decoded data cannot bypass the invariants.

## Deliberate limits (not bugs)

- A renewal whose lead day has already passed when the plan is computed gets no reminder for that cycle; whether Wave 4 schedules a catch-up (e.g. same-day) is a scheduling-time decision.
- The trial ladder plans the three listed reminders; the "repeat daily until conversion if unacknowledged" escalation from spec §6.3 depends on acknowledgment state and belongs to Wave 4.
- Usage check-ins count from `lastUsedDate`, falling back to the anchor date when no use was ever recorded.
- The morning and evening trial reminders share a `CalendarDay`; they diverge by fire time at Wave 4 scheduling.
