import Foundation
import Testing
import OttoDomain

@Suite("Day and week cycles (spec §4.2 rule 5)")
struct OtherCycleTests {

    @Test("every 45 days from Nov 20 crosses the year boundary correctly")
    func every45DaysAcrossYearBoundary() throws {
        let anchorDate = try day(2026, 11, 20)
        let every45Days = try cycle(.day, 45)

        let jan4 = try day(2027, 1, 4)
        let feb18 = try day(2027, 2, 18)
        #expect(billingDate(occurrence: 1, anchor: anchorDate, cycle: every45Days) == jan4)
        #expect(billingDate(occurrence: 2, anchor: anchorDate, cycle: every45Days) == feb18)

        let dec25 = try day(2026, 12, 25)
        #expect(nextBillingDate(after: dec25, anchor: anchorDate, cycle: every45Days) == jan4)
    }

    @Test("weekly from a Friday is always a Friday across two DST transitions")
    func weeklyFromFridayStaysOnFriday() throws {
        // Jan 2 2026 is a Friday. Sixty weekly occurrences reach February 2027,
        // crossing the North American DST transitions on Mar 8 2026 and Nov 1 2026.
        // Weekday is verified through Foundation's calendar in a DST-observing zone,
        // independently of the domain's own day arithmetic.
        let anchorDate = try day(2026, 1, 2)
        let toronto = try #require(TimeZone(identifier: "America/Toronto"))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = toronto

        let fridayWeekdayNumber = 6 // Foundation numbers weekdays from 1 = Sunday

        for occurrence in 0...60 {
            let billed = billingDate(occurrence: occurrence, anchor: anchorDate, cycle: .weekly)
            let fire = try #require(billed.fireDate(hour: 9, minute: 0, in: toronto))
            let weekday = gregorian.component(.weekday, from: fire)
            #expect(weekday == fridayWeekdayNumber, "occurrence \(occurrence) landed on \(billed)")
        }
    }
}
