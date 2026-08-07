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
/// - Parameter acknowledgedChargeDays: the expected dates of this subscription's
///   acknowledged `BillingEvent`s (spec §5.3, v1.4). "Keeping it" silences that
///   charge's reminders - and because the acknowledgement is persisted and honoured
///   HERE, in the plan, the silencing survives a cancel-all-then-replan reschedule.
///   Silences this cycle only: other charges plan normally. The §5.2a conversion
///   announcement is never silenced - acknowledging a deadline is not the same as
///   being told money started moving.
public func reminderSchedule(
    for subscription: Subscription,
    cancellation: CancellationEpisode? = nil,
    acknowledgedChargeDays: Set<CalendarDay> = [],
    from today: CalendarDay,
    horizonDays: Int
) -> [PlannedReminder] {
    guard horizonDays >= 0 else { return [] }
    let window = today...today.adding(days: horizonDays)

    // The planner acts on the EFFECTIVE status (spec §5.2a): a trial whose
    // conversion date has passed plans like the active subscription it now is,
    // with the paid sequence anchored at the conversion date - whether or not
    // any flow ever persisted the flip.
    let planned: [PlannedReminder] = switch subscription.effectiveStatus(asOf: today) {
    case .trial:
        trialReminders(for: subscription, acknowledgedChargeDays: acknowledgedChargeDays, in: window)
    case .active:
        renewalReminders(
            for: subscription, acknowledgedChargeDays: acknowledgedChargeDays, from: today, in: window
        )
            + usageCheckInReminders(for: subscription, from: today, in: window)
            + conversionDayAnnouncement(for: subscription, from: today)
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

/// A trial's ladder can never exceed this many notifications (spec §6.3), because
/// pre-scheduled P1 rungs consume budget slots and an unbounded buffer must not
/// let one trial starve the rest of the plan.
public let trialLadderCap = 5

/// The full trial ladder (spec §6.3), pre-scheduled and budgeted: the lead-time
/// warning, the morning and evening of the cancel-by day, a daily escalation
/// through the buffer, and - as the final rung - the §5.2a conversion announcement
/// on the conversion date itself. Trials get repetition because a swiped-away
/// notification is gone forever and a converted trial is unrecoverable money;
/// everything is planned up front because reactive rescheduling needs the app to
/// run, and the user ignoring the notification is precisely the case the
/// escalation exists for.
///
/// Capped at `trialLadderCap` total. The four named rungs always survive; daily
/// rungs drop furthest-from-conversion first, because the last calls before the
/// money moves are the ones worth keeping. At the default 2-day buffer the ladder
/// is exactly five: lead, morning, evening, one daily, announcement.
private func trialReminders(
    for subscription: Subscription,
    acknowledgedChargeDays: Set<CalendarDay>,
    in window: ClosedRange<CalendarDay>
) -> [PlannedReminder] {
    guard let trial = subscription.trial else { return [] }
    let cancelBy = trial.cancelByDate
    let conversion = trial.conversionDate

    // "Keeping it" acknowledges the conversion charge - the trial's only ledger
    // row - and cancels the remaining escalation (spec §6.3). The announcement is
    // the one rung that survives: §5.2a sends it whether or not the user ever
    // acknowledged anything.
    if acknowledgedChargeDays.contains(conversion) {
        guard window.contains(conversion) else { return [] }
        return [PlannedReminder(subscriptionID: subscription.id, day: conversion, kind: .conversionAnnouncement)]
    }

    var dailies: [(day: CalendarDay, kind: PlannedReminder.Kind)] = []
    var dailyDay = cancelBy.adding(days: 1)
    while dailyDay < conversion {
        dailies.append((dailyDay, .trialDaily))
        dailyDay = dailyDay.adding(days: 1)
    }
    let fixedRungs: [(day: CalendarDay, kind: PlannedReminder.Kind)] = [
        (cancelBy.adding(days: -subscription.reminderLeadDays), .trialLead),
        (cancelBy, .trialDayOfMorning),
        (cancelBy, .trialDayOfEvening),
        (conversion, .conversionAnnouncement)
    ]
    let dailyBudget = max(0, trialLadderCap - fixedRungs.count)
    let ladder = fixedRungs + dailies.suffix(dailyBudget)

    return ladder.filter { window.contains($0.day) }.map {
        PlannedReminder(subscriptionID: subscription.id, day: $0.day, kind: $0.kind)
    }
}

/// The conversion announcement for the day a trial converts (spec §5.2a). By then
/// the effective status is already `.active`, so the trial branch never sees the
/// conversion day - but a scheduler run that morning cancels all pending requests,
/// and without this the pre-scheduled announcement would be cancelled hours before
/// its fire time and never replaced. Money starts moving today; the statement of
/// that fact must survive every reschedule that happens today.
private func conversionDayAnnouncement(
    for subscription: Subscription,
    from today: CalendarDay
) -> [PlannedReminder] {
    guard let trial = subscription.trial,
          subscription.isConvertedTrial(asOf: today),
          trial.conversionDate == today
    else { return [] }
    return [PlannedReminder(subscriptionID: subscription.id, day: today, kind: .conversionAnnouncement)]
}

/// One reminder per billing date in the horizon, `reminderLeadDays` ahead of it,
/// plus the optional same-day reminder (spec §6.3) and the §6.2 catch-up rule: a
/// billing date still ahead whose lead day has already passed gets a reminder
/// TODAY instead of silence. Without the catch-up, Mode B onboarding fails in its
/// most common case - the user adds a subscription because they noticed a charge
/// coming in two days, the 3-day lead is already past, and nothing fires for the
/// exact charge that prompted them.
private func renewalReminders(
    for subscription: Subscription,
    acknowledgedChargeDays: Set<CalendarDay>,
    from today: CalendarDay,
    in window: ClosedRange<CalendarDay>
) -> [PlannedReminder] {
    // The effective anchor (spec §5.2a): the conversion date once a trial has
    // converted, the stored anchor otherwise.
    let anchor = subscription.billingAnchor(asOf: today)
    var reminders: [PlannedReminder] = []
    var caughtUp = false
    var occurrence = firstOccurrenceIndex(
        after: today, anchor: anchor, cycle: subscription.cycle
    )
    while true {
        // Iterating the occurrence INDEX is fine - every candidate is still computed
        // directly from the anchor. Iterating by adding intervals to computed dates
        // is what drifts (spec §4.2 rule 3).
        let billing = billingDate(
            occurrence: occurrence, anchor: anchor, cycle: subscription.cycle
        )
        let reminderDay = billing.adding(days: -subscription.reminderLeadDays)
        guard reminderDay <= window.upperBound else { break }
        if acknowledgedChargeDays.contains(billing) {
            // "Keeping it" silences this charge only (spec §6.4): no lead, no
            // same-day, no catch-up. The next cycle's charge plans normally.
            occurrence += 1
            continue
        }
        if window.contains(reminderDay) {
            reminders.append(PlannedReminder(subscriptionID: subscription.id, day: reminderDay, kind: .renewal))
        } else if reminderDay < today, !caughtUp {
            // The lead day has passed but the charge is still ahead: fire today.
            // One catch-up at most - with a lead longer than the cycle several
            // lead days can be in the past at once, and identical (day, kind)
            // pairs would collide in the deterministic identifier anyway; the
            // earliest un-warned charge is the urgent one.
            caughtUp = true
            reminders.append(PlannedReminder(subscriptionID: subscription.id, day: today, kind: .renewal))
        }
        if subscription.sameDayReminder, window.contains(billing) {
            reminders.append(PlannedReminder(subscriptionID: subscription.id, day: billing, kind: .renewalDayOf))
        }
        occurrence += 1
    }
    return reminders
}

/// The usage check-in cadence (spec §7.3) - the other half of the FoodApp failure.
/// A tracker that warns a charge is coming but never asks "are you using this?" has
/// solved half the problem. Public because the zombie report uses the same
/// threshold: a subscription is a zombie at exactly the age its check-in fires.
public let usageCheckInCadenceDays = 90

private func usageCheckInReminders(
    for subscription: Subscription,
    from today: CalendarDay,
    in window: ClosedRange<CalendarDay>
) -> [PlannedReminder] {
    // Counted from the last recorded use, or from the effective anchor when use was
    // never recorded - the anchor is the only day the subscription certainly mattered,
    // and for a converted trial that day is the conversion (spec §5.2a).
    let reference = subscription.lastUsedDate ?? subscription.billingAnchor(asOf: today)
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
    var reminderDay = pauseEndsOn.adding(days: -subscription.reminderLeadDays)
    // The §6.2 catch-up rule applies here too: a pause ending inside the lead
    // window still deserves its warning, today, not silence.
    if reminderDay < window.lowerBound && pauseEndsOn >= window.lowerBound {
        reminderDay = window.lowerBound
    }
    guard window.contains(reminderDay) else { return [] }
    return [PlannedReminder(subscriptionID: subscription.id, day: reminderDay, kind: .pauseEnding)]
}

/// The post-cancellation verification check (spec §6.3): fires on the first date a
/// charge would have landed after the final legitimate one, asking the user to check
/// their statement. A cancellation is not done until the money is confirmed stopped.
private func verificationReminders(
    for subscription: Subscription,
    cancellation: CancellationEpisode?,
    from today: CalendarDay,
    in window: ClosedRange<CalendarDay>
) -> [PlannedReminder] {
    // A resolved record needs no reminder: verified-stopped archives, still-charging
    // moves to the dispute flow, and needs-manual-review has already escalated to a
    // persistent Today card - three ignored checks mean notifications are not
    // reaching this item, and a fourth won't either (spec §5.4).
    if let cancellation, cancellation.verificationState != .pending { return [] }
    if let cancellation, cancellation.unansweredCheckCount >= 3 { return [] }

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
