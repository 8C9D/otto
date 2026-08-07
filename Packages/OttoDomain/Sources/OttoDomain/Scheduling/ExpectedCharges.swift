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
/// nothing (spec §5.1); cancellation states expect nothing prospectively, because
/// a `BillingEvent` asserts a charge is expected and these are watched by
/// verification instead; archived is terminal.
public func expectedCharges(
    for subscription: Subscription,
    from windowStart: CalendarDay,
    through windowEnd: CalendarDay,
    asOf today: CalendarDay
) -> [ExpectedCharge] {
    guard windowStart <= windowEnd else { return [] }
    switch subscription.effectiveStatus(asOf: today) {
    case .active:
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
    case .trial:
        // §5.2b guarantees the term exists; the guard keeps this function total.
        guard let trial = subscription.trial,
              (windowStart...windowEnd).contains(trial.conversionDate)
        else { return [] }
        return [ExpectedCharge(day: trial.conversionDate, amountCents: trial.convertsToAmountCents)]
    case .paused, .cancellationPending, .cancelled, .archived:
        return []
    }
}

/// Whether one (date, amount) pair is a charge the subscription's effective
/// schedule still expects - the membership test behind spec §5.3's invalidation
/// of `.upcoming` ledger rows.
///
/// Generalized in v1.4: status transitions invalidate too. A subscription in
/// `.paused`, `.cancellationPending`, `.cancelled`, or `.archived` expects no
/// charge at all, so every `.upcoming` row it still carries is a phantom -
/// without this, pausing or archiving leaves the user seeing charges in Detail
/// for a subscription that is not going to charge them. Resuming from `.paused`
/// re-materializes, because tombstoned `.upcoming` rows never block (spec §5.3).
public func isExpectedCharge(
    day: CalendarDay,
    amountCents: Int,
    for subscription: Subscription,
    asOf today: CalendarDay
) -> Bool {
    switch subscription.effectiveStatus(asOf: today) {
    case .active:
        return amountCents == subscription.billingAmountCents(asOf: today)
            && isBillingOccurrence(
                day, anchor: subscription.billingAnchor(asOf: today), cycle: subscription.cycle
            )
    case .trial:
        guard let trial = subscription.trial else { return false }
        return day == trial.conversionDate && amountCents == trial.convertsToAmountCents
    case .paused, .cancellationPending, .cancelled, .archived:
        return false
    }
}
