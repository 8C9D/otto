import Testing
import OttoDomain

// iOS silently drops pending notifications beyond 64, furthest-out first - exactly the
// annual renewals most worth warning about (spec §6.1). The budget makes the cut
// explicit, deterministic, and honest about where coverage stops.
@Suite("Slot budgeting (spec §6.1)")
struct SlotBudgetTests {

    /// The synthetic 200-subscription fixture from spec §6.1: 10 trials (a full
    /// five-rung ladder each, all P1 - §6.3's ceiling arithmetic, updated in Wave 4
    /// from the three-rung ladder Wave 1 planned) and 190 active monthly
    /// subscriptions. Deterministic throughout so failures reproduce identically.
    private func makeFixturePlan(today: CalendarDay) throws -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        for index in 0..<10 {
            let start = today.adding(days: -(index % 3))
            let trial = try makeTrialTerm(index: 400 + index, startDate: start, lengthDays: 14, convertsToAmountCents: 1099)
            let sub = try makeSubscription(
                index: index, status: .trial, cycle: .monthly, cycleStartDay: start, reminderLeadDays: 5, trial: trial
            )
            planned += reminderSchedule(for: sub, from: today, horizonDays: 90)
        }
        for index in 10..<200 {
            let anchorDate = today.adding(days: -(320 + index))
            let sub = try makeSubscription(
                index: index,
                status: .active,
                cycle: .monthly,
                cycleStartDay: anchorDate,
                lastUsedDate: today.adding(days: -1)
            )
            planned += reminderSchedule(for: sub, from: today, horizonDays: 90)
        }
        return planned
    }

    @Test("200 subscriptions budget to exactly 64 slots with every trial reminder kept")
    func budgetsTheFixtureTo64() throws {
        let today = try day(2026, 8, 6)
        let planned = try makeFixturePlan(today: today)
        #expect(planned.count > 64)

        let trialReminders = planned.filter { $0.priority == .trial }
        #expect(trialReminders.count == 10 * trialLadderCap)

        let result = budgeted(planned, limit: 64)
        #expect(result.scheduled.count == 64)

        // Every trial reminder survives - unrecoverable money always gets a slot.
        #expect(Set(result.scheduled.filter { $0.priority == .trial }) == Set(trialReminders))

        // No usage check-in outranks a renewal.
        #expect(result.scheduled.allSatisfy { $0.priority != .usageCheckIn })

        // Renewals are dropped furthest-out first: no kept renewal is further out
        // than any dropped one.
        let scheduledSet = Set(result.scheduled)
        let dropped = planned.filter { !scheduledSet.contains($0) }
        let keptRenewalDays = result.scheduled.filter { $0.kind == .renewal }.map(\.day)
        let droppedRenewalDays = dropped.filter { $0.kind == .renewal }.map(\.day)
        let furthestKept = try #require(keptRenewalDays.max())
        let nearestDropped = try #require(droppedRenewalDays.min())
        #expect(furthestKept <= nearestDropped)

        // Coverage is complete through the day before the earliest dropped reminder,
        // and truncatedAfter says exactly that.
        let earliestDropped = try #require(dropped.map(\.day).min())
        #expect(result.truncatedAfter == earliestDropped.adding(days: -1))
    }

    @Test("under the limit nothing is dropped and truncatedAfter is nil")
    func underTheLimit() throws {
        let today = try day(2026, 8, 6)
        let sub = try makeSubscription(status: .active, cycle: .monthly, cycleStartDay: try day(2026, 7, 15))
        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)
        #expect(!planned.isEmpty)

        let result = budgeted(planned, limit: 64)
        #expect(Set(result.scheduled) == Set(planned))
        #expect(result.truncatedAfter == nil)
    }

    @Test("budgeting is order-independent and deterministic")
    func deterministic() throws {
        let today = try day(2026, 8, 6)
        let planned = try makeFixturePlan(today: today)
        let first = budgeted(planned, limit: 64)
        let second = budgeted(planned.shuffled(), limit: 64)
        #expect(first.scheduled == second.scheduled)
        #expect(first.truncatedAfter == second.truncatedAfter)
    }
}
