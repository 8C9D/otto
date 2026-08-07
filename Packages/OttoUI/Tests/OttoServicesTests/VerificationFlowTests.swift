import Foundation
import OttoDomain
import Testing
@testable import OttoServices

// The verification flow (spec §5.4) end to end against the fakes: the yes and no
// answers, the scheduler-owned roll-forward, and the converted-trial
// confirmation - every transition run twice to prove it equals running it once.

@Suite("The verification flow (spec §5.4)")
struct VerificationFlowTests {

    private struct World {
        let fixture: SchedulerFixture
        let subscription: Subscription
        let today: CalendarDay
        let now: Date
    }

    /// A cancelled subscription watching Aug 15, answered on Aug 15.
    private func seededWorld() async throws -> World {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(
            index: 1, status: .cancelled, cycleStartDay: try day(2026, 1, 15)
        )
        await fixture.subscriptions.seed([subscription])
        await fixture.cancellations.seed([CancellationEpisode(
            id: try fixtureUUID(600),
            subscriptionID: subscription.id,
            markedCancelledAt: Date(timeIntervalSince1970: 4_000),
            nextChargeDateIfNotCancelled: try day(2026, 8, 15),
            verificationState: .pending,
            evidenceNote: "Confirmation: 4821",
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )])
        let today = try day(2026, 8, 15)
        let now = try #require(Calendar.gregorianDate(
            year: 2026, month: 8, day: 15, hour: 10, in: torontoZone
        ))
        return World(fixture: fixture, subscription: subscription, today: today, now: now)
    }

    @Test("yes archives the subscription and verifies the record - twice equals once")
    func yesPathArchives() async throws {
        let world = try await seededWorld()
        let (fixture, subscription, today, now) = (world.fixture, world.subscription, world.today, world.now)
        let flows = fixture.flows

        let summary = try await flows.answerVerification(
            subscriptionID: subscription.id, chargesStopped: true, now: now, today: today
        )
        #expect(summary == nil)
        // Verification passing is also the episode's end (spec §5.3a): it is
        // closed now, so the open-episode read is empty and history holds it.
        #expect(try await fixture.cancellations.openEpisode(forSubscription: subscription.id) == nil)
        let record = try await fixture.cancellations.episodes(forSubscription: subscription.id).first
        #expect(record?.verifiedAt == now)
        #expect(record?.endedAt == now)
        #expect(record?.outcome == .verifiedStopped)
        #expect(try await fixture.subscriptions.subscription(withID: subscription.id)?.storedStatus == .archived)

        // Redelivery: same state, first instant kept.
        _ = try await flows.answerVerification(
            subscriptionID: subscription.id, chargesStopped: true,
            now: now.addingTimeInterval(600), today: today
        )
        #expect(try await fixture.cancellations.episodes(forSubscription: subscription.id).first == record)

        // An archived subscription plans nothing and its rows are invalidated on
        // the next pass (spec §5.3, v1.4).
        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        #expect(await fixture.client.pendingRequests().isEmpty)
    }

    @Test("no creates exactly ONE .unexpectedCharge - the state's only producer - and populates the dispute")
    func noPathCreatesOneUnexpectedCharge() async throws {
        let world = try await seededWorld()
        let (fixture, subscription, today, now) = (world.fixture, world.subscription, world.today, world.now)
        let flows = fixture.flows

        let summary = try #require(try await flows.answerVerification(
            subscriptionID: subscription.id, chargesStopped: false, now: now, today: today
        ))
        #expect(summary.subscriptionName == subscription.name)
        #expect(summary.markedCancelledAt == Date(timeIntervalSince1970: 4_000))
        #expect(summary.evidenceNote == "Confirmation: 4821")
        #expect(summary.chargeDate == (try day(2026, 8, 15)))
        #expect(summary.chargeAmountCents == subscription.amountCents)
        #expect(summary.currencyCode == "CAD")

        let record = try await fixture.cancellations.openEpisode(forSubscription: subscription.id)
        #expect(record?.verificationState == .stillCharging)
        // Not archived: the money did NOT stop, so the lifecycle is not over.
        #expect(try await fixture.subscriptions.subscription(withID: subscription.id)?.storedStatus == .cancelled)

        // Twice equals once: still exactly one retrospective row.
        _ = try await flows.answerVerification(
            subscriptionID: subscription.id, chargesStopped: false,
            now: now.addingTimeInterval(600), today: today
        )
        let unexpected = try await fixture.billingEvents.events(forSubscription: subscription.id)
            .filter { $0.state == .unexpectedCharge }
        #expect(unexpected.count == 1)
        #expect(unexpected.first?.expectedDate == (try day(2026, 8, 15)))
        #expect(unexpected.first?.expectedAmountCents == subscription.amountCents)

        // A resolved record schedules no further checks.
        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        #expect(await fixture.client.pendingRequests().isEmpty)
    }

    @Test("a price edited after cancellation cannot corrupt the dispute (spec §5.4, v1.5)")
    func editedPriceDoesNotCorruptDispute() async throws {
        // Cancelled at 1100; the user then hand-edits the price to 1500 before
        // the check comes due. The derivation can only see 1500 - the dispute
        // and its ledger row must both carry the 1100 stored at cancellation,
        // because that summary ends at a bank.
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await fixture.subscriptions.seed([subscription])
        let flows = fixture.flows
        _ = try await flows.startCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        )

        var edited = try #require(try await fixture.subscriptions.subscription(withID: subscription.id))
        edited.amountCents = 1500
        try await fixture.subscriptions.save(edited)

        let summary = try #require(try await flows.answerVerification(
            subscriptionID: subscription.id, chargesStopped: false,
            now: try fixtureNow(), today: try day(2026, 8, 15)
        ))
        #expect(summary.chargeAmountCents == 1100)

        let unexpected = try await fixture.billingEvents.events(forSubscription: subscription.id)
            .filter { $0.state == .unexpectedCharge }
        #expect(unexpected.first?.expectedAmountCents == 1100)
    }

    @Test("a cancelled trial's dispute carries the converted amount - the charge that would actually land")
    func trialDisputeUsesConvertedAmount() async throws {
        let fixture = SchedulerFixture()
        let trial = try makeTrialTerm(
            startDate: try day(2026, 7, 1), lengthDays: 30, convertsToAmountCents: 1599
        )
        let subscription = try makeSubscription(
            index: 1, status: .cancellationPending, cycleStartDay: try day(2026, 7, 1), trial: trial
        )
        await fixture.subscriptions.seed([subscription])
        let now = try fixtureNow()
        _ = try await fixture.flows.startCancellation(
            subscriptionID: subscription.id, now: now, today: try day(2026, 7, 20)
        )

        let summary = try #require(try await fixture.flows.answerVerification(
            subscriptionID: subscription.id, chargesStopped: false, now: now, today: try day(2026, 7, 31)
        ))
        #expect(summary.chargeDate == trial.conversionDate)
        #expect(summary.chargeAmountCents == 1599)
    }
}

@Suite("The verification roll-forward at the scheduler (spec §5.4)")
struct RollForwardSchedulingTests {

    @Test("a scheduling pass rolls unanswered checks and keeps watching the new date")
    func passRollsForward() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(
            index: 1, status: .cancelled, cycleStartDay: try day(2026, 1, 15)
        )
        await fixture.subscriptions.seed([subscription])
        await fixture.cancellations.seed([CancellationEpisode(
            id: try fixtureUUID(600),
            subscriptionID: subscription.id,
            markedCancelledAt: Date(timeIntervalSince1970: 4_000),
            nextChargeDateIfNotCancelled: try day(2026, 8, 15),
            verificationState: .pending,
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )])

        // Opened Aug 20: the Aug 15 check passed unanswered - one strike, the
        // watch moves to Sep 15, and the pending check notification moves with it.
        let now = try #require(Calendar.gregorianDate(
            year: 2026, month: 8, day: 20, hour: 8, in: torontoZone
        ))
        _ = try await fixture.scheduler.reschedule(
            now: now, today: try day(2026, 8, 20), timeZone: torontoZone
        )
        let rolled = try #require(try await fixture.cancellations.openEpisode(forSubscription: subscription.id))
        #expect(rolled.unansweredCheckCount == 1)
        #expect(rolled.nextChargeDateIfNotCancelled == (try day(2026, 9, 15)))
        let pending = await fixture.client.pendingRequests()
        #expect(pending.count == 1)
        #expect(pending.first.map { CalendarDay(year: $0.year, month: $0.month, day: $0.day) }
            == (try day(2026, 9, 15)))
    }

    @Test("at exactly three unanswered checks: .needsManualReview and NO further notifications")
    func threeStrikesStopsNotifying() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(
            index: 1, status: .cancelled, cycleStartDay: try day(2026, 1, 15)
        )
        await fixture.subscriptions.seed([subscription])
        await fixture.cancellations.seed([CancellationEpisode(
            id: try fixtureUUID(600),
            subscriptionID: subscription.id,
            markedCancelledAt: Date(timeIntervalSince1970: 4_000),
            nextChargeDateIfNotCancelled: try day(2026, 8, 15),
            verificationState: .pending,
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )])

        // A long absence: Aug 15, Sep 15, Oct 15 all passed. One pass catches
        // the whole thing up - no dependence on the app having been opened in
        // between (constraint 3).
        let now = try #require(Calendar.gregorianDate(
            year: 2026, month: 12, day: 20, hour: 8, in: torontoZone
        ))
        _ = try await fixture.scheduler.reschedule(
            now: now, today: try day(2026, 12, 20), timeZone: torontoZone
        )

        let escalated = try #require(try await fixture.cancellations.openEpisode(forSubscription: subscription.id))
        #expect(escalated.unansweredCheckCount == 3)
        #expect(escalated.verificationState == .needsManualReview)
        #expect(await fixture.client.pendingRequests().isEmpty)

        // Further passes change nothing - the escalation is the persistent Today
        // card's job now, not the notification center's.
        _ = try await fixture.scheduler.reschedule(
            now: now, today: try day(2026, 12, 21), timeZone: torontoZone
        )
        #expect(try await fixture.cancellations.openEpisode(forSubscription: subscription.id) == escalated)
        #expect(await fixture.client.pendingRequests().isEmpty)
    }
}

@Suite("Confirming a converted trial (spec §5.2a, §7.1)")
struct TrialConfirmationFlowTests {

    private struct World {
        let fixture: SchedulerFixture
        let subscription: Subscription
        let trial: TrialTerm
    }

    /// A trial that converted Aug 10; today is Aug 20 and nothing was ever tapped.
    private func seededWorld() async throws -> World {
        let fixture = SchedulerFixture()
        let trial = try makeTrialTerm(
            startDate: try day(2026, 7, 27), lengthDays: 14, convertsToAmountCents: 1599
        )
        let subscription = try makeSubscription(
            index: 1, status: .trial, amountCents: 0, cycleStartDay: try day(2026, 7, 27),
            reminderLeadDays: 5, trial: trial
        )
        await fixture.subscriptions.seed([subscription])
        return World(fixture: fixture, subscription: subscription, trial: trial)
    }

    @Test("the converted-unacknowledged card persists across relaunches until confirmed, then retires - deleting nothing")
    func cardPersistsUntilConfirmed() async throws {
        let world = try await seededWorld()
        let (fixture, subscription, trial) = (world.fixture, world.subscription, world.trial)
        let today = try day(2026, 8, 20)
        let now = try #require(Calendar.gregorianDate(
            year: 2026, month: 8, day: 20, hour: 8, in: torontoZone
        ))
        // A scheduler pass materializes the ledger - the state a relaunch reads.
        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        // "Relaunch" twice: the overview is derived purely from stored state, so
        // it says needs-action every time until someone confirms.
        for _ in 0..<2 {
            let stored = try await fixture.subscriptions.subscriptions()
            let overview = todayOverview(subscriptions: stored, cancellations: [:], from: today)
            #expect(overview.needsAction.count == 1)
            #expect(overview.needsAction.first.map {
                if case .trialConverted = $0.reason { true } else { false }
            } == true)
        }

        try await fixture.flows.confirmTrialConversion(
            subscriptionID: subscription.id, now: now, today: today
        )

        // The card retires because the stored state now says .active…
        let confirmed = try #require(try await fixture.subscriptions.subscription(withID: subscription.id))
        #expect(confirmed.storedStatus == .active)
        #expect(confirmed.cycleStartDay == trial.conversionDate)
        #expect(confirmed.amountCents == 1599)
        let overview = todayOverview(subscriptions: [confirmed], cancellations: [:], from: today)
        #expect(overview.needsAction.isEmpty)
        #expect(overview.next30Days.count + overview.later.count == 1)

        // …and confirming RECORDED, never deleted: the trial term survives, the
        // conversion ledger row survives with the acknowledgement instant, and
        // the price transition is history now.
        #expect(confirmed.trial == trial)
        let conversionEvent = try await fixture.billingEvents.events(forSubscription: subscription.id)
            .first { $0.expectedDate == trial.conversionDate }
        #expect(conversionEvent?.acknowledgedAt == now)
        let history = try await fixture.priceChanges.history(forSubscription: subscription.id)
        #expect(history.count == 1)
        #expect(history.first?.source == .trialConversion)
        #expect(history.first?.oldAmountCents == 0)
        #expect(history.first?.newAmountCents == 1599)
        #expect(history.first?.effectiveDate == trial.conversionDate)
    }

    @Test("confirming twice equals confirming once - no second price change, no lost acknowledgement")
    func confirmingIsIdempotent() async throws {
        let world = try await seededWorld()
        let (fixture, subscription) = (world.fixture, world.subscription)
        let today = try day(2026, 8, 20)
        let now = try #require(Calendar.gregorianDate(
            year: 2026, month: 8, day: 20, hour: 8, in: torontoZone
        ))
        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        try await fixture.flows.confirmTrialConversion(
            subscriptionID: subscription.id, now: now, today: today
        )
        let once = try await fixture.subscriptions.subscription(withID: subscription.id)

        try await fixture.flows.confirmTrialConversion(
            subscriptionID: subscription.id, now: now.addingTimeInterval(600), today: today
        )
        #expect(try await fixture.subscriptions.subscription(withID: subscription.id) == once)
        #expect(try await fixture.priceChanges.history(forSubscription: subscription.id).count == 1)
    }

    @Test("the schedule does not move when a conversion is confirmed - the flip persists what the derivation already did")
    func confirmationDoesNotChangeTheSchedule() async throws {
        let world = try await seededWorld()
        let (fixture, subscription) = (world.fixture, world.subscription)
        let today = try day(2026, 8, 20)
        let now = try #require(Calendar.gregorianDate(
            year: 2026, month: 8, day: 20, hour: 8, in: torontoZone
        ))

        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        let before = await fixture.client.pendingRequests().map(\.identifier).sorted()
        let eventsBefore = try await fixture.billingEvents.events(forSubscription: subscription.id)

        try await fixture.flows.confirmTrialConversion(
            subscriptionID: subscription.id, now: now, today: today
        )
        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        let after = await fixture.client.pendingRequests().map(\.identifier).sorted()
        #expect(after == before)
        // No ledger churn: every pre-confirmation row survives the flip and the
        // pass untouched, and the one addition is the retrospective conversion
        // row - the charge that happened while nothing was materializing.
        let eventsAfter = try await fixture.billingEvents.events(forSubscription: subscription.id)
        let idsBefore = Set(eventsBefore.map(\.id))
        #expect(idsBefore.isSubset(of: Set(eventsAfter.map(\.id))))
        let added = eventsAfter.filter { !idsBefore.contains($0.id) }
        #expect(added.map(\.expectedDate) == [try day(2026, 8, 10)])
        #expect(added.first?.acknowledgedAt != nil)
    }
}
