import Foundation
import Testing
@testable import OttoDomain

// Spec §5.3 (v1.4): "Keeping it" writes `acknowledgedAt` on the charge's ledger
// row, and the PLANNER skips reminders for acknowledged events - so the silencing
// is a property of every plan, not of one notification-center mutation, and a
// cancel-all-then-replan reschedule cannot replant what it never plans.
@Suite("Acknowledged charges silence their reminders in the plan (spec §5.3, v1.4)")
struct AcknowledgedChargeTests {

    @Test("an acknowledged renewal charge plans no lead and no same-day reminder; the next cycle plans normally")
    func acknowledgedRenewalSilencedThisCycleOnly() throws {
        let subscription = try makeSubscription(
            status: .active, cycleStartDay: try day(2026, 1, 15), sameDayReminder: true
        )
        let today = try day(2026, 8, 6)

        let plan = reminderSchedule(
            for: subscription,
            acknowledgedChargeDays: [try day(2026, 8, 15)],
            from: today, horizonDays: 60
        )

        let renewalDays = plan
            .filter { $0.kind == .renewal || $0.kind == .renewalDayOf }
            .map(\.day)
        // Aug 15's lead (Aug 12) and same-day rows are gone; Sep 15's and Oct 15's
        // remain untouched.
        #expect(!renewalDays.contains(try day(2026, 8, 12)))
        #expect(!renewalDays.contains(try day(2026, 8, 15)))
        #expect(renewalDays.contains(try day(2026, 9, 12)))
        #expect(renewalDays.contains(try day(2026, 9, 15)))
    }

    @Test("an acknowledged charge gets no catch-up either - silenced means silenced")
    func acknowledgedChargeGetsNoCatchUp() throws {
        // Added today with the charge two days out: the 3-day lead is already
        // past, which is exactly the §6.2 catch-up case - unless acknowledged.
        let subscription = try makeSubscription(status: .active, cycleStartDay: try day(2026, 8, 8))
        let today = try day(2026, 8, 6)

        let unacknowledged = reminderSchedule(for: subscription, from: today, horizonDays: 90)
        #expect(unacknowledged.contains { $0.kind == .renewal && $0.day == today })

        let acknowledged = reminderSchedule(
            for: subscription,
            acknowledgedChargeDays: [try day(2026, 8, 8)],
            from: today, horizonDays: 90
        )
        #expect(!acknowledged.contains { $0.kind == .renewal && $0.day == today })
    }

    @Test("with a lead longer than the cycle, the catch-up moves past an acknowledged charge to the next un-warned one")
    func catchUpSkipsAcknowledgedToNextCharge() throws {
        // 45-day lead on a monthly cycle: several lead days are in the past at
        // once. The earliest un-warned charge is Aug 15 - but the user already
        // said "Keeping it" for it, so the one catch-up warns about Sep 15.
        let subscription = try makeSubscription(
            status: .active, cycleStartDay: try day(2026, 1, 15), reminderLeadDays: 45
        )
        let today = try day(2026, 8, 6)

        let plan = reminderSchedule(
            for: subscription,
            acknowledgedChargeDays: [try day(2026, 8, 15)],
            from: today, horizonDays: 90
        )

        let catchUps = plan.filter { $0.kind == .renewal && $0.day == today }
        #expect(catchUps.count == 1)
        // Sep 15's own lead day (Aug 1) is also past, so the catch-up is its
        // reminder; Oct 15's lead (Aug 31) is ahead and plans normally.
        let octoberLeadDay = try day(2026, 8, 31)
        #expect(plan.contains { $0.kind == .renewal && $0.day == octoberLeadDay })
    }

    @Test("an acknowledged trial keeps ONLY the conversion announcement - the escalation is waived, the fact is not")
    func acknowledgedTrialKeepsAnnouncementOnly() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 27), lengthDays: 14)
        let subscription = try makeSubscription(
            status: .trial, cycleStartDay: try day(2026, 7, 27), reminderLeadDays: 5, trial: trial
        )
        let today = try day(2026, 8, 1)

        let plan = reminderSchedule(
            for: subscription,
            acknowledgedChargeDays: [trial.conversionDate],
            from: today, horizonDays: 90
        )

        #expect(plan.map(\.kind) == [.conversionAnnouncement])
        #expect(plan.map(\.day) == [trial.conversionDate])
    }

    @Test("equal inputs with equal acknowledgements produce identical plans - the silencing is deterministic")
    func acknowledgedPlanningIsDeterministic() throws {
        let subscription = try makeSubscription(
            status: .active, cycleStartDay: try day(2026, 1, 15), sameDayReminder: true
        )
        let today = try day(2026, 8, 6)
        let acknowledged: Set<CalendarDay> = [try day(2026, 8, 15)]

        let first = reminderSchedule(
            for: subscription, acknowledgedChargeDays: acknowledged, from: today, horizonDays: 90
        )
        let second = reminderSchedule(
            for: subscription, acknowledgedChargeDays: acknowledged, from: today, horizonDays: 90
        )
        #expect(first == second)
    }
}

// Spec §5.3: which charges the effective status expects, and which ledger rows it
// still stands behind - the decisions the persistence layer materializes and
// invalidates by, moved into the domain in the v1.4 reconciliation.
@Suite("Expected charges (spec §5.3, §5.2a)")
struct ExpectedChargeTests {

    @Test("an active subscription expects its anchored sequence at its amount, today included")
    func activeSequence() throws {
        let subscription = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 31))
        let charges = expectedCharges(
            for: subscription, from: try day(2026, 8, 31), through: try day(2026, 10, 31)
        )
        #expect(charges.map(\.day) == [try day(2026, 8, 31), try day(2026, 9, 30), try day(2026, 10, 31)])
        #expect(charges.allSatisfy { $0.amountCents == subscription.amountCents })
    }

    @Test("an unconverted trial expects exactly one charge: the conversion, at the converted amount")
    func trialExpectsConversionOnly() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 1), lengthDays: 14, convertsToAmountCents: 1599)
        let subscription = try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial)
        let charges = expectedCharges(
            for: subscription, from: try day(2026, 8, 6), through: try day(2026, 11, 6)
        )
        #expect(charges == [ExpectedCharge(day: trial.conversionDate, amountCents: 1599)])
    }

    @Test("a converted trial expects the paid sequence from the conversion anchor (spec §5.2a)")
    func convertedTrialExpectsPaidSequence() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 6), lengthDays: 7, convertsToAmountCents: 1100)
        let subscription = try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 6), trial: trial)
        let charges = expectedCharges(
            for: subscription, from: try day(2026, 9, 1), through: try day(2026, 11, 30)
        )
        #expect(charges.map(\.day) == [try day(2026, 9, 13), try day(2026, 10, 13), try day(2026, 11, 13)])
        #expect(charges.allSatisfy { $0.amountCents == 1100 })
    }

    @Test(
        "non-expecting statuses expect nothing, and stand behind no .upcoming row (v1.4)",
        arguments: [SubscriptionStatus.paused, .cancellationPending, .cancelled, .archived]
    )
    func nonExpectingStatuses(status: SubscriptionStatus) throws {
        let subscription = try makeSubscription(status: status, cycleStartDay: try day(2026, 1, 15))
        let today = try day(2026, 8, 6)
        #expect(expectedCharges(for: subscription, from: today, through: today.adding(days: 90)).isEmpty)
        // Even a row that WOULD match the sequence is no longer expected: the
        // status transition invalidates it (spec §5.3, v1.4).
        #expect(!isExpectedCharge(
            day: try day(2026, 8, 15), amountCents: subscription.amountCents,
            for: subscription, asOf: today
        ))
    }

    @Test("isExpectedCharge accepts exactly the sequence's (date, amount) pairs for an active subscription")
    func membershipMatchesSequence() throws {
        let subscription = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 31))
        let today = try day(2026, 8, 6)
        #expect(isExpectedCharge(
            day: try day(2026, 8, 31), amountCents: subscription.amountCents, for: subscription, asOf: today
        ))
        #expect(!isExpectedCharge(
            day: try day(2026, 8, 30), amountCents: subscription.amountCents, for: subscription, asOf: today
        ))
        #expect(!isExpectedCharge(
            day: try day(2026, 8, 31), amountCents: subscription.amountCents + 1, for: subscription, asOf: today
        ))
    }
}

// Spec §6.2 (v1.4): Add/Edit warns when the reminder lead is at least a whole
// cycle - the configuration where every reminder is about the charge after next.
@Suite("Lead-time sanity (spec §6.2, v1.4)")
struct LeadTimeCoverageTests {

    @Test("the warning threshold is the average cycle length")
    func thresholds() throws {
        #expect(BillingCycle.monthly.isCovered(byLeadDays: 31))
        #expect(!BillingCycle.monthly.isCovered(byLeadDays: 30))
        #expect(BillingCycle.weekly.isCovered(byLeadDays: 7))
        #expect(!BillingCycle.weekly.isCovered(byLeadDays: 6))
        #expect(!BillingCycle.annual.isCovered(byLeadDays: 365))
        #expect(BillingCycle.annual.isCovered(byLeadDays: 366))
        let fortyFiveDays = try #require(BillingCycle(unit: .day, interval: 45))
        #expect(fortyFiveDays.isCovered(byLeadDays: 45))
        #expect(!fortyFiveDays.isCovered(byLeadDays: 44))
    }
}
