import Testing
import OttoDomain

// Expected sequences come from Stripe's documented billing behaviour (spec §4.2),
// not from what the implementation happens to do.
@Suite("Month-end clamping (spec §4.4)")
struct MonthEndClampingTests {

    @Test("Jan 31 monthly clamps short months and returns to the 31st")
    func jan31Monthly() throws {
        let anchorDate = try day(2026, 1, 31)
        let expected = [
            try day(2026, 2, 28),
            try day(2026, 3, 31),
            try day(2026, 4, 30),
            try day(2026, 5, 31),
            try day(2026, 6, 30),
            try day(2026, 7, 31)
        ]
        let actual = (1...6).map { billingDate(occurrence: $0, anchor: anchorDate, cycle: .monthly) }
        #expect(actual == expected)
    }

    @Test("Jan 31 monthly in a leap year bills Feb 29")
    func jan31MonthlyLeapYear() throws {
        let anchorDate = try day(2028, 1, 31)
        let expected = [
            try day(2028, 2, 29),
            try day(2028, 3, 31),
            try day(2028, 4, 30)
        ]
        let actual = (1...3).map { billingDate(occurrence: $0, anchor: anchorDate, cycle: .monthly) }
        #expect(actual == expected)
    }

    @Test("Jan 30 monthly clamps only February")
    func jan30Monthly() throws {
        let anchorDate = try day(2026, 1, 30)
        let expected = [
            try day(2026, 2, 28),
            try day(2026, 3, 30),
            try day(2026, 4, 30)
        ]
        let actual = (1...3).map { billingDate(occurrence: $0, anchor: anchorDate, cycle: .monthly) }
        #expect(actual == expected)
    }

    @Test("Aug 31 quarterly clamps to each landing month's end")
    func aug31Quarterly() throws {
        let anchorDate = try day(2026, 8, 31)
        let expected = [
            try day(2026, 11, 30),
            try day(2027, 2, 28),
            try day(2027, 5, 31)
        ]
        let actual = (1...3).map { billingDate(occurrence: $0, anchor: anchorDate, cycle: .quarterly) }
        #expect(actual == expected)
    }

    @Test("Aug 31 quarterly crossing a leap February bills Feb 29")
    func aug31QuarterlyLeapYear() throws {
        let anchorDate = try day(2027, 8, 31)
        let expected = [
            try day(2027, 11, 30),
            try day(2028, 2, 29),
            try day(2028, 5, 31)
        ]
        let actual = (1...3).map { billingDate(occurrence: $0, anchor: anchorDate, cycle: .quarterly) }
        #expect(actual == expected)
    }

    @Test("Feb 29 annual bills Feb 28 in common years and Feb 29 in leap years")
    func feb29Annual() throws {
        let anchorDate = try day(2024, 2, 29)
        let expected = [
            try day(2025, 2, 28),
            try day(2026, 2, 28),
            try day(2027, 2, 28),
            try day(2028, 2, 29)
        ]
        let actual = (1...4).map { billingDate(occurrence: $0, anchor: anchorDate, cycle: .annual) }
        #expect(actual == expected)
    }
}
