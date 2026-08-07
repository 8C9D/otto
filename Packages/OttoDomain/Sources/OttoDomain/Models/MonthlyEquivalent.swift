/// The monthly-equivalent price of a subscription, so a $120/yr and a $10/mo compare
/// at a glance (spec §7.2). Annualised figures are monthly x 12, computed by callers.
///
/// Formula: amountCents x (30.4375 / cycle length in days), where 30.4375 is the
/// average Gregorian month (365.25 / 12).
///
/// Rounding rule, stated here because this is where the rounding lives: the result
/// rounds to the nearest cent, half away from zero, and this boundary is the ONLY
/// place monthly-equivalent money is ever rounded. The result is a display and
/// comparison value - never store it; stored money is always the exact integer cents
/// the vendor charges. The `Double` below is a transient day-count ratio, not a money
/// value: money enters and leaves this function as integer cents (spec §3.5).
public func monthlyEquivalentCents(amountCents: Int, cycle: BillingCycle) -> Int {
    let averageDaysPerMonth = 30.4375
    let monthsPerCycle = cycle.averageLengthInDays / averageDaysPerMonth
    return Int((Double(amountCents) / monthsPerCycle).rounded(.toNearestOrAwayFromZero))
}
