import Foundation
import Testing
@testable import OttoDomain

// ⛔ The device clock is not a monotonic source (docs/sync-safety.md). Real
// exported data carries records whose `deletedAt` PRECEDES their `createdAt`:
// they were written under the advanced clock of this project's own verification
// procedure and tombstoned after the clock was restored. A user can set the
// clock by hand for their own reasons and nothing in the app can prevent it, so
// every write clamps instead of trusting the instant it is handed - an edit
// cannot lose the merge against the copy it just replaced, and a tombstone
// cannot predate the record it closes.

@Suite("Mutation stamps never move backwards (docs/sync-safety.md)")
struct StampMonotonicityTests {

    /// The clock was advanced, records were written, the clock was restored:
    /// every stamp the record carries is now AHEAD of `now`.
    private let writtenUnderAdvancedClock = Date(timeIntervalSince1970: 1_786_371_065)  // 2026-08-10T14:11:05Z
    private let clockRestored = Date(timeIntervalSince1970: 1_786_210_329)  // 2026-08-08T17:32:09Z

    private func advancedClockSubscription(
        status: SubscriptionStatus = .active, trial: TrialTerm? = nil
    ) throws -> Subscription {
        var subscription = try makeSubscription(
            status: status, cycleStartDay: try day(2026, 8, 1), trial: trial
        )
        subscription.createdAt = writtenUnderAdvancedClock
        subscription.updatedAt = writtenUnderAdvancedClock
        return subscription
    }

    @Test("a status transition under a set-back clock keeps the later stamp")
    func transitionDoesNotRegressUpdatedAt() throws {
        let subscription = try advancedClockSubscription()

        let cancelling = try #require(subscription.markingCancellationPending(at: clockRestored))

        #expect(cancelling.storedStatus == .cancellationPending)
        // The mutation happened; the stamp did not move backwards, so the copy
        // it replaced cannot beat it under last-write-wins.
        #expect(cancelling.updatedAt == writtenUnderAdvancedClock)
    }

    @Test("a pause under a set-back clock keeps the later stamp")
    func pauseDoesNotRegressUpdatedAt() throws {
        let subscription = try advancedClockSubscription()

        let paused = try #require(subscription.pausing(
            on: try day(2026, 8, 8), until: nil, episodeID: try fixtureUUID(701), at: clockRestored
        ))

        #expect(paused.storedStatus == .paused)
        #expect(paused.updatedAt == writtenUnderAdvancedClock)
    }

    @Test("an honest clock still stamps the honest instant")
    func honestClockIsUnaffected() throws {
        var subscription = try advancedClockSubscription()
        subscription.updatedAt = clockRestored
        let now = writtenUnderAdvancedClock

        let archived = try #require(subscription.archiving(at: now))

        #expect(archived.updatedAt == now)
    }

    @Test("a resumed pause episode's own stamp does not regress either")
    func pauseEpisodeDoesNotRegressUpdatedAt() throws {
        var episode = try makePauseEpisode(index: 701, startedOn: try day(2026, 8, 1))
        episode.createdAt = writtenUnderAdvancedClock
        episode.updatedAt = writtenUnderAdvancedClock

        let resumed = try #require(episode.resuming(on: try day(2026, 8, 8), at: clockRestored))

        #expect(resumed.outcome == .resumed)
        #expect(resumed.updatedAt == writtenUnderAdvancedClock)
    }

    @Test("a verification answer under a set-back clock keeps the later stamp")
    func verificationDoesNotRegressUpdatedAt() throws {
        var episode = try makeCancellationEpisode(
            index: 601, subscriptionID: try fixtureUUID(1),
            nextChargeDateIfNotCancelled: try day(2026, 9, 10)
        )
        episode.createdAt = writtenUnderAdvancedClock
        episode.updatedAt = writtenUnderAdvancedClock

        let confirmed = episode.confirmingChargesStopped(at: clockRestored)

        #expect(confirmed.outcome == .verifiedStopped)
        #expect(confirmed.updatedAt == writtenUnderAdvancedClock)
    }

    @Test("⛔ a tombstone written under a set-back clock cannot predate the record it closes")
    func tombstoneNeverPrecedesCreation() throws {
        var trial = try makeTrialTerm(startDate: try day(2026, 8, 1), lengthDays: 14)
        trial.createdAt = writtenUnderAdvancedClock
        trial.updatedAt = writtenUnderAdvancedClock
        let subscription = try advancedClockSubscription(status: .trial, trial: trial)

        // The trial toggle turned off: the term is tombstoned at `now`, which
        // the restored clock has put two days before the term was created.
        let dropped = try #require(subscription.editedTrial(draft: nil, droppedAt: clockRestored))

        #expect(dropped.deletedAt == writtenUnderAdvancedClock)
        #expect(try #require(dropped.deletedAt) >= dropped.createdAt)
        #expect(dropped.updatedAt == writtenUnderAdvancedClock)
    }
}
