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
        // And says it was DELIBERATE (round 5, item 9): the implausible-day
        // subset is what lets the gap card stop describing this silencing as
        // a transient failure.
        #expect(outcome.implausibleDayFailures == [corrupt.id])
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
        #expect(outcome.implausibleDayFailures.isEmpty)
        #expect(outcome.canClaimCoverage)
        #expect(outcome.coveredThrough == today.adding(days: 90))
    }

    /// Round 5, item 9: the two failure kinds stay distinguishable through the
    /// outcome. A transient materialization failure and a deliberate
    /// implausible-day silencing in ONE pass - the mixed shape the gap card's
    /// third wording exists for - must land as two `ledgerFailures` with
    /// exactly one of them in `implausibleDayFailures`, or the card upstream
    /// cannot tell "wait, it will retry" apart from "repair the dates".
    @Test("⛔ a transient ledger failure is never reported as an implausible-day silencing")
    func transientFailureIsNotMarkedImplausible() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, subscriptions, events) = (fixture.scheduler, fixture.subscriptions, fixture.billingEvents)
        let today = try day(2026, 8, 11)
        let corrupt = try makeSubscription(index: 1, cycleStartDay: try eraNumberedAnchor())
        let transient = try makeSubscription(index: 2, name: "Transient", cycleStartDay: try day(2026, 8, 6))
        try await subscriptions.seed([corrupt, transient])
        await events.failMaterialize(forSubscription: transient.id)

        let outcome = try await scheduler.reschedule(
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )

        #expect(Set(outcome.ledgerFailures) == Set([corrupt.id, transient.id]))
        #expect(outcome.implausibleDayFailures == [corrupt.id])
        #expect(outcome.canClaimCoverage == false)
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
        // Round 5, item 2 changed this expectation from 4 to 0, by decision,
        // not by test drift: before the planner guard, a behind-offset anchor
        // was projected forward into four reminders on days that are not the
        // subscription's dates (measured at `bb0c0f9`: 9-3, 9-16, 10-3, 11-3
        // for this anchor, against a healthy control's 9-3, 10-3, 11-3, 11-4).
        // N4-2 recorded that no round had decided whether it should; round 5
        // decided it should not. Detected corruption now plans nothing on any
        // calendar, and this pass's failure report is what tells Today so.
        #expect(outcome.scheduledCount == 0)
    }

    /// Round 5, item 2: the device-visible half of the planner guard. The
    /// Indian test above pins the outcome fields; this pins the notification
    /// center - no request is pending for a behind-offset anchor, where before
    /// the guard four wrong-day requests were (measured at `bb0c0f9` for all
    /// seven behind-offset families, four each).
    @Test("⛔ a behind-offset anchor leaves nothing pending on the device")
    func negativeOffsetAnchorSchedulesNothing() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 11)
        let corrupt = try makeSubscription(index: 1, cycleStartDay: try day(1448, 8, 6))
        try await subscriptions.seed([corrupt])

        let outcome = try await scheduler.reschedule(
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )

        #expect(outcome.scheduledCount == 0)
        #expect(await client.pendingRequests().isEmpty)
        #expect(outcome.ledgerFailures == [corrupt.id])
        #expect(outcome.canClaimCoverage == false)
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
