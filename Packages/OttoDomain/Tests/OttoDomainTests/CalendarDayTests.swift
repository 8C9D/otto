import Foundation
import Testing
import OttoDomain

@Suite("The calendar every CalendarDay conversion resolves in (F1)")
struct ConversionCalendarTests {

    @Test("it is Gregorian - the era CalendarDay's own arithmetic assumes")
    func isGregorian() {
        #expect(CalendarDay.conversionCalendar.identifier == .gregorian)
    }

    @Test("its timezone autoupdates, so a user who travels still gets their own day")
    func followsTheDeviceTimeZone() {
        // `Calendar(identifier:)` alone carries a SNAPSHOT of the zone in force
        // when it was built. `Calendar.current`, which this replaced at four
        // sites, re-reads the zone on every access - so anything less than
        // autoupdating would be a behaviour change for a user who travels.
        #expect(CalendarDay.conversionCalendar.timeZone == TimeZone.autoupdatingCurrent)
    }
}

/// A raw year-month-day triple for validation tests - input that is not yet known
/// to be a real date, so it cannot be a `CalendarDay`.
struct DateTriple: Sendable, CustomTestStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    var testDescription: String { "\(year)-\(month)-\(day)" }
}

@Suite("CalendarDay")
struct CalendarDayTests {

    @Test("rejects impossible dates", arguments: [
        DateTriple(2026, 2, 29),
        DateTriple(2026, 2, 30),
        DateTriple(2026, 4, 31),
        DateTriple(2026, 13, 1),
        DateTriple(2026, 0, 1),
        DateTriple(2026, 1, 0),
        DateTriple(2026, 1, 32),
        DateTriple(0, 1, 1),
        DateTriple(1900, 2, 29),
        DateTriple(2100, 2, 29)
    ])
    func rejectsImpossibleDates(_ input: DateTriple) {
        #expect(CalendarDay(year: input.year, month: input.month, day: input.day) == nil)
    }

    @Test("accepts real dates including leap days", arguments: [
        DateTriple(2024, 2, 29),
        DateTriple(2000, 2, 29),
        DateTriple(2026, 1, 31),
        DateTriple(2026, 12, 31),
        DateTriple(1, 1, 1),
        DateTriple(9999, 12, 31)
    ])
    func acceptsRealDates(_ input: DateTriple) {
        #expect(CalendarDay(year: input.year, month: input.month, day: input.day) != nil)
    }

    @Test("knows month lengths including the century leap rules")
    func monthLengths() {
        #expect(CalendarDay.daysIn(month: 2, year: 2024) == 29)
        #expect(CalendarDay.daysIn(month: 2, year: 2026) == 28)
        #expect(CalendarDay.daysIn(month: 2, year: 1900) == 28) // divisible by 100 but not 400
        #expect(CalendarDay.daysIn(month: 2, year: 2000) == 29) // divisible by 400
        #expect(CalendarDay.daysIn(month: 4, year: 2026) == 30)
        #expect(CalendarDay.daysIn(month: 12, year: 2026) == 31)
    }

    @Test("orders by year, then month, then day")
    func ordering() throws {
        let ascending = [
            try day(2025, 12, 31),
            try day(2026, 1, 1),
            try day(2026, 1, 31),
            try day(2026, 2, 1),
            try day(2027, 1, 1)
        ]
        #expect(ascending.sorted() == ascending)
        #expect(ascending[0] < ascending[1])
        #expect(!(ascending[1] < ascending[0]))
    }

    @Test("adds days across month, year, and leap boundaries")
    func addingDays() throws {
        let dec31 = try day(2026, 12, 31)
        let jan1 = try day(2027, 1, 1)
        #expect(dec31.adding(days: 1) == jan1)
        #expect(jan1.adding(days: -1) == dec31)

        let feb28 = try day(2024, 2, 28)
        let feb29 = try day(2024, 2, 29)
        let mar1 = try day(2024, 3, 1)
        #expect(feb28.adding(days: 1) == feb29)
        #expect(feb29.adding(days: 1) == mar1)

        let aug6 = try day(2026, 8, 6)
        let aug6NextYear = try day(2027, 8, 6)
        #expect(aug6.adding(days: 365) == aug6NextYear)
        #expect(aug6.adding(days: 0) == aug6)
    }

    @Test("counts days between dates symmetrically")
    func daysBetween() throws {
        let aug6 = try day(2026, 8, 6)
        let aug13 = try day(2026, 8, 13)
        #expect(aug6.days(until: aug13) == 7)
        #expect(aug13.days(until: aug6) == -7)
        #expect(aug6.days(until: aug6) == 0)
    }

    @Test("codable round trip preserves the day")
    func codableRoundTrip() throws {
        let original = try day(2026, 8, 6)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalendarDay.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("decoding an impossible date fails instead of producing a bad value")
    func decodingImpossibleDateFails() {
        let json = Data(#"{"year":2026,"month":2,"day":30}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CalendarDay.self, from: json)
        }
    }

    @Test("converts to and from DateComponents")
    func dateComponentsRoundTrip() throws {
        let original = try day(2026, 8, 6)
        let components = original.dateComponents
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 6)
        #expect(CalendarDay(dateComponents: components) == original)

        #expect(CalendarDay(dateComponents: DateComponents(year: 2026, month: 8)) == nil)
        #expect(CalendarDay(dateComponents: DateComponents(year: 2026, month: 2, day: 30)) == nil)
    }

    @Test("fireDate resolves to the same wall-clock day and time in any timezone")
    func fireDateKeepsTheWallClockDay() throws {
        let billing = try day(2026, 2, 28)
        for zoneID in ["America/Toronto", "America/Vancouver", "Pacific/Auckland", "UTC"] {
            let zone = try #require(TimeZone(identifier: zoneID))
            let fire = try #require(billing.fireDate(hour: 9, minute: 0, in: zone))
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = zone
            let resolved = gregorian.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            #expect(resolved.year == 2026, "in \(zoneID)")
            #expect(resolved.month == 2, "in \(zoneID)")
            #expect(resolved.day == 28, "in \(zoneID)")
            #expect(resolved.hour == 9, "in \(zoneID)")
            #expect(resolved.minute == 0, "in \(zoneID)")
        }
    }
}
