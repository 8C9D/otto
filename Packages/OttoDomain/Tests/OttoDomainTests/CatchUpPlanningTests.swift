import Foundation
import Testing
@testable import OttoDomain

// Wave 10, defect A: §6.2's catch-up planning - a rung whose instant passed
// but whose deadline is ahead stays in the plan at its ORIGINAL day, so its
// deterministic identifier is stable and the scheduler's delivered-check can
// stop a second fire.
@Suite("Catch-up planning (spec §6.2, Wave 10)")
struct CatchUpPlanningTests {
    @Test("the catch-up rule: a charge still ahead whose lead day passed keeps its rung (spec §6.2)")
    func catchUpReminder() throws {
        // The Mode B onboarding case: added two days before the charge, 3-day
        // lead. The rung keeps its ORIGINAL day (Wave 10, defect A) - a stable
        // identifier is what lets the scheduler's delivered-check stop a
        // second fire - and the scheduler delivers the passed instant
        // immediately.
        let sub = try makeSubscription(status: .active, cycle: .monthly, cycleStartDay: try day(2026, 8, 8))
        let today = try day(2026, 8, 6)

        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)

        #expect(planned.contains(
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 8, 5), kind: .renewal)
        ))
    }

    @Test("a pause ending inside the lead window still warns - immediately, not silently never")
    func pauseEndingCatchUp() throws {
        let sub = try makeSubscription(
            status: .paused,
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 5,
            pauseEndsOn: try day(2026, 8, 8)
        )
        let today = try day(2026, 8, 6)

        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)

        // At its original day (Aug 3), for the stable identifier (Wave 10);
        // the scheduler delivers the passed instant immediately.
        #expect(planned == [
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 8, 3), kind: .pauseEnding)
        ])
    }
}
