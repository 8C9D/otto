import Foundation

/// One charge the schedule expects: the day it lands and the amount it will be.
public struct ExpectedCharge: Hashable, Sendable {
    public let day: CalendarDay
    public let amountCents: Int

    public init(day: CalendarDay, amountCents: Int) {
        self.day = day
        self.amountCents = amountCents
    }
}

/// Every charge the subscription's EFFECTIVE status (spec §5.2a) expects inside
/// `[windowStart, windowEnd]` - the decision behind `BillingEvent` materialization
/// (spec §5.3), kept in the domain so the persistence layer creates rows without
/// ever deciding which.
///
/// The window and the status are separate inputs since v1.5: the status is
/// derived as of TODAY, but the window may start behind today (the
/// `lastMaterializedThrough` watermark), so a conversion that fell while the app
/// was closed is expected by the .active branch at its past date - the founding
/// scenario at the ledger layer. Deriving status as of the window start instead
/// would re-run the .trial branch and miss every paid cycle behind today.
///
/// An active subscription - or a trial whose conversion date has passed, anchored
/// at conversion for the converted amount - expects its cycle sequence; an
/// unconverted trial expects exactly one charge, the conversion; paused expects
/// nothing during the pause, but a pause with a `pauseEndsOn` expects the resumed
/// sequence from that day (spec §5.2a, v1.6: the resume is derived, never
/// awaited, and materialization proceeds from `pauseEndsOn`); cancellation states
/// expect nothing prospectively, because a `BillingEvent` asserts a charge is
/// expected and these are watched by verification instead; archived is terminal.
public func expectedCharges(
    for subscription: Subscription,
    from windowStart: CalendarDay,
    through windowEnd: CalendarDay,
    asOf today: CalendarDay
) -> [ExpectedCharge] {
    guard windowStart <= windowEnd else { return [] }
    switch subscription.effectiveStatus(asOf: today) {
    case .active:
        // A derived pause resume runs the ordinary sequence, but never expects a
        // charge from inside the pause: the window may reach back past
        // `pauseEndsOn` (the watermark), and those dates were the vendor's
        // silence, not missed charges (spec §5.2a, v1.6).
        let start = subscription.isResumedPause(asOf: today)
            ? max(windowStart, subscription.pauseEndsOn ?? windowStart)
            : windowStart
        return cycleCharges(for: subscription, from: start, through: windowEnd, asOf: today)
    case .trial:
        // §5.2b guarantees the term exists; the guard keeps this function total.
        guard let trial = subscription.trial,
              (windowStart...windowEnd).contains(trial.conversionDate)
        else { return [] }
        return [ExpectedCharge(day: trial.conversionDate, amountCents: trial.convertsToAmountCents)]
    case .paused:
        // Still inside the pause. With a known end the resumed sequence is
        // already certain, so its rows materialize now - that is what makes the
        // watermark safe to advance while paused (spec §5.3, v1.6). An
        // indefinite pause expects nothing and freezes the watermark instead.
        guard let resumes = subscription.pauseEndsOn else { return [] }
        return cycleCharges(
            for: subscription, from: max(windowStart, resumes), through: windowEnd, asOf: today
        )
    case .cancellationPending, .cancelled, .archived:
        return []
    }
}

/// The anchor sequence's charges in `[windowStart, windowEnd]`, at the effective
/// anchor and amount (spec §5.2a).
private func cycleCharges(
    for subscription: Subscription,
    from windowStart: CalendarDay,
    through windowEnd: CalendarDay,
    asOf today: CalendarDay
) -> [ExpectedCharge] {
    guard windowStart <= windowEnd else { return [] }
    let anchor = subscription.billingAnchor(asOf: today)
    let amount = subscription.billingAmountCents(asOf: today)
    var charges: [ExpectedCharge] = []
    var cursor = windowStart.adding(days: -1)
    while true {
        // Each candidate is computed directly from the anchor - never by
        // adding an interval to a previous date (spec §4.2 rule 3). The
        // window includes today itself: today's charge is still worth
        // confirming.
        let chargeDay = nextBillingDate(after: cursor, anchor: anchor, cycle: subscription.cycle)
        guard chargeDay <= windowEnd else { break }
        cursor = chargeDay
        charges.append(ExpectedCharge(day: chargeDay, amountCents: amount))
    }
    return charges
}

/// Whether one (date, amount) pair is a charge the subscription's effective
/// schedule still expects - the membership test behind spec §5.3's invalidation
/// of `.upcoming` ledger rows.
///
/// Generalized in v1.4: status transitions invalidate too. A subscription in
/// `.cancellationPending`, `.cancelled`, or `.archived` expects no charge at
/// all, and a `.paused` one expects none from inside the pause, so every
/// `.upcoming` row those windows still carry is a phantom - without this,
/// pausing or archiving leaves the user seeing charges in Detail for a
/// subscription that is not going to charge them. A pause with a `pauseEndsOn`
/// keeps its resumed-sequence rows (spec §5.2a, v1.6); resuming re-materializes
/// whatever was dropped, because tombstoned `.upcoming` rows never block
/// (spec §5.3).
public func isExpectedCharge(
    day: CalendarDay,
    amountCents: Int,
    for subscription: Subscription,
    asOf today: CalendarDay
) -> Bool {
    switch subscription.effectiveStatus(asOf: today) {
    case .active:
        // A derived pause resume still expects no charge from inside the pause
        // (spec §5.2a, v1.6) - mirroring expectedCharges keeps invalidation and
        // materialization one decision.
        if subscription.isResumedPause(asOf: today),
           let resumes = subscription.pauseEndsOn, day < resumes {
            return false
        }
        return amountCents == subscription.billingAmountCents(asOf: today)
            && isBillingOccurrence(
                day, anchor: subscription.billingAnchor(asOf: today), cycle: subscription.cycle
            )
    case .trial:
        guard let trial = subscription.trial else { return false }
        return day == trial.conversionDate && amountCents == trial.convertsToAmountCents
    case .paused:
        // The resumed sequence's rows stay valid while the pause runs out; rows
        // dated inside the pause do not (spec §5.2a, v1.6). An indefinite pause
        // expects nothing.
        guard let resumes = subscription.pauseEndsOn, day >= resumes else { return false }
        return amountCents == subscription.billingAmountCents(asOf: today)
            && isBillingOccurrence(
                day, anchor: subscription.billingAnchor(asOf: today), cycle: subscription.cycle
            )
    case .cancellationPending, .cancelled, .archived:
        return false
    }
}
