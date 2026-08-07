import Testing
import OttoDomain

// The Mode B mitigation (spec §5.1): a next-charge date on the last day of a short
// month cannot reveal whether the vendor anchors month-end or that specific day.
// One question resolves it; this is the arithmetic behind the "last day" answer.
@Suite("Mode B last-day-of-month disambiguation (spec §5.1)")
struct ModeBDisambiguationTests {

    @Test("next charge Feb 28, monthly: the last-day answer anchors Jan 31")
    func februaryMonthly() throws {
        let anchor = lastDayOfMonthAnchor(forNextBillingDate: try day(2026, 2, 28), cycle: .monthly)
        #expect(anchor == (try day(2026, 1, 31)))
    }

    @Test("the two answers produce the sequences that diverge from March onward")
    func sequencesDiverge() throws {
        let entered = try day(2026, 2, 28)
        let lastDay = try #require(lastDayOfMonthAnchor(forNextBillingDate: entered, cycle: .monthly))

        // "Last day of the month": Feb 28 is a real occurrence, and March returns to the 31st.
        #expect(nextBillingDate(after: entered.adding(days: -1), anchor: lastDay, cycle: .monthly) == entered)
        #expect(nextBillingDate(after: entered, anchor: lastDay, cycle: .monthly) == (try day(2026, 3, 31)))

        // "Specifically the 28th": the entered date is the anchor, and March bills the 28th.
        #expect(nextBillingDate(after: entered, anchor: entered, cycle: .monthly) == (try day(2026, 3, 28)))
    }

    @Test("next charge Apr 30, monthly: the last-day answer anchors Mar 31")
    func aprilMonthly() throws {
        let anchor = lastDayOfMonthAnchor(forNextBillingDate: try day(2026, 4, 30), cycle: .monthly)
        #expect(anchor == (try day(2026, 3, 31)))
    }

    @Test("quarterly cycles step back in cycle months: Feb 28 anchors the previous Aug 31")
    func februaryQuarterly() throws {
        // The quarterly sequence through February is Aug-Nov-Feb-May; November has
        // 30 days, so the nearest 31-day cycle month is August.
        let anchor = lastDayOfMonthAnchor(forNextBillingDate: try day(2026, 2, 28), cycle: .quarterly)
        #expect(anchor == (try day(2025, 8, 31)))
        #expect(
            nextBillingDate(after: try day(2026, 2, 27), anchor: try #require(anchor), cycle: .quarterly)
                == (try day(2026, 2, 28))
        )
    }

    @Test("annual Feb 28: the last-day answer anchors Feb 29 of the nearest earlier leap year")
    func februaryAnnual() throws {
        let anchor = lastDayOfMonthAnchor(forNextBillingDate: try day(2026, 2, 28), cycle: .annual)
        #expect(anchor == (try day(2024, 2, 29)))
    }

    @Test(
        "no question when the date carries no ambiguity",
        arguments: [
            (2026, 7, 31, BillingCycle.monthly),   // last day of a 31-day month
            (2026, 1, 31, .monthly),               // ditto, January
            (2026, 8, 15, .monthly),               // mid-month
            (2026, 4, 30, .annual),                // April is 30 days in every year
            (2028, 2, 29, .annual),                // a leap-day anchor is already maximal
            (2026, 2, 28, .weekly),                // week cycles have no anchor day
            (2026, 2, 28, BillingCycle.biweekly)
        ]
    )
    func unambiguousDates(year: Int, month: Int, dayOfMonth: Int, cycle: BillingCycle) throws {
        #expect(lastDayOfMonthAnchor(forNextBillingDate: try day(year, month, dayOfMonth), cycle: cycle) == nil)
    }

    @Test("an every-45-days cycle never asks - day cycles have no anchor day")
    func dayCycle() throws {
        let cycle45 = try cycle(.day, 45)
        #expect(lastDayOfMonthAnchor(forNextBillingDate: try day(2026, 2, 28), cycle: cycle45) == nil)
    }
}
