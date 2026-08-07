import Testing
import OttoDomain

@Suite("Date engine edge cases")
struct DateEngineEdgeCaseTests {

    @Test("next billing date is strictly after today, even when today is a billing date")
    func nextIsStrictlyAfterToday() throws {
        let anchorDate = try day(2026, 7, 15)
        let aug15 = try day(2026, 8, 15)
        let sep15 = try day(2026, 9, 15)
        #expect(nextBillingDate(after: aug15, anchor: anchorDate, cycle: .monthly) == sep15)
        #expect(nextBillingDate(after: anchorDate, anchor: anchorDate, cycle: .monthly) == aug15)
    }

    @Test("a future anchor is itself the next billing date")
    func futureAnchor() throws {
        // A subscription entered before its first charge: the anchor is still ahead.
        let anchorDate = try day(2026, 9, 15)
        let today = try day(2026, 8, 6)
        #expect(nextBillingDate(after: today, anchor: anchorDate, cycle: .monthly) == anchorDate)
        #expect(nextBillingDate(after: today, anchor: anchorDate, cycle: .weekly) == anchorDate)
        let every45Days = try cycle(.day, 45)
        #expect(nextBillingDate(after: today, anchor: anchorDate, cycle: every45Days) == anchorDate)
    }

    @Test("next billing date lands on clamped dates, then returns to the anchor day")
    func nextLandsOnClampedDate() throws {
        let anchorDate = try day(2026, 1, 31)
        let midFebruary = try day(2026, 2, 15)
        let feb28 = try day(2026, 2, 28)
        let mar31 = try day(2026, 3, 31)
        #expect(nextBillingDate(after: midFebruary, anchor: anchorDate, cycle: .monthly) == feb28)
        #expect(nextBillingDate(after: feb28, anchor: anchorDate, cycle: .monthly) == mar31)
    }

    @Test("Dec 31 monthly wraps the year and keeps clamping from the anchor")
    func dec31Monthly() throws {
        let anchorDate = try day(2026, 12, 31)
        let expected = [
            try day(2027, 1, 31),
            try day(2027, 2, 28),
            try day(2027, 3, 31),
            try day(2027, 4, 30)
        ]
        let actual = (1...4).map { billingDate(occurrence: $0, anchor: anchorDate, cycle: .monthly) }
        #expect(actual == expected)
    }

    @Test("Feb 29 annual respects the century rule: 1900 was a common year")
    func centuryCommonYear() throws {
        let anchorDate = try day(1896, 2, 29)
        let feb28In1900 = try day(1900, 2, 28)
        let feb29In1904 = try day(1904, 2, 29)
        #expect(billingDate(occurrence: 4, anchor: anchorDate, cycle: .annual) == feb28In1900)
        #expect(billingDate(occurrence: 8, anchor: anchorDate, cycle: .annual) == feb29In1904)
    }

    @Test("biweekly billing crosses the year boundary by plain arithmetic")
    func biweeklyAcrossYearBoundary() throws {
        let anchorDate = try day(2026, 12, 21)
        let jan4 = try day(2027, 1, 4)
        let jan18 = try day(2027, 1, 18)
        #expect(billingDate(occurrence: 1, anchor: anchorDate, cycle: .biweekly) == jan4)
        #expect(billingDate(occurrence: 2, anchor: anchorDate, cycle: .biweekly) == jan18)
    }
}
