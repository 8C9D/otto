import Foundation
import Testing
import OttoDomain
@testable import OttoServices

// The un-cancel flow (spec §5.4, §5.3a - Wave 8.5): an accidental "I'm
// cancelling" tap used to be irreversible in-app. Abandoning closes the open
// episode - keeps it, never deletes it - and restores the status the
// cancellation interrupted.
@Suite("Abandoning a cancellation (spec §5.4, §5.3a)")
struct AbandonCancellationTests {

    @Test("abandon closes the episode as .abandoned and the subscription is active again")
    func abandonRestoresActive() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await fixture.subscriptions.seed([subscription])
        let start = try #require(try await fixture.flows.startCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        ))
        #expect(start.record.statusAtStart == .active)

        let later = try fixtureNow().addingTimeInterval(3_600)
        try await fixture.flows.abandonCancellation(
            subscriptionID: subscription.id, now: later, today: try day(2026, 8, 6)
        )

        // The episode is history now: closed, kept, outcome recorded.
        #expect(try await fixture.cancellations.openEpisode(forSubscription: subscription.id) == nil)
        let episodes = try await fixture.cancellations.episodes(forSubscription: subscription.id)
        #expect(episodes.count == 1)
        #expect(episodes.first?.outcome == .abandoned)
        #expect(episodes.first?.endedAt == later)
        // And the subscription is back where the cancellation found it.
        let restored = try #require(try await fixture.subscriptions.subscription(withID: subscription.id))
        #expect(restored.storedStatus == .active)

        // Twice equals once.
        try await fixture.flows.abandonCancellation(
            subscriptionID: subscription.id, now: later.addingTimeInterval(600),
            today: try day(2026, 8, 6)
        )
        #expect(try await fixture.cancellations.episodes(forSubscription: subscription.id) == episodes)
        #expect(try await fixture.subscriptions.subscription(withID: subscription.id) == restored)
    }

    @Test("a cancellation abandoned mid-pause restores .paused - the pause episode never closed")
    func abandonRestoresPaused() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(
            index: 1, status: .paused, cycleStartDay: try day(2026, 1, 15),
            pauseEndsOn: try day(2026, 12, 1), pausedOn: try day(2026, 6, 1)
        )
        await fixture.subscriptions.seed([subscription])
        let start = try #require(try await fixture.flows.startCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        ))
        #expect(start.record.statusAtStart == .paused)

        try await fixture.flows.abandonCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        )

        let restored = try #require(try await fixture.subscriptions.subscription(withID: subscription.id))
        #expect(restored.storedStatus == .paused)
        #expect(restored.pauseEndsOn == (try day(2026, 12, 1)))
    }

    @Test("a trial cancelled before converting comes back as the trial it still is")
    func abandonRestoresTrial() async throws {
        let fixture = SchedulerFixture()
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 1), lengthDays: 30)
        let subscription = try makeSubscription(
            index: 1, status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial
        )
        await fixture.subscriptions.seed([subscription])
        let start = try #require(try await fixture.flows.startCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        ))
        #expect(start.record.statusAtStart == .trial)

        try await fixture.flows.abandonCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        )

        let restored = try #require(try await fixture.subscriptions.subscription(withID: subscription.id))
        #expect(restored.storedStatus == .trial)
        #expect(restored.trial == trial)
    }

    @Test("cancelling again after an abandon opens a SECOND episode - history accumulates")
    func recancelOpensNewEpisode() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await fixture.subscriptions.seed([subscription])
        let first = try #require(try await fixture.flows.startCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        ))
        try await fixture.flows.abandonCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        )

        let second = try #require(try await fixture.flows.startCancellation(
            subscriptionID: subscription.id,
            now: try fixtureNow().addingTimeInterval(86_400),
            today: try day(2026, 8, 7)
        ))

        #expect(second.record.id != first.record.id)
        let episodes = try await fixture.cancellations.episodes(forSubscription: subscription.id)
        #expect(episodes.count == 2)
        #expect(episodes.filter(\.isOpen).map(\.id) == [second.record.id])
        #expect(episodes.first { $0.id == first.record.id }?.outcome == .abandoned)
    }

    @Test("an un-cancel killed between its two writes heals - from either flow")
    func interruptedAbandonHeals() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await fixture.subscriptions.seed([subscription])
        _ = try await fixture.flows.startCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        )

        // Simulate the kill: the episode write landed, the status restore did
        // not - the subscription is .cancellationPending with no open episode.
        let open = try #require(try await fixture.cancellations.openEpisode(forSubscription: subscription.id))
        let closed = try #require(open.abandoning(at: try fixtureNow()))
        try await fixture.cancellations.save(closed)

        // Re-running the abandon completes the restore.
        try await fixture.flows.abandonCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 8, 6)
        )
        let healed = try #require(try await fixture.subscriptions.subscription(withID: subscription.id))
        #expect(healed.storedStatus == .active)
    }

    @Test("the watermark rewinds behind the watched date on abandon - migrated data's belt")
    func abandonRewindsWatermark() async throws {
        // A pre-freeze (migrated) record: the watch was on Sep 1 and the
        // watermark advanced past it while the cancellation sat pending. The
        // un-cancel asserts those dates were real charges, so nothing may
        // vouch for them unobserved.
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(
            index: 1, status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
        )
        await fixture.subscriptions.seed([subscription])
        await fixture.billingEvents.seedWatermark(try day(2026, 11, 20), forSubscription: subscription.id)
        await fixture.cancellations.seed([CancellationEpisode(
            id: try fixtureUUID(601),
            subscriptionID: subscription.id,
            markedCancelledAt: Date(timeIntervalSince1970: 4_000),
            nextChargeDateIfNotCancelled: try day(2026, 9, 1),
            verificationState: .pending,
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )])

        try await fixture.flows.abandonCancellation(
            subscriptionID: subscription.id, now: try fixtureNow(), today: try day(2026, 11, 25)
        )

        #expect(
            try await fixture.billingEvents.materializationWatermark(forSubscription: subscription.id)
                == (try day(2026, 8, 31))
        )
    }
}
