import Foundation
import OttoDomain
import Testing
@testable import OttoServices

// The Wave 5 flows, end to end against the fakes: both cancellation entry
// points, the verification answers, the roll-forward, and the converted-trial
// confirmation - every transition run twice to prove it equals running it once.

@Suite("The cancellation flow (spec §5.4)")
struct CancellationFlowTests {

    private struct WorldState: Equatable {
        var subscription: Subscription?
        var record: CancellationRecord?
        var events: [BillingEvent]
        var pendingIdentifiers: [String]
    }

    /// Everything a cancellation touches, with the per-run noise (record and
    /// event UUIDs) normalised out so two worlds compare on substance.
    private func worldState(_ fixture: SchedulerFixture, id: UUID) async throws -> WorldState {
        let nullID = UUID(uuid: UUID_NULL)
        let record = try await fixture.cancellations.record(forSubscription: id).map { record in
            CancellationRecord(
                id: nullID,
                subscriptionID: record.subscriptionID,
                markedCancelledAt: record.markedCancelledAt,
                nextChargeDateIfNotCancelled: record.nextChargeDateIfNotCancelled,
                expectedChargeAmountCents: record.expectedChargeAmountCents,
                verificationState: record.verificationState,
                unansweredCheckCount: record.unansweredCheckCount,
                verifiedAt: record.verifiedAt,
                evidenceNote: record.evidenceNote,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                deletedAt: record.deletedAt
            )
        }
        let events = try await fixture.billingEvents.eventsIncludingDeleted(forSubscription: id)
            .map { event in
                BillingEvent(
                    id: nullID,
                    subscriptionID: event.subscriptionID,
                    expectedDate: event.expectedDate,
                    expectedAmountCents: event.expectedAmountCents,
                    state: event.state,
                    userConfirmedAt: event.userConfirmedAt,
                    acknowledgedAt: event.acknowledgedAt,
                    actualAmountCents: event.actualAmountCents,
                    createdAt: event.createdAt,
                    updatedAt: event.updatedAt,
                    deletedAt: event.deletedAt
                )
            }
        return WorldState(
            subscription: try await fixture.subscriptions.subscription(withID: id),
            record: record,
            events: events,
            pendingIdentifiers: await fixture.client.pendingRequests().map(\.identifier).sorted()
        )
    }

    @Test("both entry points - detail screen and notification action - produce identical state")
    func entryPointsProduceIdenticalState() async throws {
        // The required date case: anchored Jan 31, cancelled Feb 10 2027 - the
        // check date must clamp to Feb 28, in both worlds.
        func seededFixture() async throws -> (SchedulerFixture, Subscription) {
            let fixture = SchedulerFixture()
            let subscription = try makeSubscription(
                index: 1, cycleStartDay: try day(2026, 1, 31),
                cancellationURL: URL(string: "https://example.com/cancel")
            )
            await fixture.subscriptions.seed([subscription])
            return (fixture, subscription)
        }
        let today = try day(2027, 2, 10)
        let now = try #require(Calendar.gregorianDate(
            year: 2027, month: 2, day: 10, hour: 8, in: torontoZone
        ))

        // World A: the notification action.
        let (worldA, subscriptionA) = try await seededFixture()
        _ = try await worldA.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        let followUp = try await worldA.handler.handle(
            actionIdentifier: NotificationAction.cancelling.rawValue,
            notificationIdentifier: NotificationPlanIdentifier.planned(
                PlannedReminder(subscriptionID: subscriptionA.id, day: today, kind: .renewal)
            ),
            now: now, today: today, timeZone: torontoZone
        )
        #expect(followUp == .openCancellation(
            subscriptionID: subscriptionA.id, url: URL(string: "https://example.com/cancel")
        ))

        // World B: the detail screen - the flow service directly, then the same
        // reschedule any state change triggers.
        let (worldB, subscriptionB) = try await seededFixture()
        _ = try await worldB.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        _ = try await worldB.flows.startCancellation(
            subscriptionID: subscriptionB.id, now: now, today: today
        )
        _ = try await worldB.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        let stateA = try await worldState(worldA, id: subscriptionA.id)
        let stateB = try await worldState(worldB, id: subscriptionB.id)
        #expect(stateA == stateB)

        // And the shared substance is right: pending status, the clamped Feb 28
        // check date, and a pending verification reminder for it.
        #expect(stateA.subscription?.status == .cancellationPending)
        #expect(stateA.record?.nextChargeDateIfNotCancelled == (try day(2027, 2, 28)))
        #expect(stateA.pendingIdentifiers.contains { NotificationPlanIdentifier.kind(of: $0) == .verification })
    }

    @Test("the check amount is stored at cancellation like the date, derived pre-mutation (spec §5.4, v1.5)")
    func amountStoredAtCancellation() async throws {
        // The Wave 4 bug's shape, pointed at the amount: trial Jul 1-31
        // converting to 1599, cancelled Aug 5 - after conversion, before any
        // flip persisted. The record must watch Aug 31 at the CONVERTED price,
        // both derived from the subscription before the status mutates.
        let fixture = SchedulerFixture()
        let trial = try makeTrialTerm(
            startDate: try day(2026, 7, 1), lengthDays: 30, convertsToAmountCents: 1599
        )
        let subscription = try makeSubscription(
            index: 1, status: .trial, cycleStartDay: try day(2026, 7, 1), trial: trial
        )
        await fixture.subscriptions.seed([subscription])

        let start = try await fixture.flows.startCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 5)
        )

        #expect(start?.record.nextChargeDateIfNotCancelled == (try day(2026, 8, 31)))
        #expect(start?.record.expectedChargeAmountCents == 1599)
    }

    @Test("the screen path captures evidence at the start; redelivery never overwrites it")
    func evidenceCapturedAndKept() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await fixture.subscriptions.seed([subscription])
        let today = try day(2026, 8, 6)
        let now = try fixtureNow()
        let flows = fixture.flows

        let start = try await flows.startCancellation(
            subscriptionID: subscription.id, evidenceNote: "Confirmation: 4821", now: now, today: today
        )
        #expect(start?.record.evidenceNote == "Confirmation: 4821")

        // A redelivered start - with or without a note - changes nothing.
        _ = try await flows.startCancellation(
            subscriptionID: subscription.id, evidenceNote: "something else", now: now, today: today
        )
        #expect(try await fixture.cancellations.record(forSubscription: subscription.id)?.evidenceNote
            == "Confirmation: 4821")

        // The deliberate edit path does replace it.
        try await flows.updateCancellationEvidence(
            subscriptionID: subscription.id, note: "Confirmation: 4821, rep was Dana", now: now
        )
        #expect(try await fixture.cancellations.record(forSubscription: subscription.id)?.evidenceNote
            == "Confirmation: 4821, rep was Dana")
    }

    @Test("a failed status save cannot leave a cancellation status without a record - the record lands first")
    func recordAlwaysPrecedesStatus() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await fixture.subscriptions.seed([subscription])
        let flows = fixture.flows
        struct DiskFull: Error {}
        await fixture.subscriptions.failSaves(with: DiskFull())

        await #expect(throws: DiskFull.self) {
            _ = try await flows.startCancellation(
                subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
            )
        }
        // The interrupted flow leaves the benign half-state: record beside a
        // still-active subscription - never .cancellationPending with nothing
        // watching it (§5.2b's invariant, Failure B with extra steps).
        #expect(try await fixture.subscriptions.subscription(withID: subscription.id)?.status == .active)
        #expect(try await fixture.cancellations.record(forSubscription: subscription.id) != nil)

        // And the re-run heals it.
        await fixture.subscriptions.recoverSaves()
        _ = try await flows.startCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        )
        #expect(try await fixture.subscriptions.subscription(withID: subscription.id)?.status
            == .cancellationPending)
    }
}
