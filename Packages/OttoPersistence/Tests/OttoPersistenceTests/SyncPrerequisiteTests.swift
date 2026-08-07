import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// Spec §8 (Wave 6B-Prep): the store-side prerequisites for enabling CloudKit,
// built and tested while there is nothing to lose.
extension SerializedPersistenceTests {
    @Suite("Sync prerequisites at the store (spec §8)")
    struct SyncPrerequisiteTests {

        private let instant = Date(timeIntervalSince1970: 11_000)

        @Test("a restore tombstones records the snapshot does not carry - never hard-deletes")
        func restoreTombstonesAbsentees() async throws {
            let (store, _) = try makeStore()
            let kept = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            let dropped = try makeSubscription(index: 2, cycleStartDay: try day(2026, 2, 1))
            try await store.save(kept)
            try await store.save(dropped)
            try await store.save(
                try makeBillingEvent(index: 101, subscriptionID: dropped.id, expectedDate: try day(2026, 2, 1))
            )

            try await store.restore(OttoDataSnapshot(subscriptions: [kept]), at: instant)

            #expect(try await store.subscriptions().map(\.id) == [kept.id])
            // The dropped subscription and its cascade are history, not gone:
            // under mirroring this restore syncs as ordinary tombstone edits,
            // not a mass cloud deletion (spec §8 prerequisite 4).
            let all = try await store.subscriptionsIncludingDeleted()
            let tombstone = try #require(all.first { $0.id == dropped.id })
            #expect(tombstone.deletedAt == instant)
            let events = try await store.eventsIncludingDeleted(forSubscription: dropped.id)
            #expect(events.allSatisfy { $0.deletedAt == instant })
        }

        @Test("a restore diffs children explicitly: an episode the aggregate no longer carries is tombstoned")
        func restoreDiffsChildren() async throws {
            let (store, _) = try makeStore()
            let closed = PauseEpisode(
                id: try fixtureUUID(701),
                startedOn: try day(2026, 2, 1),
                scheduledResumeOn: nil,
                endedOn: try day(2026, 3, 1),
                outcome: .resumed,
                createdAt: Date(timeIntervalSince1970: 3_000),
                updatedAt: Date(timeIntervalSince1970: 3_000)
            )
            var subscription = try makeSubscription(
                index: 1, cycleStartDay: try day(2026, 1, 15), pauseEpisodes: [closed]
            )
            try await store.save(subscription)

            // The snapshot's copy of the aggregate has no episodes: a restore
            // IS the whole-database statement, so - unlike a save (§4a) - it
            // may and must remove the child, as a tombstone.
            subscription.pauseEpisodes = []
            try await store.restore(OttoDataSnapshot(subscriptions: [subscription]), at: instant)

            let reloaded = try #require(try await store.subscription(withID: subscription.id))
            let episode = try #require(reloaded.pauseEpisodes.first { $0.id == closed.id })
            #expect(episode.deletedAt == instant)
        }

        @Test("a restore never overwrites an earlier tombstone's instant")
        func restoreKeepsEarlierTombstones() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await store.save(subscription)
            try await store.deleteSubscription(withID: subscription.id, at: Date(timeIntervalSince1970: 9_000))

            try await store.restore(OttoDataSnapshot(), at: instant)

            let all = try await store.subscriptionsIncludingDeleted()
            #expect(all.first?.deletedAt == Date(timeIntervalSince1970: 9_000))
        }

        @Test("the kill switch decides the main store's sync mode, and it always wins")
        func killSwitchGovernsSyncMode() {
            // Today every branch is .off - there is nothing safe to turn on
            // until 6B - but the guard rails are on the real path already.
            #expect(OttoContainerFactory.mainStoreSyncMode(for: SyncState()) == .off)
            #expect(OttoContainerFactory.mainStoreSyncMode(
                for: SyncState(isEnabled: true, killSwitchEngaged: false)
            ) == .off)
            // The line 6B will care about: an engaged kill switch beats an
            // enabled sync, unconditionally.
            #expect(OttoContainerFactory.mainStoreSyncMode(
                for: SyncState(isEnabled: true, killSwitchEngaged: true)
            ) == .off)
            #expect(OttoContainerFactory.mainStoreSyncMode(
                for: SyncState(isEnabled: false, killSwitchEngaged: true)
            ) == .off)
        }

        @Test("the sync switches persist and load without a container")
        func syncStateRoundTrips() throws {
            let defaults = try #require(UserDefaults(suiteName: "sync-state-tests"))
            defer { defaults.removePersistentDomain(forName: "sync-state-tests") }

            #expect(SyncState.load(from: defaults) == SyncState())

            SyncState.setEnabled(true, in: defaults)
            SyncState.setKillSwitchEngaged(true, in: defaults)
            #expect(SyncState.load(from: defaults) == SyncState(isEnabled: true, killSwitchEngaged: true))

            // Disengaging the brake restores the previous state - the enable
            // flag was deliberately untouched by the kill switch.
            SyncState.setKillSwitchEngaged(false, in: defaults)
            #expect(SyncState.load(from: defaults) == SyncState(isEnabled: true, killSwitchEngaged: false))
        }
    }
}
