import Foundation
import OttoDomain
import Testing
@testable import OttoServices

// The paused-cancellation flow (spec §5.4, v1.5; built in Wave 7): a dated
// pause watches its first resumed charge, an indefinite one defers the check
// entirely and waits for the user to supply the date it refused to guess.

@Suite("The paused-cancellation flow (spec §5.4)")
struct PausedCancellationFlowTests {

    @Test("cancelling an indefinitely paused subscription defers the check instead of guessing a date")
    func indefinitePausedCancellationDefers() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(
            index: 1, status: .paused, cycleStartDay: try day(2026, 1, 15)
        )
        await fixture.subscriptions.seed([subscription])
        let flows = fixture.flows
        let today = try day(2026, 8, 6)
        let now = try fixtureNow()

        let start = try await flows.startCancellation(subscriptionID: subscription.id, now: now, today: today)

        // The record exists (a .cancellationPending subscription without one is
        // the §5.2b violation), watching nothing, fabricating nothing.
        let record = try #require(start?.record)
        #expect(record.verificationState == .awaitingResumeDate)
        #expect(record.nextChargeDateIfNotCancelled == nil)
        #expect(record.expectedChargeAmountCents == nil)
        let mutated = try await fixture.subscriptions.subscription(withID: subscription.id)
        #expect(mutated?.storedStatus == .cancellationPending)

        // Answering the never-asked question does nothing - and must not archive.
        let summary = try await flows.answerVerification(
            subscriptionID: subscription.id, chargesStopped: true, now: now, today: today
        )
        #expect(summary == nil)
        #expect(try await fixture.subscriptions.subscription(withID: subscription.id)?.storedStatus
            == .cancellationPending)

        // The user supplies the resume date: the watch starts at the first
        // would-be charge on or after it, and the record becomes ordinary.
        try await flows.supplyPausedResumeDate(
            subscriptionID: subscription.id, resumeDate: try day(2026, 9, 1), now: now
        )
        let watching = try #require(try await fixture.cancellations.openEpisode(forSubscription: subscription.id))
        #expect(watching.verificationState == .pending)
        #expect(watching.nextChargeDateIfNotCancelled == (try day(2026, 9, 15)))
        #expect(watching.expectedChargeAmountCents == subscription.amountCents)

        // Twice equals once.
        try await flows.supplyPausedResumeDate(
            subscriptionID: subscription.id, resumeDate: try day(2026, 12, 1), now: now
        )
        let unchanged = try await fixture.cancellations.openEpisode(forSubscription: subscription.id)
        #expect(unchanged == watching)
    }

    @Test("cancelling a pause with a known end watches the first resumed charge")
    func datedPausedCancellationWatchesResumedCharge() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(
            index: 1, status: .paused, cycleStartDay: try day(2026, 1, 15),
            pauseEndsOn: try day(2026, 9, 1)
        )
        await fixture.subscriptions.seed([subscription])

        let start = try await fixture.flows.startCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        )

        let record = try #require(start?.record)
        #expect(record.verificationState == .pending)
        #expect(record.nextChargeDateIfNotCancelled == (try day(2026, 9, 15)))
        #expect(record.expectedChargeAmountCents == subscription.amountCents)
    }
}
