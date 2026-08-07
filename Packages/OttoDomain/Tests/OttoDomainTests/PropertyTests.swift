import Testing
import OttoDomain

/// Every month- and year-based cadence the app will realistically see.
private let monthAndYearCycles: [BillingCycle] = [.monthly, .quarterly, .semiannual, .annual]
    + [BillingCycle(unit: .month, interval: 2), BillingCycle(unit: .year, interval: 2)].compactMap { $0 }

// The property test spec §4.4 requires: advancing N occurrences and computing back
// must recover the original anchor day. "Computing back" is encoded three ways, because
// the engine's whole design is that dates are functions of (anchor, occurrence index):
//   1. occurrence 0 recomputed after any advance is exactly the anchor;
//   2. the month arithmetic reverses exactly (N intervals forward is N intervals back);
//   3. the anchor day is never lost to a clamp - every landing day is
//      min(anchorDay, days in the landing month), so months long enough to hold the
//      anchor day always recover it.
// An implementation that iterated from computed dates would fail 3 on the first
// February and fail 1 forever after.
@Suite("Anchor round-trip property (spec §4.4)")
struct PropertyTests {

    @Test("any anchor day, any month/year cycle, any N in 1-60 round-trips", arguments: 1...31, monthAndYearCycles)
    func anchorRoundTrip(anchorDayOfMonth: Int, cycle: BillingCycle) throws {
        // January 2026 has 31 days, so every anchor day 1-31 is constructible.
        let anchorDate = try day(2026, 1, anchorDayOfMonth)
        let intervalInMonths = cycle.unit == .year ? cycle.interval * 12 : cycle.interval

        #expect(billingDate(occurrence: 0, anchor: anchorDate, cycle: cycle) == anchorDate)

        for occurrenceIndex in 1...60 {
            let advanced = billingDate(occurrence: occurrenceIndex, anchor: anchorDate, cycle: cycle)

            let capacity = CalendarDay.daysIn(month: advanced.month, year: advanced.year)
            #expect(
                advanced.day == min(anchorDayOfMonth, capacity),
                "occurrence \(occurrenceIndex) of day-\(anchorDayOfMonth) \(cycle.interval)-\(cycle.unit) landed on \(advanced)"
            )

            let monthsAdvanced = (advanced.year - anchorDate.year) * 12 + (advanced.month - anchorDate.month)
            #expect(monthsAdvanced == occurrenceIndex * intervalInMonths)

            #expect(billingDate(occurrence: 0, anchor: anchorDate, cycle: cycle) == anchorDate)

            // And mode-B derivation from any occurrence reproduces that occurrence.
            let derivedAnchor = anchor(fromNextBillingDate: advanced, cycle: cycle)
            let dayBefore = advanced.adding(days: -1)
            #expect(nextBillingDate(after: dayBefore, anchor: derivedAnchor, cycle: cycle) == advanced)
        }
    }
}
