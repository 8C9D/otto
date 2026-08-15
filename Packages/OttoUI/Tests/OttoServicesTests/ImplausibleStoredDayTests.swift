import Foundation
import OttoDomain
import Testing
@testable import OttoServices

/// R0-7 / N2-2, at the level where the harm actually happens.
///
/// The defect measured at HEAD, before this guard existed: a subscription whose
/// stored anchor is era-numbered - what a pre-F1 build wrote on a Buddhist
/// device - plans nothing, because every stored date is ~543 years beyond the
/// 90-day horizon, and the pass returns an outcome IDENTICAL on every field
/// Today reads to one that scheduled four reminders.
///
/// ```
/// PROBE   scheduledCount=0 pending=0 ledgerFailures=0 canClaimCoverage=true coveredThrough=2026-11-09
/// CONTROL scheduledCount=4              ledgerFailures=0 canClaimCoverage=true coveredThrough=2026-11-09
/// ```
///
/// `scheduledCount` is not on Today. `canClaimCoverage` and `coveredThrough`
/// are, and they agreed. This suite pins the two halves of the fix: the failing
/// device now reports a failure, and the healthy one is untouched.
@Suite("A stored day no calendar could have meant (R0-7 / N2-2)")
struct ImplausibleStoredDayTests {

    /// What a pre-F1 build wrote on a Buddhist device for "6 Aug 2026".
    private func eraNumberedAnchor() throws -> CalendarDay { try day(2569, 8, 6) }

    @Test("⛔ a pass over an era-numbered anchor can no longer claim coverage")
    func coverageIsNotClaimed() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 11)
        let corrupt = try makeSubscription(index: 1, cycleStartDay: try eraNumberedAnchor())
        try await subscriptions.seed([corrupt])

        let outcome = try await scheduler.reschedule(
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )

        // Still nothing scheduled - the fix does not repair the day, and
        // claiming otherwise would be the dishonesty this exists to remove.
        #expect(outcome.scheduledCount == 0)
        #expect(await client.pendingRequests().isEmpty)
        // What changed: the pass says so.
        #expect(outcome.ledgerFailures == [corrupt.id])
        #expect(outcome.canClaimCoverage == false)
    }

    @Test("a healthy subscription is completely untouched by the check")
    func healthyDeviceIsUnaffected() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 11)
        try await subscriptions.seed([
            try makeSubscription(index: 2, cycleStartDay: try day(2026, 8, 6))
        ])

        let outcome = try await scheduler.reschedule(
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )

        #expect(outcome.scheduledCount == 4)
        #expect(await client.pendingRequests().count == 4)
        #expect(outcome.ledgerFailures.isEmpty)
        #expect(outcome.canClaimCoverage)
        #expect(outcome.coveredThrough == today.adding(days: 90))
    }

    /// ⛔ N3-1. Indian/Saka was the second of the two calendars round 3 recorded
    /// as unreachable, and it is the more dangerous one: its anchor is in the
    /// PAST, so unlike the Buddhist case the planner projects it forward and
    /// schedules real reminders on the wrong days.
    ///
    /// Measured at `abef4a7`, before the asymmetric window, driving the real
    /// scheduler over the day a pre-F1 build stored on an Indian device for
    /// Gregorian 2026-08-06:
    ///
    /// ```
    /// indian(-78)     scheduled=4 ledgerFailures=0 canClaimCoverage=true
    ///                 fireDays=[2026-8-12, 2026-9-12, 2026-9-23, 2026-10-12]
    /// healthy control scheduled=4 ledgerFailures=0 canClaimCoverage=true
    ///                 fireDays=[2026-9-3, 2026-10-3, 2026-11-3, 2026-11-4]
    /// ```
    ///
    /// Four reminders, on the 12th instead of the 3rd, with the pass reporting
    /// itself healthy on every field Today reads.
    @Test("⛔ an Indian-written anchor can no longer claim coverage either")
    func indianAnchorWithdrawsTheCoverageClaim() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, subscriptions) = (fixture.scheduler, fixture.subscriptions)
        let today = try day(2026, 8, 11)
        let corrupt = try makeSubscription(index: 1, cycleStartDay: try day(1948, 5, 15))
        try await subscriptions.seed([corrupt])

        let outcome = try await scheduler.reschedule(
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )

        #expect(outcome.ledgerFailures == [corrupt.id])
        #expect(outcome.canClaimCoverage == false)
        // Stated rather than implied: this does NOT stop the wrong-day
        // reminders. The anchor is in the past, so the planner still produces
        // rungs from it, and the pass still schedules them - what changed is
        // that Today no longer says the schedule is complete. The same is true
        // of every negative-offset calendar and was true at round 3's HEAD;
        // `PROD-READINESS-4.md` N4-2 records it.
        #expect(outcome.scheduledCount == 4)
    }

    @Test("⛔ one corrupt subscription does not silence the healthy ones beside it")
    func theOthersStillSchedule() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 11)
        let corrupt = try makeSubscription(index: 1, cycleStartDay: try eraNumberedAnchor())
        let healthy = try makeSubscription(index: 2, name: "Healthy", cycleStartDay: try day(2026, 8, 6))
        try await subscriptions.seed([corrupt, healthy])

        let outcome = try await scheduler.reschedule(
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )

        // The §5.3 rule the ledger loop already follows: one broken record must
        // not take the other 199 subscriptions' reminders with it.
        #expect(outcome.ledgerFailures == [corrupt.id])
        #expect(outcome.scheduledCount == 4)
        let pending = await client.pendingRequests()
        #expect(pending.allSatisfy { $0.identifier.contains(healthy.id.uuidString) })
        #expect(!pending.isEmpty)
    }

    @Test("⛔ the ledger is not asked to materialize from a corrupt anchor at all")
    func theLedgerIsNotTouched() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, subscriptions, events) = (fixture.scheduler, fixture.subscriptions, fixture.billingEvents)
        let today = try day(2026, 8, 11)
        let corrupt = try makeSubscription(index: 1, cycleStartDay: try eraNumberedAnchor())
        let healthy = try makeSubscription(index: 2, name: "Healthy", cycleStartDay: try day(2026, 8, 6))
        try await subscriptions.seed([corrupt, healthy])

        _ = try await scheduler.reschedule(
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )

        // The CALL, not its result. An earlier version of this test asserted
        // that no rows and no watermark exist afterwards, and that was true
        // with the fix reverted too - a 2569 anchor produces no charges in a
        // 2026 window either way, and the fake's `materializeEvents` never
        // advances a watermark. It passed for the wrong reason and proved
        // nothing. What the fix actually changes is that the corrupt record
        // never reaches the ledger, while the healthy one beside it does.
        #expect(await events.materializeCalls == [healthy.id])
        #expect(await events.invalidateCalls == [healthy.id])
    }
}
