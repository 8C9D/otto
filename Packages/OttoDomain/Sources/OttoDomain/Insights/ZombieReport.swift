import Foundation

// Zombie detection (spec §7.3) - the other half of Failure A. The FoodApp
// charge wasn't only a date problem; it was $11/month for something nobody was
// using. This report presents FACTS, never a recommendation: "You haven't
// recorded using FoodApp since May. It has cost you $33 since then." The user
// decides; Otto reports.

/// One subscription with no recorded use in the zombie window, and what it has
/// cost over that window.
public struct ZombieEntry: Hashable, Sendable {
    public let subscription: Subscription
    /// The last recorded use, nil when use was never recorded at all.
    public let lastUsedDate: CalendarDay?
    public let daysSinceUse: Int
    /// What the subscription's charge sequence has cost since the reference day
    /// (exclusive) through today, at the effective amount.
    public let costSinceCents: Int
    /// The annual number (spec §7.3): monthly-equivalent × 12.
    public let annualCostCents: Int

    public init(
        subscription: Subscription,
        lastUsedDate: CalendarDay?,
        daysSinceUse: Int,
        costSinceCents: Int,
        annualCostCents: Int
    ) {
        self.subscription = subscription
        self.lastUsedDate = lastUsedDate
        self.daysSinceUse = daysSinceUse
        self.costSinceCents = costSinceCents
        self.annualCostCents = annualCostCents
    }
}

/// Every effectively active subscription with no recorded use in
/// `usageCheckInCadenceDays` (90) or more days, costliest first.
///
/// The reference day is `lastUsedDate`, or the effective billing anchor when
/// use was never recorded - the same rule the §7.3 usage check-in reminders
/// count from, so the report and the notifications can never disagree about
/// what "since" means. For a converted trial that anchor is the conversion
/// date, which is exactly what makes the converted-and-noticed-late records
/// from Wave 5 appear here: paying since conversion, never used since. Those
/// records are the reason this report exists; nothing filters them out.
///
/// Cost is the charge sequence since the reference at the effective amount -
/// money that moved while the subscription went unused. With a recorded use the
/// window opens the day AFTER it (a charge on the use day was, at least that
/// day, paid for something being used); with none it opens ON the anchor, so a
/// converted trial's own conversion charge counts - it moved with no recorded
/// use ever.
public func zombieReport(subscriptions: [Subscription], asOf today: CalendarDay) -> [ZombieEntry] {
    subscriptions
        .filter { $0.deletedAt == nil && $0.effectiveStatus(asOf: today) == .active }
        .compactMap { subscription -> ZombieEntry? in
            let reference = subscription.lastUsedDate ?? subscription.billingAnchor(asOf: today)
            let daysSinceUse = reference.days(until: today)
            guard daysSinceUse >= usageCheckInCadenceDays else { return nil }

            let amount = subscription.billingAmountCents(asOf: today)
            let charges = projectedCharges(
                for: subscription,
                from: subscription.lastUsedDate.map { $0.adding(days: 1) } ?? reference,
                through: today,
                asOf: today
            )
            return ZombieEntry(
                subscription: subscription,
                lastUsedDate: subscription.lastUsedDate,
                daysSinceUse: daysSinceUse,
                costSinceCents: charges.map(\.amountCents).reduce(0, +),
                annualCostCents: monthlyEquivalentCents(amountCents: amount, cycle: subscription.cycle) * 12
            )
        }
        .sorted { lhs, rhs in
            (rhs.costSinceCents, lhs.subscription.name, lhs.subscription.id.uuidString)
                < (lhs.costSinceCents, rhs.subscription.name, rhs.subscription.id.uuidString)
        }
}
