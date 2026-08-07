import Testing
import OttoDomain

// Drift is the silent bug (spec §4.2 rule 3): iterating by adding an interval to the
// previously computed date turns one February clamp into a 28th-of-the-month
// subscription forever. These tests walk long sequences to prove that never happens.
@Suite("No drift (spec §4.2)")
struct NoDriftTests {

    @Test("Mar 15 monthly stays on the 15th for 24 occurrences")
    func mar15MonthlyNeverDrifts() throws {
        let anchorDate = try day(2026, 3, 15)
        for occurrence in 1...24 {
            let billed = billingDate(occurrence: occurrence, anchor: anchorDate, cycle: .monthly)
            #expect(billed.day == 15, "occurrence \(occurrence) landed on \(billed)")
            let monthsAdvanced = (billed.year - 2026) * 12 + (billed.month - 3)
            #expect(monthsAdvanced == occurrence, "occurrence \(occurrence) skipped to \(billed)")
        }
    }

    @Test("Jan 31 monthly returns to the 31st in every 31-day month across 36 occurrences")
    func jan31MonthlyReturnsToThe31st() throws {
        let anchorDate = try day(2026, 1, 31)
        for occurrence in 1...36 {
            let billed = billingDate(occurrence: occurrence, anchor: anchorDate, cycle: .monthly)
            let capacity = CalendarDay.daysIn(month: billed.month, year: billed.year)
            // Clamped to exactly what the month holds - so every 31-day month is the
            // 31st, and a February clamp never propagates into March.
            #expect(billed.day == min(31, capacity), "occurrence \(occurrence) landed on \(billed)")
            let monthsAdvanced = (billed.year - 2026) * 12 + (billed.month - 1)
            #expect(monthsAdvanced == occurrence, "occurrence \(occurrence) skipped to \(billed)")
        }
    }
}
