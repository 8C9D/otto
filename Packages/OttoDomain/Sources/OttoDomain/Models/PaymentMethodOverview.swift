import Foundation

// Payment methods (spec §5.5): the expiry warning and the per-card totals are
// domain decisions - the screen renders them, it never computes.

/// How far ahead of a card's expiry the warning shows. Two months: long enough
/// to receive a replacement card and update the vendors, short enough not to be
/// permanent noise.
public let cardExpiryWarningDays = 60

/// A card's standing relative to its expiry (spec §5.5).
public enum CardExpiryStatus: Hashable, Sendable {
    /// Valid, expiry not close.
    case valid
    /// Valid through `lastValidDay`, which is `cardExpiryWarningDays` or fewer
    /// days away - subscriptions on this card will start failing soon after.
    case expiringSoon(lastValidDay: CalendarDay)
    /// The card expired at the end of its printed month.
    case expired(lastValidDay: CalendarDay)
}

extension PaymentMethod {
    /// The last day the card is valid: cards run through the END of their
    /// printed month. An unrepresentable month/year (corrupt data) reports as
    /// already expired rather than silently valid - erring loud, not blind.
    public var lastValidDay: CalendarDay? {
        guard let firstOfMonth = CalendarDay(year: expiryYear, month: expiryMonth, day: 1) else {
            return nil
        }
        let nextMonth = expiryMonth == 12
            ? CalendarDay(year: expiryYear + 1, month: 1, day: 1)
            : CalendarDay(year: expiryYear, month: expiryMonth + 1, day: 1)
        return nextMonth?.adding(days: -1) ?? firstOfMonth
    }

    /// The §5.5 expiry warning, derived - never awaited or stored.
    public func expiryStatus(asOf today: CalendarDay) -> CardExpiryStatus {
        guard let lastValidDay else { return .expired(lastValidDay: today) }
        if today > lastValidDay {
            return .expired(lastValidDay: lastValidDay)
        }
        if today.days(until: lastValidDay) <= cardExpiryWarningDays {
            return .expiringSoon(lastValidDay: lastValidDay)
        }
        return .valid
    }
}

/// What one payment method carries: how many live subscriptions bill to it and
/// their combined monthly-equivalent (spec §5.5's per-card totals).
public struct PaymentMethodLoad: Hashable, Sendable {
    public let subscriptionCount: Int
    public let monthlyCents: Int

    public init(subscriptionCount: Int, monthlyCents: Int) {
        self.subscriptionCount = subscriptionCount
        self.monthlyCents = monthlyCents
    }
}

/// Per-card totals, keyed by payment method id. Counts what is actually
/// billing: effectively active subscriptions (spec §5.2a derivations included)
/// at their monthly-equivalent - the same rule as the burn, so a card's total
/// is the slice of the burn that hits it.
public func paymentMethodLoads(
    subscriptions: [Subscription],
    asOf today: CalendarDay
) -> [UUID: PaymentMethodLoad] {
    var loads: [UUID: PaymentMethodLoad] = [:]
    for subscription in subscriptions
    where subscription.deletedAt == nil && subscription.effectiveStatus(asOf: today) == .active {
        guard let methodID = subscription.paymentMethodID else { continue }
        let equivalent = monthlyEquivalentCents(
            amountCents: subscription.billingAmountCents(asOf: today), cycle: subscription.cycle
        )
        let current = loads[methodID] ?? PaymentMethodLoad(subscriptionCount: 0, monthlyCents: 0)
        loads[methodID] = PaymentMethodLoad(
            subscriptionCount: current.subscriptionCount + 1,
            monthlyCents: current.monthlyCents + equivalent
        )
    }
    return loads
}
