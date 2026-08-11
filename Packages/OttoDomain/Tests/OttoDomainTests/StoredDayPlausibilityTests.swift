import Foundation
import Testing
@testable import OttoDomain

/// R0-7 / N2-2. F1 stopped a non-Gregorian device writing era-numbered years
/// into billing data; it repaired nothing already written, and on such a device
/// it turned a working set of reminders into no reminders at all while Today
/// went on claiming coverage.
///
/// These assertions are about the DETECTOR, not a repair. Nothing here converts
/// a day or claims to know which calendar wrote it - the store never recorded
/// that, and guessing is not acceptable on billing dates.
///
/// Unlike `CalendarEraTests`, this file is host-independent: the corruption
/// lives in the stored VALUES, so it reproduces under a Gregorian process and a
/// Gregorian CI runner exactly as it does on the device that caused it.
@Suite("Implausible stored days (R0-7 / N2-2)")
struct StoredDayPlausibilityTests {

    /// The offsets every calendar Foundation offers applies to a Gregorian
    /// year. The detector has to catch all of them; the threshold is not tuned
    /// to any one.
    private static let eraOffsets: [(name: String, offset: Int)] = [
        ("Buddhist", 543),
        ("Hebrew", 3760),
        ("Islamic", -578),
        ("Minguo / ROC", -1911),
        ("Japanese (Reiwa)", -2018),
        ("Persian", -621)
    ]

    @Test("every calendar's era offset lands outside the plausible window")
    func everyEraIsCaught() throws {
        let today = try day(2026, 8, 11)
        for era in Self.eraOffsets {
            let stored = try #require(
                CalendarDay(year: 2026 + era.offset, month: 8, day: 6),
                "\(era.name) produced an unrepresentable year"
            )
            #expect(
                !stored.isPlausibleStoredDay(asOf: today),
                "\(era.name) year \(stored.year) was accepted as a date near \(today)"
            )
        }
    }

    @Test("ordinary billing dates, including unusual ones, stay plausible")
    func realDatesSurvive() throws {
        let today = try day(2026, 8, 11)
        // A long-past import, a far-future prepaid term, and both edges of the
        // window itself. The threshold exists to catch centuries; it must never
        // second-guess a date a user could actually have entered.
        for candidate in [
            try day(1970, 1, 1),
            try day(2026, 8, 11),
            try day(2099, 12, 31),
            try day(1926, 8, 11),
            try day(2126, 8, 11)
        ] {
            #expect(
                candidate.isPlausibleStoredDay(asOf: today),
                "\(candidate) was rejected as implausible against \(today)"
            )
        }
    }

    @Test("the window is exactly a century wide on both sides")
    func windowEdges() throws {
        let today = try day(2026, 8, 11)
        #expect(try day(1925, 12, 31).isPlausibleStoredDay(asOf: today) == false)
        #expect(try day(2127, 1, 1).isPlausibleStoredDay(asOf: today) == false)
        #expect(CalendarDay.plausibleStoredDayYears == 100)
    }

    @Test("⛔ every stored day the scheduler reads is checked, not just the anchor")
    func everyScheduledFieldIsChecked() throws {
        let today = try day(2026, 8, 11)
        let era = { (year: Int) in try #require(CalendarDay(year: year, month: 8, day: 6)) }

        // The anchor.
        #expect(
            try makeSubscription(status: .active, cycleStartDay: era(2569))
                .implausibleStoredDays(asOf: today)
                == [try day(2569, 8, 6)]
        )
        // The trial's entered start, which also moves its derived conversion
        // date - both are reported, because a reader repairing this needs to
        // know the whole record is affected, not one field of it.
        let trial = try makeTrialTerm(startDate: era(2569), lengthDays: 14)
        let trialSubscription = try makeSubscription(
            status: .trial, cycleStartDay: try day(2026, 8, 6), trial: trial
        )
        #expect(
            trialSubscription.implausibleStoredDays(asOf: today)
                == [try day(2569, 8, 6), try day(2569, 8, 20)]
        )
        // A pause's scheduled resume: `pauseEndingReminders` is the only rung a
        // paused subscription gets, so a corrupt resume day silences it alone.
        #expect(
            try makeSubscription(
                status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEndsOn: era(2569)
            ).implausibleStoredDays(asOf: today) == [try day(2569, 8, 6)]
        )
        // The last recorded use: the §7.3 check-in cadence counts from it.
        #expect(
            try makeSubscription(
                status: .active, cycleStartDay: try day(2026, 8, 6), lastUsedDate: era(2569)
            ).implausibleStoredDays(asOf: today) == [try day(2569, 8, 6)]
        )
    }

    @Test("a subscription on a device that was always Gregorian reports nothing")
    func healthySubscriptionIsUntouched() throws {
        let today = try day(2026, 8, 11)
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 1), lengthDays: 14)
        let subscription = try makeSubscription(
            status: .trial,
            cycleStartDay: try day(2026, 8, 6),
            pauseEndsOn: nil,
            trial: trial,
            lastUsedDate: try day(2026, 7, 30)
        )
        #expect(subscription.implausibleStoredDays(asOf: today).isEmpty)
    }
}
