// The date engine (spec §4) - the highest-risk component in the app. If it is wrong,
// the app is actively harmful: the user has stopped watching their own subscriptions
// and delegated that to a tool firing on the wrong day.
//
// Every function here is pure. Results depend only on the arguments, and "today" is
// always a parameter - nothing reads the system clock or timezone.
//
// The month-end rule matches Stripe's documented behaviour (spec §4.2): the anchor
// day is stored as entered and is immutable; every occurrence advances whole
// intervals from the anchor and clamps the day to what the landing month holds.
// A Jan 31 monthly subscription bills Feb 28, then Mar 31 - the February clamp never
// propagates, because nothing is ever computed from a previously computed date.

/// The billing date `occurrenceIndex` cycles after the anchor.
///
/// Occurrence 0 is the anchor itself. Negative indices are the mirror-image dates
/// before the anchor - well-defined mathematically, but not real charges.
public func billingDate(occurrence occurrenceIndex: Int, anchor: CalendarDay, cycle: BillingCycle) -> CalendarDay {
    switch cycle.unit {
    case .day:
        // Day and week cycles are plain arithmetic: no anchor day, no clamping
        // (spec §4.2 rule 5).
        return anchor.adding(days: occurrenceIndex * cycle.interval)
    case .week:
        return anchor.adding(days: occurrenceIndex * cycle.interval * 7)
    case .month:
        return monthAnchoredDate(monthsAfterAnchor: occurrenceIndex * cycle.interval, anchor: anchor)
    case .year:
        // A year is 12 month-intervals, so Feb 29 anchors inherit the clamp for free:
        // Feb 28 in common years, Feb 29 in leap years (spec §4.2 rule 4).
        return monthAnchoredDate(monthsAfterAnchor: occurrenceIndex * cycle.interval * 12, anchor: anchor)
    }
}

/// Advances whole months from the anchor, then clamps the day - the Stripe rule.
private func monthAnchoredDate(monthsAfterAnchor: Int, anchor: CalendarDay) -> CalendarDay {
    // Months counted continuously from year zero make the year/month split plain division.
    let anchorMonthCount = anchor.year * 12 + (anchor.month - 1)
    let targetMonthCount = anchorMonthCount + monthsAfterAnchor
    let targetYear = targetMonthCount / 12
    let targetMonth = targetMonthCount % 12 + 1

    // The clamp, without drift: the day always starts over from the ANCHOR's day, so
    // a short month pulls one occurrence back without pulling later occurrences with it.
    let clampedDay = min(anchor.day, CalendarDay.daysIn(month: targetMonth, year: targetYear))
    return CalendarDay(validYear: targetYear, validMonth: targetMonth, validDay: clampedDay)
}

/// The first billing date strictly after `today`, computed directly from the anchor.
///
/// When the anchor itself is still ahead of `today` - a subscription entered before
/// its first charge - the anchor is the answer.
public func nextBillingDate(after today: CalendarDay, anchor: CalendarDay, cycle: BillingCycle) -> CalendarDay {
    billingDate(
        occurrence: firstOccurrenceIndex(after: today, anchor: anchor, cycle: cycle),
        anchor: anchor,
        cycle: cycle
    )
}

/// The occurrence index of the first billing date strictly after `today`. Never below
/// 0, because occurrences before the anchor are not real charges.
func firstOccurrenceIndex(after today: CalendarDay, anchor: CalendarDay, cycle: BillingCycle) -> Int {
    switch cycle.unit {
    case .day, .week:
        let daysPerCycle = cycle.unit == .week ? cycle.interval * 7 : cycle.interval
        let daysPastAnchor = anchor.days(until: today)
        guard daysPastAnchor >= 0 else { return 0 }
        // Both operands are non-negative, so the division floors: it yields the last
        // occurrence on or before today, and one past that is the answer.
        return daysPastAnchor / daysPerCycle + 1
    case .month, .year:
        let monthsPerCycle = cycle.unit == .year ? cycle.interval * 12 : cycle.interval
        let monthsPastAnchor = (today.year - anchor.year) * 12 + (today.month - anchor.month)
        // Month arithmetic alone cannot settle same-month day comparisons (the clamp
        // moves a date within its month, never across months), so start one full cycle
        // low - provably at or below the answer - and walk up the 1-3 candidates,
        // each computed directly from the anchor.
        var candidate = max(0, monthsPastAnchor / monthsPerCycle - 1)
        while billingDate(occurrence: candidate, anchor: anchor, cycle: cycle) <= today {
            candidate += 1
        }
        return candidate
    }
}

/// Derives the billing anchor for a subscription entered as "I know my next charge"
/// (spec §5.1, mode B) - the entry mode most long-held subscriptions need, because
/// their true start date is unknowable.
///
/// The entered date IS the anchor: it is a real billing occurrence, and anchoring the
/// sequence there (occurrence 0) reproduces it exactly. Nothing cleverer is possible.
/// Stepping one cycle backwards from Mar 31 monthly would manufacture a Feb 28 anchor
/// that bills the 28th forever after, and a Feb 28 next-charge date cannot reveal
/// whether the vendor's true anchor is the 28th, 30th, or 31st - that information is
/// simply not present in the input. `cycle` is part of the signature because it is
/// part of the question being asked; every unit currently derives the same way.
public func anchor(fromNextBillingDate nextBillingDate: CalendarDay, cycle: BillingCycle) -> CalendarDay {
    nextBillingDate
}
