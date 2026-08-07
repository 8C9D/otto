import Foundation

// Insights (spec §7.2): every figure the screen shows, computed here as pure
// functions of the data and the day. Views render; they never compute. Money
// stays integer cents throughout; the only rounding is the monthly-equivalent
// boundary in `monthlyEquivalentCents`, which is a display-and-comparison value
// by contract (spec §3.5, §7.2).
//
// Which subscriptions count where (spec §7.2, §5.1):
//   - effective `.active` (including converted-unacknowledged trials at the
//     converted price, and pauses past their end date - spec §5.2a): full
//     monthly-equivalent toward burn.
//   - effective `.trial`: $0 toward burn, listed under "Converting soon" with
//     the amount and date - counting the converts-to price would overstate
//     what is being paid NOW, counting nothing would hide money about to move.
//   - effective `.paused`: excluded from burn, reported as its own line at the
//     price frozen when the pause began - or the burn figure lies.
//   - cancellation states and archived: no prospective spend anywhere.

/// One category's share of the monthly burn.
public struct CategoryBurn: Hashable, Sendable {
    public let category: Category
    public let monthlyCents: Int

    public init(category: Category, monthlyCents: Int) {
        self.category = category
        self.monthlyCents = monthlyCents
    }
}

/// One month of the next-12-months projection.
public struct MonthlyProjection: Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let totalCents: Int

    public init(year: Int, month: Int, totalCents: Int) {
        self.year = year
        self.month = month
        self.totalCents = totalCents
    }
}

/// One paused subscription's line: excluded from burn, priced at the freeze
/// point (spec §5.1).
public struct PausedSpendLine: Hashable, Sendable {
    public let subscription: Subscription
    /// The price when the pause began: a `PriceChange` recorded during a pause
    /// does not take effect until resume (spec §5.1).
    public let frozenAmountCents: Int
    public let monthlyEquivalent: Int

    public init(subscription: Subscription, frozenAmountCents: Int, monthlyEquivalent: Int) {
        self.subscription = subscription
        self.frozenAmountCents = frozenAmountCents
        self.monthlyEquivalent = monthlyEquivalent
    }
}

/// One unconverted trial's "Converting soon" line - the sentence that is the
/// whole product in one line: "Your monthly burn goes from $84 to $95 on 13 Aug."
public struct ConvertingTrial: Hashable, Sendable {
    public let subscription: Subscription
    public let conversionDate: CalendarDay
    public let convertsToAmountCents: Int
    /// What this trial adds to the monthly burn once it converts.
    public let monthlyEquivalent: Int
    /// The burn after this trial (and every trial converting on or before it)
    /// converts - cumulative, because two trials converting a week apart both
    /// contribute by the later date, and the sentence must not understate.
    public let burnAfterCents: Int

    public init(
        subscription: Subscription,
        conversionDate: CalendarDay,
        convertsToAmountCents: Int,
        monthlyEquivalent: Int,
        burnAfterCents: Int
    ) {
        self.subscription = subscription
        self.conversionDate = conversionDate
        self.convertsToAmountCents = convertsToAmountCents
        self.monthlyEquivalent = monthlyEquivalent
        self.burnAfterCents = burnAfterCents
    }
}

/// One price change with its subscription named, for the cross-subscription log.
public struct PriceChangeLogEntry: Hashable, Sendable {
    public let subscriptionName: String
    public let currencyCode: String
    public let change: PriceChange

    public init(subscriptionName: String, currencyCode: String, change: PriceChange) {
        self.subscriptionName = subscriptionName
        self.currencyCode = currencyCode
        self.change = change
    }
}

// MARK: - Burn

/// The live subscriptions whose full monthly-equivalent counts toward burn.
private func burningSubscriptions(_ subscriptions: [Subscription], asOf today: CalendarDay) -> [Subscription] {
    subscriptions.filter { $0.deletedAt == nil && $0.effectiveStatus(asOf: today) == .active }
}

/// Monthly burn in cents (spec §7.2): every effectively active subscription's
/// monthly-equivalent, summed. Each term is rounded at the monthly-equivalent
/// boundary - the same figure the subscription list shows per row, so the two
/// screens can never disagree about a subscription's contribution.
public func monthlyBurnCents(subscriptions: [Subscription], asOf today: CalendarDay) -> Int {
    burningSubscriptions(subscriptions, asOf: today)
        .map { monthlyEquivalentCents(amountCents: $0.billingAmountCents(asOf: today), cycle: $0.cycle) }
        .reduce(0, +)
}

/// Annualised total: monthly × 12, per §7.2's stated rule.
public func annualizedTotalCents(subscriptions: [Subscription], asOf today: CalendarDay) -> Int {
    monthlyBurnCents(subscriptions: subscriptions, asOf: today) * 12
}

/// Burn by category (spec §7.2) - the view that answers "how much am I actually
/// spending on AI tools". Sorted by cost descending, then category name, so
/// equal inputs always render identically.
public func burnByCategory(subscriptions: [Subscription], asOf today: CalendarDay) -> [CategoryBurn] {
    let grouped = Dictionary(grouping: burningSubscriptions(subscriptions, asOf: today), by: \.category)
    return grouped
        .map { category, members in
            CategoryBurn(
                category: category,
                monthlyCents: members
                    .map { monthlyEquivalentCents(amountCents: $0.billingAmountCents(asOf: today), cycle: $0.cycle) }
                    .reduce(0, +)
            )
        }
        .sorted { ($0.monthlyCents, $1.category.rawValue) > ($1.monthlyCents, $0.category.rawValue) }
}

// MARK: - The next 12 months

/// Every charge the schedule projects in `[today, today + 12 months)`, bucketed
/// by calendar month (spec §7.2) - the current month counts only what is still
/// ahead. Annual renewals cluster, and this is where that becomes visible.
///
/// This is a PROJECTION over future dates, distinct from §5.3 materialization
/// (which is as-of-today ledger work): a trial's paid cycles after conversion
/// belong in a 12-month forecast even though the ledger only materializes its
/// conversion row today, and a dated pause's resumed sequence likewise.
public func next12Months(subscriptions: [Subscription], asOf today: CalendarDay) -> [MonthlyProjection] {
    var buckets: [Int: Int] = [:]  // year * 100 + month -> cents
    let months = (0..<12).map { offset -> (year: Int, month: Int) in
        let zeroBased = today.month - 1 + offset
        return (today.year + zeroBased / 12, zeroBased % 12 + 1)
    }
    let last = months[11]
    let windowEnd = CalendarDay(year: last.year + (last.month == 12 ? 1 : 0),
                                month: last.month == 12 ? 1 : last.month + 1,
                                day: 1)?.adding(days: -1) ?? today
    for subscription in subscriptions where subscription.deletedAt == nil {
        for charge in projectedCharges(for: subscription, from: today, through: windowEnd, asOf: today) {
            buckets[charge.day.year * 100 + charge.day.month, default: 0] += charge.amountCents
        }
    }
    return months.map { year, month in
        MonthlyProjection(year: year, month: month, totalCents: buckets[year * 100 + month] ?? 0)
    }
}

/// The forward-looking charge sequence for one subscription - the derivations
/// applied over future time rather than as of one day.
func projectedCharges(
    for subscription: Subscription,
    from windowStart: CalendarDay,
    through windowEnd: CalendarDay,
    asOf today: CalendarDay
) -> [ExpectedCharge] {
    guard windowStart <= windowEnd else { return [] }
    switch subscription.effectiveStatus(asOf: today) {
    case .active:
        return anchorSequence(
            for: subscription,
            anchor: subscription.billingAnchor(asOf: today),
            amountCents: subscription.billingAmountCents(asOf: today),
            from: windowStart, through: windowEnd
        )
    case .trial:
        // The conversion charge IS the paid sequence's first occurrence: once
        // converted the subscription is effectively active (spec §5.2a), so the
        // projection runs the paid sequence from the conversion anchor.
        guard let trial = subscription.trial else { return [] }
        return anchorSequence(
            for: subscription,
            anchor: trial.conversionDate,
            amountCents: trial.convertsToAmountCents,
            from: max(windowStart, trial.conversionDate), through: windowEnd
        )
    case .paused:
        // A dated pause resumes by derivation (spec §5.2a, v1.6): charges from
        // `pauseEndsOn` are certain and belong in the forecast. An indefinite
        // pause projects nothing - its spend is the separate paused line.
        guard let resumes = subscription.pauseEndsOn else { return [] }
        return anchorSequence(
            for: subscription,
            anchor: subscription.cycleStartDay,
            amountCents: subscription.amountCents,
            from: max(windowStart, resumes), through: windowEnd
        )
    case .cancellationPending, .cancelled, .archived:
        return []
    }
}

private func anchorSequence(
    for subscription: Subscription,
    anchor: CalendarDay,
    amountCents: Int,
    from windowStart: CalendarDay,
    through windowEnd: CalendarDay
) -> [ExpectedCharge] {
    guard windowStart <= windowEnd else { return [] }
    var charges: [ExpectedCharge] = []
    var cursor = windowStart.adding(days: -1)
    while true {
        // Every candidate computed directly from the anchor (spec §4.2 rule 3).
        let chargeDay = nextBillingDate(after: cursor, anchor: anchor, cycle: subscription.cycle)
        guard chargeDay <= windowEnd else { break }
        cursor = chargeDay
        charges.append(ExpectedCharge(day: chargeDay, amountCents: amountCents))
    }
    return charges
}

// MARK: - Paused spend

/// The price a paused subscription froze at (spec §5.1): the amount before any
/// `PriceChange` that took effect during the pause. With no recorded pause
/// start (`pausedOn` nil - records paused before Wave 7 added the field), the
/// current price is the honest answer: the freeze point is unknown, and
/// reconstructing one would be a guess.
public func frozenPausedAmountCents(
    for subscription: Subscription,
    priceChanges: [PriceChange]
) -> Int {
    guard let pausedOn = subscription.pausedOn else { return subscription.amountCents }
    let duringPause = priceChanges
        .filter { $0.subscriptionID == subscription.id && $0.deletedAt == nil && $0.effectiveDate >= pausedOn }
        .sorted { ($0.effectiveDate, $0.createdAt) < ($1.effectiveDate, $1.createdAt) }
    // The earliest change inside the pause carries the pre-pause price in its
    // oldAmountCents - history is appended, never overwritten (spec §5.5).
    return duringPause.first?.oldAmountCents ?? subscription.amountCents
}

/// Every effectively paused subscription's separate spend line (spec §7.2),
/// sorted by monthly-equivalent descending then name.
public func pausedSpendLines(
    subscriptions: [Subscription],
    priceChanges: [PriceChange],
    asOf today: CalendarDay
) -> [PausedSpendLine] {
    subscriptions
        .filter { $0.deletedAt == nil && $0.effectiveStatus(asOf: today) == .paused }
        .map { subscription in
            let frozen = frozenPausedAmountCents(for: subscription, priceChanges: priceChanges)
            return PausedSpendLine(
                subscription: subscription,
                frozenAmountCents: frozen,
                monthlyEquivalent: monthlyEquivalentCents(amountCents: frozen, cycle: subscription.cycle)
            )
        }
        .sorted {
            ($0.monthlyEquivalent, $1.subscription.name) > ($1.monthlyEquivalent, $0.subscription.name)
        }
}

// MARK: - Converting soon

/// Every unconverted trial, ordered by conversion date, each carrying the burn
/// it raises the total to (spec §7.2's pinned trial rule).
public func convertingSoon(subscriptions: [Subscription], asOf today: CalendarDay) -> [ConvertingTrial] {
    let currentBurn = monthlyBurnCents(subscriptions: subscriptions, asOf: today)
    let trials = subscriptions
        .filter { $0.deletedAt == nil && $0.effectiveStatus(asOf: today) == .trial }
        .compactMap { subscription -> (Subscription, TrialTerm)? in
            subscription.trial.map { (subscription, $0) }
        }
        .sorted { lhs, rhs in
            (lhs.1.conversionDate, lhs.0.name, lhs.0.id.uuidString)
                < (rhs.1.conversionDate, rhs.0.name, rhs.0.id.uuidString)
        }
    var runningBurn = currentBurn
    return trials.map { subscription, trial in
        let equivalent = monthlyEquivalentCents(
            amountCents: trial.convertsToAmountCents, cycle: subscription.cycle
        )
        runningBurn += equivalent
        return ConvertingTrial(
            subscription: subscription,
            conversionDate: trial.conversionDate,
            convertsToAmountCents: trial.convertsToAmountCents,
            monthlyEquivalent: equivalent,
            burnAfterCents: runningBurn
        )
    }
}

// MARK: - The price-increase log

/// Every subscription's price history in one list (spec §7.2), newest first.
/// Decreases are included - it is a log, not an accusation - and the UI may
/// distinguish them.
public func priceChangeLog(
    subscriptions: [Subscription],
    priceChanges: [PriceChange]
) -> [PriceChangeLogEntry] {
    let byID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
    return priceChanges
        .filter { $0.deletedAt == nil }
        .compactMap { change -> PriceChangeLogEntry? in
            guard let subscription = byID[change.subscriptionID], subscription.deletedAt == nil else {
                return nil
            }
            return PriceChangeLogEntry(
                subscriptionName: subscription.name,
                currencyCode: subscription.currencyCode,
                change: change
            )
        }
        .sorted { lhs, rhs in
            (rhs.change.effectiveDate, rhs.change.createdAt, rhs.change.id.uuidString)
                < (lhs.change.effectiveDate, lhs.change.createdAt, lhs.change.id.uuidString)
        }
}
