import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// Spec §4a principle 1 (Wave 6B-Prep): absence is not deletion. Under
// per-record sync a stale in-memory snapshot is ordinary - device A loads,
// device B's record syncs in, device A saves an unrelated edit - and the save
// path must be INCAPABLE of removing a record the snapshot never carried.
// Every test here is that scenario, one per child collection: the store holds
// a record, a snapshot from before it existed is saved, the record survives.
extension SerializedPersistenceTests {
    @Suite("Stale snapshots cannot delete (spec §4a, Wave 6B-Prep)")
    struct StaleSnapshotSaveTests {

        private func closedEpisode() throws -> PauseEpisode {
            PauseEpisode(
                id: try fixtureUUID(701),
                startedOn: try day(2026, 2, 1),
                scheduledResumeOn: nil,
                endedOn: try day(2026, 3, 1),
                outcome: .resumed,
                createdAt: Date(timeIntervalSince1970: 3_000),
                updatedAt: Date(timeIntervalSince1970: 3_000)
            )
        }

        @Test("a pause episode a stale snapshot never saw survives its save")
        func pauseEpisodeSurvivesStaleSave() async throws {
            let (store, _) = try makeStore()
            let stale = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await store.save(stale)

            var current = stale
            current.pauseEpisodes = [try closedEpisode()]
            try await store.save(current)

            // The other device's episode synced in; this device saves its
            // pre-episode snapshot with an unrelated edit.
            var staleEdit = stale
            staleEdit.notes = "edited from a stale snapshot"
            try await store.save(staleEdit)

            let reloaded = try #require(try await store.subscription(withID: stale.id))
            #expect(reloaded.notes == "edited from a stale snapshot")
            let survivor = try #require(reloaded.pauseEpisodes.first { $0.id == (try fixtureUUID(701)) })
            #expect(survivor.deletedAt == nil)
        }

        @Test("a trial term a stale snapshot never saw survives its save")
        func trialSurvivesStaleSave() async throws {
            let (store, _) = try makeStore()
            let stale = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await store.save(stale)

            var current = stale
            current.trial = try makeTrialTerm(startDate: try day(2026, 1, 1))
            try await store.save(current)

            var staleEdit = stale
            staleEdit.notes = "edited from a stale snapshot"
            try await store.save(staleEdit)

            let reloaded = try #require(try await store.subscription(withID: stale.id))
            #expect(reloaded.trial == current.trial)
        }

        @Test("an evidence note a stale episode snapshot never saw survives its save")
        func evidenceNoteSurvivesStaleSave() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(
                index: 1, status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
            )
            try await store.save(subscription)
            let stale = try makeCancellationEpisode(
                subscriptionID: subscription.id,
                nextChargeDateIfNotCancelled: try day(2026, 9, 15),
                evidenceNote: "confirmation #123"
            )
            try await store.save(stale)

            var current = stale
            current.evidenceNotes.append(EvidenceNote(
                id: try fixtureUUID(651),
                text: "second round, retention offer declined",
                createdAt: Date(timeIntervalSince1970: 5_000),
                updatedAt: Date(timeIntervalSince1970: 5_000)
            ))
            try await store.save(current)

            try await store.save(stale)

            let reloaded = try #require(try await store.episodes(forSubscription: subscription.id).first)
            #expect(reloaded.evidenceNotes.count == 2)
            #expect(reloaded.evidenceNotes.allSatisfy { $0.deletedAt == nil })
        }

        @Test("a cancellation episode is untouchable from a subscription save - it is not in the aggregate")
        func cancellationEpisodeSurvivesSubscriptionSave() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(
                index: 1, status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
            )
            try await store.save(subscription)
            let episode = try makeCancellationEpisode(
                subscriptionID: subscription.id,
                nextChargeDateIfNotCancelled: try day(2026, 9, 15)
            )
            try await store.save(episode)

            var staleEdit = subscription
            staleEdit.notes = "edited from a stale snapshot"
            try await store.save(staleEdit)

            #expect(try await store.episodes(forSubscription: subscription.id) == [episode])
        }

        @Test("deletion still works - as an explicit tombstone on the identified record")
        func explicitTombstoneStillDeletes() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(
                index: 1, status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
            )
            try await store.save(subscription)
            var episode = try makeCancellationEpisode(
                subscriptionID: subscription.id,
                nextChargeDateIfNotCancelled: try day(2026, 9, 15),
                evidenceNote: "kept"
            )
            try await store.save(episode)

            // The evidence flow expresses removal by tombstoning the note in
            // place (spec §3.5) - the one way a save may delete.
            episode.evidenceNotes[0].deletedAt = Date(timeIntervalSince1970: 6_000)
            episode.evidenceNotes[0].updatedAt = Date(timeIntervalSince1970: 6_000)
            try await store.save(episode)

            let reloaded = try #require(try await store.episodes(forSubscription: subscription.id).first)
            let note = try #require(reloaded.evidenceNotes.first)
            #expect(note.deletedAt == Date(timeIntervalSince1970: 6_000))
        }
    }
}
