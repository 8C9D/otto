import Foundation

/// Plans every reminder one subscription needs within a horizon (spec §6.3).
///
/// Pure planning only: `today` is injected, nothing reads a clock, and turning the
/// plan into notification requests is Wave 4's job. Reminders dated today are kept -
/// whether today's fire time has already passed is a scheduling concern, not a
/// planning one.
///
/// The result is sorted by day, then priority, then kind name, so equal inputs always
/// produce identical output.
///
/// - Parameter cancellation: the subscription's cancellation record when one exists;
///   it drives the verification check for cancellation-pending and cancelled statuses.
public func reminderSchedule(
    for subscription: Subscription,
    cancellation: CancellationRecord? = nil,
    from today: CalendarDay,
    horizonDays: Int
) -> [PlannedReminder] {
    guard horizonDays >= 0 else { return [] }
    let window = today...today.adding(days: horizonDays)

    let planned: [PlannedReminder] = switch subscription.status {
    case .trial:
        trialReminders(for: subscription, in: window)
    case .active:
        renewalReminders(for: subscription, from: today, in: window)
            + usageCheckInReminders(for: subscription, from: today, in: window)
    case .paused:
        // Paused is first-class (spec §5.1): no billing, no renewal reminders - only
        // the warning that billing is about to resume, so it cannot restart unwatched.
        pauseEndingReminders(for: subscription, in: window)
    case .cancellationPending, .cancelled:
        // Not archived until verification passes (spec §5.4), so both statuses keep
        // watching for the charge that should not arrive.
        verificationReminders(for: subscription, cancellation: cancellation, from: today, in: window)
    case .archived:
        []
    }

    return planned.sorted { lhs, rhs in
        (lhs.day, lhs.priority.rawValue, lhs.kind.rawValue) < (rhs.day, rhs.priority.rawValue, rhs.kind.rawValue)
    }
}

/// The three-run trial ladder (spec §6.3): a lead-time warning, then the morning and
/// evening of the cancel-by day. Trials get repetition because a swiped-away
/// notification is gone forever, and a converted trial is unrecoverable money.
private func trialReminders(
    for subscription: Subscription,
    in window: ClosedRange<CalendarDay>
) -> [PlannedReminder] {
    guard let trial = subscription.trial else { return [] }
    let cancelBy = trial.cancelByDate
    let ladder: [(day: CalendarDay, kind: PlannedReminder.Kind)] = [
        (cancelBy.adding(days: -subscription.reminderLeadDays), .trialLead),
        (cancelBy, .trialDayOfMorning),
        (cancelBy, .trialDayOfEvening)
    ]
    return ladder.filter { window.contains($0.day) }.map {
        PlannedReminder(subscriptionID: subscription.id, day: $0.day, kind: $0.kind)
    }
}

/// One reminder per billing date in the horizon, `reminderLeadDays` ahead of it.
/// A billing date whose lead day has already passed gets no planned reminder this
/// cycle; catching up late-added subscriptions is a Wave 4 scheduling decision.
private func renewalReminders(
    for subscription: Subscription,
    from today: CalendarDay,
    in window: ClosedRange<CalendarDay>
) -> [PlannedReminder] {
    var reminders: [PlannedReminder] = []
    var occurrence = firstOccurrenceIndex(
        after: today, anchor: subscription.cycleStartDay, cycle: subscription.cycle
    )
    while true {
        // Iterating the occurrence INDEX is fine - every candidate is still computed
        // directly from the anchor. Iterating by adding intervals to computed dates
        // is what drifts (spec §4.2 rule 3).
        let billing = billingDate(
            occurrence: occurrence, anchor: subscription.cycleStartDay, cycle: subscription.cycle
        )
        let reminderDay = billing.adding(days: -subscription.reminderLeadDays)
        guard reminderDay <= window.upperBound else { break }
        if window.contains(reminderDay) {
            reminders.append(PlannedReminder(subscriptionID: subscription.id, day: reminderDay, kind: .renewal))
        }
        occurrence += 1
    }
    return reminders
}

/// The usage check-in cadence (spec §7.3) - the other half of the FoodApp failure.
/// A tracker that warns a charge is coming but never asks "are you using this?" has
/// solved half the problem.
private let usageCheckInCadenceDays = 90

private func usageCheckInReminders(
    for subscription: Subscription,
    from today: CalendarDay,
    in window: ClosedRange<CalendarDay>
) -> [PlannedReminder] {
    // Counted from the last recorded use, or from the anchor date when use was never
    // recorded - the anchor is the only day the subscription certainly mattered.
    let reference = subscription.lastUsedDate ?? subscription.cycleStartDay
    let daysSinceReference = reference.days(until: today)

    // First multiple of the cadence landing on or after today, computed directly.
    let cadence = usageCheckInCadenceDays
    let firstMultiple = daysSinceReference <= 0 ? 1 : (daysSinceReference + cadence - 1) / cadence

    var reminders: [PlannedReminder] = []
    var multiple = max(1, firstMultiple)
    while true {
        let checkInDay = reference.adding(days: multiple * cadence)
        guard checkInDay <= window.upperBound else { break }
        if window.contains(checkInDay) {
            reminders.append(PlannedReminder(subscriptionID: subscription.id, day: checkInDay, kind: .usageCheckIn))
        }
        multiple += 1
    }
    return reminders
}

/// The resume warning for a paused subscription, `reminderLeadDays` ahead of the day
/// billing resumes. Un-paused-by-accident is a real failure mode: the vendor resumes
/// on schedule and the user has stopped watching (spec §5.1).
private func pauseEndingReminders(
    for subscription: Subscription,
    in window: ClosedRange<CalendarDay>
) -> [PlannedReminder] {
    guard let pauseEndsOn = subscription.pauseEndsOn else { return [] }
    let reminderDay = pauseEndsOn.adding(days: -subscription.reminderLeadDays)
    guard window.contains(reminderDay) else { return [] }
    return [PlannedReminder(subscriptionID: subscription.id, day: reminderDay, kind: .pauseEnding)]
}

/// The post-cancellation verification check (spec §6.3): fires on the first date a
/// charge would have landed after the final legitimate one, asking the user to check
/// their statement. A cancellation is not done until the money is confirmed stopped.
private func verificationReminders(
    for subscription: Subscription,
    cancellation: CancellationRecord?,
    from today: CalendarDay,
    in window: ClosedRange<CalendarDay>
) -> [PlannedReminder] {
    // A resolved record needs no reminder: verified-stopped archives, still-charging
    // moves to the dispute flow.
    if let cancellation, cancellation.verificationState != .pending { return [] }

    // The check fires on the stored next-would-be charge date, computed once at
    // cancellation time (spec §5.4). Once that date has passed unverified - or when
    // no record exists at all - the app keeps watching the first would-be charge
    // date on or after today, computed from the anchor as always. `markedCancelledAt`
    // is a UTC instant; turning an instant into a calendar day requires a timezone,
    // so it deliberately plays no part in date arithmetic.
    let checkDay: CalendarDay
    if let stored = cancellation?.nextChargeDateIfNotCancelled, stored >= today {
        checkDay = stored
    } else {
        checkDay = nextBillingDate(
            after: today.adding(days: -1), anchor: subscription.cycleStartDay, cycle: subscription.cycle
        )
    }
    guard window.contains(checkDay) else { return [] }
    return [PlannedReminder(subscriptionID: subscription.id, day: checkDay, kind: .verification)]
}
