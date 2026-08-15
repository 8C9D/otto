import Foundation
import Testing
import OttoDomain

/// N4-2 (round 5, item 2): a detected-implausible stored day plans NOTHING,
/// uniformly, whichever calendar wrote it and whichever field carries it.
///
/// Before the guard, measured through the real scheduler at `bb0c0f9`, the
/// behaviour depended on the corrupting calendar's sign: Buddhist and Hebrew
/// (ahead) planned zero, while every behind-offset calendar was projected
/// forward into four reminders on days that are not the subscription's dates.
/// The decision this pins: detected corruption is silent, the ledger failure
/// and the coverage gap are the signal, and no rung fires on a wrong day.
@Suite("Implausible stored days plan nothing (N4-2)")
struct ImplausibleDayPlanningTests {

    /// What a pre-F1 build stored for Gregorian 2026-08-06, one year per
    /// detected corrupting calendar family, from the year-gap table on
    /// `plausibleStoredDayYearsBehind`.
    private static let detectedEraYears: [(family: String, year: Int)] = [
        ("buddhist", 2569), ("hebrew", 5786), ("japanese", 8),
        ("chinese", 43), ("coptic", 1742), ("islamic", 1448),
        ("persian", 1405), ("republicOfChina", 115), ("indian", 1948)
    ]

    @Test("a corrupt anchor plans nothing for every detected calendar family")
    func corruptAnchorsPlanNothing() throws {
        let today = try day(2026, 8, 11)
        for (family, year) in Self.detectedEraYears {
            let sub = try makeSubscription(
                status: .active, cycleStartDay: try day(year, 8, 6)
            )
            let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)
            #expect(planned.isEmpty, "\(family) (year \(year)) planned \(planned.count) rungs")
        }
    }

    @Test("a corrupt lastUsedDate silences the whole subscription, not just the check-in")
    func corruptLastUsedDatePlansNothing() throws {
        // Before the guard a behind-offset lastUsedDate kept the three renewal
        // rungs and added a check-in on a wrong day; an ahead-offset one kept
        // the renewals and suppressed the check-in. Both are detected, so both
        // now plan nothing: the subscription-level silence is the decision,
        // because a partially-wrong plan reads as a healthy one.
        let today = try day(2026, 8, 11)
        for lastUsed in [try day(2569, 8, 6), try day(1948, 5, 15)] {
            let sub = try makeSubscription(
                status: .active, cycleStartDay: try day(2026, 8, 6), lastUsedDate: lastUsed
            )
            #expect(reminderSchedule(for: sub, from: today, horizonDays: 90).isEmpty)
        }
    }

    @Test("a corrupt pauseEndsOn no longer un-pauses the subscription into a full plan")
    func corruptPauseResumePlansNothing() throws {
        // The sharpest pre-guard case: a behind-offset resume date derived the
        // paused subscription back to active, and it planned four rungs
        // indistinguishable from a healthy control's - measured at `bb0c0f9`.
        let today = try day(2026, 8, 11)
        let sub = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 8, 6),
            pauseEndsOn: try day(1948, 9, 1)
        )
        #expect(reminderSchedule(for: sub, from: today, horizonDays: 90).isEmpty)
    }

    @Test("the plausibility boundary itself still plans: 70 years behind is a date")
    func boundaryStillPlans() throws {
        // The guard must not reach past the rule it applies: a stored day
        // exactly at `plausibleStoredDayYearsBehind` is plausible, and an
        // Ethiopic-written day (7-8 years behind) is undetectable by design -
        // both keep planning. The Ethiopic case pins the boundary honestly:
        // its wrong-day rungs are the recorded residual, not a regression.
        let today = try day(2026, 8, 11)
        let boundary = try makeSubscription(
            status: .active, cycleStartDay: try day(1956, 8, 11)
        )
        #expect(!reminderSchedule(for: boundary, from: today, horizonDays: 90).isEmpty)
        let ethiopic = try makeSubscription(
            status: .active, cycleStartDay: try day(2018, 8, 6)
        )
        #expect(!reminderSchedule(for: ethiopic, from: today, horizonDays: 90).isEmpty)
    }
}
