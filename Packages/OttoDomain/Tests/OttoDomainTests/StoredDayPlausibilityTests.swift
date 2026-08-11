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

    /// Every calendar identifier this SDK declares.
    ///
    /// `Calendar.Identifier` is not `CaseIterable`, so this list is the one
    /// hand-maintained thing here - but the OFFSETS are not: each is derived by
    /// asking Foundation what that calendar writes for a fixed instant, which
    /// is exactly what a pre-F1 build did. A calendar added by a future SDK
    /// must be added here; nothing else in this file needs updating.
    private static let allIdentifiers: [(name: String, identifier: Calendar.Identifier)] = [
        ("buddhist", .buddhist), ("chinese", .chinese), ("coptic", .coptic),
        ("ethiopicAmeteMihret", .ethiopicAmeteMihret), ("ethiopicAmeteAlem", .ethiopicAmeteAlem),
        ("gregorian", .gregorian), ("hebrew", .hebrew), ("indian", .indian),
        ("islamic", .islamic), ("islamicCivil", .islamicCivil), ("islamicTabular", .islamicTabular),
        ("islamicUmmAlQura", .islamicUmmAlQura), ("iso8601", .iso8601), ("japanese", .japanese),
        ("persian", .persian), ("republicOfChina", .republicOfChina)
    ]

    /// The calendars whose stored triple this rule provably CANNOT reject,
    /// because their year offset is small enough that any window admitting an
    /// ordinary long-held subscription admits them too.
    ///
    /// Pinned as a positive assertion, not left as an omission. If a future
    /// change catches one of these, this test fails - and the right response is
    /// to update this set and the ledger, not to delete the assertion.
    private static let knownUncatchable: Set<String> = ["ethiopicAmeteMihret", "indian"]

    /// The three integers a pre-F1 build packed into `yyyymmdd`.
    private struct StoredTriple: Equatable {
        let year: Int
        let month: Int
        let dayOfMonth: Int
    }

    /// What a pre-F1 build stored for one instant under each calendar, asked of
    /// Foundation rather than recalled.
    private func storedTriple(
        under identifier: Calendar.Identifier, at instant: Date
    ) -> StoredTriple? {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else { return nil }
        return StoredTriple(year: year, month: month, dayOfMonth: dayOfMonth)
    }

    /// ⛔ The coverage of the rule, measured against Foundation on both sides.
    ///
    /// The first version of this test enumerated six era offsets in a literal -
    /// the same six the doc comment used to justify the threshold. That made
    /// the test the claim's own premise asserted back at itself: it could not
    /// fail on a calendar the list omitted, and two of the omitted ones are
    /// precisely the ones the rule does not catch. `reviews-3/REVIEW-2.md`
    /// finding 1 measured it end to end against the real scheduler.
    @Test("⛔ what the rule catches across Foundation's calendars, and what it provably cannot")
    func coverageAcrossFoundationsCalendars() throws {
        let today = try day(2026, 8, 11)
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "America/Toronto") ?? .current
        let instant = try #require(
            gregorian.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 12))
        )
        let gregorianTriple = try #require(storedTriple(under: .gregorian, at: instant))

        var missed: Set<String> = []
        var caught = 0
        for entry in Self.allIdentifiers {
            guard let triple = storedTriple(under: entry.identifier, at: instant) else { continue }
            // A calendar that writes the same numbers Gregorian does cannot
            // corrupt anything, so it is not this rule's business.
            guard triple != gregorianTriple else { continue }
            guard let stored = CalendarDay(
                year: triple.year, month: triple.month, day: triple.dayOfMonth
            ) else { continue }
            if stored.isPlausibleStoredDay(asOf: today) {
                missed.insert(entry.name)
            } else {
                caught += 1
            }
        }

        // A degenerate walk proves nothing: the loop must have reached real
        // calendars for the comparison below to mean anything.
        #expect(caught >= 10, "only \(caught) calendars were caught; the walk is not reaching them")
        #expect(
            missed == Self.knownUncatchable,
            """
            the set of calendars this rule cannot reject changed: measured \(missed.sorted()), \
            recorded \(Self.knownUncatchable.sorted()). Update this set, the doc comment on \
            plausibleStoredDayYears, and PROD-READINESS-3.md ITEM 1 together - the three must agree.
            """
        )
    }

    @Test("the two uncatchable calendars are uncatchable because no window separates them")
    func noThresholdCatchesTheTwo() throws {
        let today = try day(2026, 8, 11)
        // Ethiopic writes 2018-11-30 for Gregorian 2026-08-06 and Indian
        // writes 1948-05-15. A window narrow enough to reject either also
        // rejects an ordinary subscription anchored on that same date, which is
        // why this is a boundary of the approach and not a tuning mistake.
        for stored in [try day(2018, 11, 30), try day(1948, 5, 15)] {
            #expect(stored.isPlausibleStoredDay(asOf: today))
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

    @Test("⛔ the reported days are deduplicated and in day order")
    func reportedDaysAreDedupedAndSorted() throws {
        let today = try day(2026, 8, 11)
        // Ordinary shapes: a trial that started on the anchor, and a last-used
        // date equal to it. Both are reachable, and the result is what a
        // reader repairing the record actually sees in the log line.
        let anchor = try day(2569, 8, 6)
        let trial = try makeTrialTerm(startDate: anchor, lengthDays: 14)
        let subscription = try makeSubscription(
            status: .trial, cycleStartDay: anchor, trial: trial, lastUsedDate: anchor
        )
        let reported = subscription.implausibleStoredDays(asOf: today)

        // The anchor, the trial start and the last-used date are the same day
        // and must be named once; the derived conversion date is a second.
        #expect(reported == [try day(2569, 8, 6), try day(2569, 8, 20)])
        #expect(reported == reported.sorted())
        #expect(Set(reported).count == reported.count)
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
