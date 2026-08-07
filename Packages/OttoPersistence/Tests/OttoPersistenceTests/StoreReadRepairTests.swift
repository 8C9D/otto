import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// Spec §4a principle 2 at the store: shapes a two-device merge writes into the
// table are readable on every device, repaired identically, reported to the
// aggregate needs-review surface, and the repair persists on the next save.
private struct TwoOpenPausesWorld {
    let store: OttoStore
    let containers: OttoContainers
    let localEpisodeID: UUID
    let remoteEpisodeID: UUID
}

extension SerializedPersistenceTests {
    @Suite("Store read repairs (spec §4a, Wave 6B-Prep)")
    struct StoreReadRepairTests {

        /// A paused subscription whose store then receives a SECOND open
        /// episode - device B's independent pause arriving by sync.
        private func storeWithTwoOpenPauses() async throws -> TwoOpenPausesWorld {
            let (store, containers) = try makeStore()
            let local = PauseEpisode(
                id: try fixtureUUID(701),
                startedOn: try day(2026, 8, 1),
                createdAt: Date(timeIntervalSince1970: 3_000),
                updatedAt: Date(timeIntervalSince1970: 3_000)
            )
            let subscription = try makeSubscription(
                status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEpisodes: [local]
            )
            try await store.save(subscription)

            let context = ModelContext(containers.main)
            let record = try #require(try context.fetch(FetchDescriptor<StoredSubscription>()).first)
            let remote = StoredPauseEpisode()
            context.insert(remote)
            remote.subscription = record
            remote.id = try fixtureUUID(702)
            remote.startedOn = 20_260_803
            remote.createdAt = Date(timeIntervalSince1970: 4_000)
            remote.updatedAt = Date(timeIntervalSince1970: 4_000)
            try context.save()

            return TwoOpenPausesWorld(
                store: OttoStore(containers: containers),
                containers: containers,
                localEpisodeID: local.id,
                remoteEpisodeID: try fixtureUUID(702)
            )
        }

        @Test("two open pause episodes stay readable: earliest start wins, the later closes as .superseded")
        func twoOpenPausesRepairOnRead() async throws {
            let world = try await storeWithTwoOpenPauses()

            let loaded = try #require(try await world.store.subscriptions().first)
            #expect(loaded.currentPauseEpisode?.id == world.localEpisodeID)
            let closed = try #require(loaded.pauseEpisodes.first { $0.id == world.remoteEpisodeID })
            #expect(closed.endedOn == (try day(2026, 8, 1)))
            #expect(closed.outcome == .superseded)

            #expect(try await world.store.unreadableSubscriptionCount() == 0)
            let reports = try await world.store.subscriptionReadRepairs()
            #expect(reports.map(\.repairs) == [[
                .extraOpenPauseEpisodeClosed(episodeID: world.remoteEpisodeID)
            ]])
        }

        @Test("the repair persists on the next save, and the report drains")
        func repairPersistsOnSave() async throws {
            let world = try await storeWithTwoOpenPauses()

            let repaired = try #require(try await world.store.subscriptions().first)
            try await world.store.save(repaired)

            let context = ModelContext(world.containers.main)
            let remoteID: UUID? = world.remoteEpisodeID
            let stored = try #require(
                try context.fetch(FetchDescriptor<StoredPauseEpisode>()).first { $0.id == remoteID }
            )
            #expect(stored.endedOn == 20_260_801)
            #expect(stored.outcome == PauseEpisode.Outcome.superseded.rawValue)
            #expect(try await world.store.subscriptionReadRepairs() == [])
        }

        @Test("a .paused parent whose episode closed elsewhere reads as an indefinite pause, not a dead record")
        func pausedWithoutOpenEpisodeReads() async throws {
            let (store, containers) = try makeStore()
            let subscription = try makeSubscription(
                status: .paused, cycleStartDay: try day(2026, 1, 15)
            )
            try await store.save(subscription)

            // The other device resumed - its episode closure synced in, the
            // status field's last-writer-wins landed on .paused.
            let context = ModelContext(containers.main)
            let episode = try #require(
                try context.fetch(FetchDescriptor<StoredPauseEpisode>()).first
            )
            episode.endedOn = 20_260_805
            episode.outcome = PauseEpisode.Outcome.resumed.rawValue
            try context.save()

            let fresh = OttoStore(containers: containers)
            let loaded = try #require(try await fresh.subscriptions().first)
            #expect(loaded.storedStatus == .paused)
            #expect(loaded.currentPauseEpisode == nil)
            #expect(try await fresh.unreadableSubscriptionCount() == 0)
            let reports = try await fresh.subscriptionReadRepairs()
            #expect(reports.map(\.repairs) == [[.pausedWithoutOpenEpisode]])
        }
    }
}
