import Foundation
import Testing
import OttoDomain

@Suite("Reminder schedule (spec §6.3)")
struct ReminderScheduleTests {

    @Test("an active subscription gets a lead-time reminder per billing date plus usage check-ins")
    func activeMonthly() throws {
        let sub = try makeSubscription(status: .active, cycle: .monthly, cycleStartDay: try day(2026, 7, 15))
        let today = try day(2026, 8, 6)

        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)

        // Billing dates Aug 15, Sep 15, Oct 15 with a 3-day lead; Nov 15's reminder
        // (Nov 12) falls past the horizon end of Nov 4. The usage check-in lands
        // 90 days after the Jul 15 anchor because no use was ever recorded.
        let expected = [
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 8, 12), kind: .renewal),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 9, 12), kind: .renewal),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 10, 12), kind: .renewal),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 10, 13), kind: .usageCheckIn)
        ]
        #expect(planned == expected)
    }

    @Test("a trial gets the three-reminder ladder, all at P1")
    func trialLadder() throws {
        let start = try day(2026, 8, 6)
        let trial = try #require(TrialTerm(startDate: start, lengthDays: 7, bufferDays: 2, convertsToAmountCents: 1100))
        let sub = try makeSubscription(
            status: .trial, cycle: .monthly, cycleStartDay: start, reminderLeadDays: 5, trial: trial
        )

        let planned = reminderSchedule(for: sub, from: start, horizonDays: 90)

        // Cancel-by is Aug 11; the lead reminder lands on today itself and is kept -
        // whether today's fire time has passed is Wave 4's problem, not the planner's.
        let aug11 = try day(2026, 8, 11)
        let expected = Set([
            PlannedReminder(subscriptionID: sub.id, day: start, kind: .trialLead),
            PlannedReminder(subscriptionID: sub.id, day: aug11, kind: .trialDayOfMorning),
            PlannedReminder(subscriptionID: sub.id, day: aug11, kind: .trialDayOfEvening)
        ])
        #expect(Set(planned) == expected)
        #expect(planned.count == 3)
        #expect(planned.allSatisfy { $0.priority == .trial })
    }

    @Test("a trial whose cancel-by day has passed gets no reminders")
    func expiredTrial() throws {
        let start = try day(2026, 8, 6)
        let trial = try #require(TrialTerm(startDate: start, lengthDays: 7, bufferDays: 2, convertsToAmountCents: 1100))
        let sub = try makeSubscription(
            status: .trial, cycle: .monthly, cycleStartDay: start, reminderLeadDays: 5, trial: trial
        )

        let today = try day(2026, 8, 20)
        #expect(reminderSchedule(for: sub, from: today, horizonDays: 90).isEmpty)
    }

    @Test("a paused subscription gets only a resume warning ahead of pauseEndsOn")
    func pausedWithResumeDate() throws {
        let sub = try makeSubscription(
            status: .paused,
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            pauseEndsOn: try day(2026, 9, 1)
        )
        let today = try day(2026, 8, 6)

        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)

        let aug29 = try day(2026, 8, 29)
        #expect(planned.map(\.day) == [aug29])
        #expect(planned.map(\.kind) == [.pauseEnding])
        #expect(planned.first?.priority == .renewal)
    }

    @Test("a paused subscription with no resume date generates nothing")
    func pausedWithoutResumeDate() throws {
        let sub = try makeSubscription(status: .paused, cycle: .monthly, cycleStartDay: try day(2026, 1, 15))
        let today = try day(2026, 8, 6)
        #expect(reminderSchedule(for: sub, from: today, horizonDays: 90).isEmpty)
    }

    @Test("a pending cancellation schedules one verification check after the final charge")
    func pendingVerification() throws {
        let sub = try makeSubscription(status: .cancellationPending, cycle: .monthly, cycleStartDay: try day(2026, 5, 20))
        let record = CancellationRecord(
            subscriptionID: sub.id,
            markedCancelledAt: Date(timeIntervalSince1970: 0),
            expectedFinalChargeDate: try day(2026, 8, 20),
            verificationState: .pending
        )
        let today = try day(2026, 8, 6)

        let planned = reminderSchedule(for: sub, cancellation: record, from: today, horizonDays: 90)

        // The final legitimate charge lands Aug 20; the first date a charge would
        // have landed post-cancellation is Sep 20, and that is the check.
        let sep20 = try day(2026, 9, 20)
        #expect(planned.map(\.day) == [sep20])
        #expect(planned.map(\.kind) == [.verification])
        #expect(planned.first?.priority == .verification)
    }

    @Test("a verified cancellation generates nothing")
    func verifiedCancellation() throws {
        let sub = try makeSubscription(status: .cancelled, cycle: .monthly, cycleStartDay: try day(2026, 5, 20))
        let record = CancellationRecord(
            subscriptionID: sub.id,
            markedCancelledAt: Date(timeIntervalSince1970: 0),
            expectedFinalChargeDate: try day(2026, 8, 20),
            verificationState: .verifiedStopped
        )
        let today = try day(2026, 8, 6)
        #expect(reminderSchedule(for: sub, cancellation: record, from: today, horizonDays: 90).isEmpty)
    }

    @Test("an archived subscription generates nothing")
    func archived() throws {
        let sub = try makeSubscription(status: .archived, cycle: .monthly, cycleStartDay: try day(2026, 1, 15))
        let today = try day(2026, 8, 6)
        #expect(reminderSchedule(for: sub, from: today, horizonDays: 90).isEmpty)
    }

    @Test("kinds map to the documented priorities", arguments: PlannedReminder.Kind.allCases)
    func priorityMapping(kind: PlannedReminder.Kind) throws {
        let expected: PlannedReminder.Priority = switch kind {
        case .trialLead, .trialDayOfMorning, .trialDayOfEvening: .trial
        case .verification: .verification
        case .renewal, .pauseEnding: .renewal
        case .usageCheckIn: .usageCheckIn
        }
        let reminder = PlannedReminder(subscriptionID: try fixtureUUID(0), day: try day(2026, 8, 6), kind: kind)
        #expect(reminder.priority == expected)
    }
}
