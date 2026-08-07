import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// Spec §5.3 (v2.0) and §4a: the post-sync reconciliation pass. Each test
// simulates what two devices leave behind after sync converges, runs the pass,
// and asserts the store reaches the state every other device would reach.
extension SerializedPersistenceTests {
    @Suite("The reconciliation pass (spec §5.3 v2.0, §4a)")
    struct ReconciliationTests {

        private let instant = Date(timeIntervalSince1970: 9_000)

        private func duplicateRow(
            _ index: Int,
            createdAt: TimeInterval,
            state: BillingEvent.State = .upcoming,
            userConfirmedAt: Date? = nil,
            acknowledgedAt: Date? = nil
        ) throws -> BillingEvent {
            BillingEvent(
                id: try fixtureUUID(index),
                subscriptionID: try fixtureUUID(0),
                expectedDate: try day(2026, 8, 15),
                expectedAmountCents: 1099,
                state: state,
                userConfirmedAt: userConfirmedAt,
                acknowledgedAt: acknowledgedAt,
                createdAt: Date(timeIntervalSince1970: createdAt),
                updatedAt: Date(timeIntervalSince1970: createdAt)
            )
        }

        /// Both devices materialized Aug 15; one acknowledged its copy, the
        /// other confirmed the charge on its own. `order` is the arrival
        /// order, which must not matter.
        private func storeWithTwins(order: [Int]) async throws -> OttoStore {
            let (store, _) = try makeStore()
            try await store.save(try makeSubscription(cycleStartDay: try day(2026, 1, 15)))
            let rows = [
                801: try duplicateRow(801, createdAt: 1_000, acknowledgedAt: Date(timeIntervalSince1970: 5_000)),
                802: try duplicateRow(
                    802, createdAt: 2_000, state: .confirmedCharged,
                    userConfirmedAt: Date(timeIntervalSince1970: 6_000)
                )
            ]
            for index in order {
                try await store.save(try #require(rows[index]))
            }
            return store
        }

        @Test("duplicate ledger twins converge from both directions", arguments: [[801, 802], [802, 801]])
        func duplicateTwinsConverge(order: [Int]) async throws {
            let store = try await storeWithTwins(order: order)

            let summary = try await store.reconcile(at: instant)

            #expect(summary.mergedLedgerGroups == 1)
            let live = try await store.events(forSubscription: try fixtureUUID(0))
            #expect(live.map(\.id) == [try fixtureUUID(801)])
            let survivor = try #require(live.first)
            // The earliest-created row survived, wearing the twin's
            // confirmation and its own acknowledgement.
            #expect(survivor.state == .confirmedCharged)
            #expect(survivor.userConfirmedAt == Date(timeIntervalSince1970: 6_000))
            #expect(survivor.acknowledgedAt == Date(timeIntervalSince1970: 5_000))
            let all = try await store.eventsIncludingDeleted(forSubscription: try fixtureUUID(0))
            let tombstoned = try #require(all.first { $0.id == (try fixtureUUID(802)) })
            #expect(tombstoned.deletedAt == instant)
        }

        @Test("rival open cancellation episodes: the newest stays open, the older closes as .superseded")
        func rivalCancellationsConverge() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(
                status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
            )
            try await store.save(subscription)
            let older = try makeCancellationEpisode(
                index: 601, subscriptionID: subscription.id,
                nextChargeDateIfNotCancelled: try day(2026, 9, 15)
            )
            var newer = try makeCancellationEpisode(
                index: 602, subscriptionID: subscription.id,
                nextChargeDateIfNotCancelled: try day(2026, 9, 15)
            )
            newer.markedCancelledAt = Date(timeIntervalSince1970: 7_000)
            try await store.save(older)
            try await store.save(newer)

            let summary = try await store.reconcile(at: instant)

            #expect(summary.closedCancellationEpisodes == 1)
            #expect(try await store.openEpisode(forSubscription: subscription.id)?.id == newer.id)
            let episodes = try await store.episodes(forSubscription: subscription.id)
            let closed = try #require(episodes.first { $0.id == older.id })
            #expect(closed.outcome == .superseded)
            #expect(closed.endedAt == newer.markedCancelledAt)
        }

        @Test("the pass persists §4a read repairs without waiting for a user save")
        func persistsReadRepairs() async throws {
            let (store, containers) = try makeStore()
            let local = PauseEpisode(
                id: try fixtureUUID(701),
                startedOn: try day(2026, 8, 1),
                createdAt: Date(timeIntervalSince1970: 3_000),
                updatedAt: Date(timeIntervalSince1970: 3_000)
            )
            try await store.save(try makeSubscription(
                status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEpisodes: [local]
            ))
            let context = ModelContext(containers.main)
            let record = try #require(try context.fetch(FetchDescriptor<StoredSubscription>()).first)
            let remote = OttoSchemaV3.StoredPauseEpisode()
            context.insert(remote)
            remote.subscription = record
            remote.id = try fixtureUUID(702)
            remote.startedOn = 20_260_803
            remote.createdAt = Date(timeIntervalSince1970: 4_000)
            remote.updatedAt = Date(timeIntervalSince1970: 4_000)
            try context.save()

            let fresh = OttoStore(containers: containers)
            let summary = try await fresh.reconcile(at: instant)

            #expect(summary.persistedReadRepairs == 1)
            #expect(try await fresh.subscriptionReadRepairs() == [])
            let verification = ModelContext(containers.main)
            let remoteID: UUID? = try fixtureUUID(702)
            let stored = try #require(
                try verification.fetch(FetchDescriptor<OttoSchemaV3.StoredPauseEpisode>())
                    .first { $0.id == remoteID }
            )
            #expect(stored.endedOn == 20_260_801)
            #expect(stored.outcome == PauseEpisode.Outcome.superseded.rawValue)
        }

        @Test("the pass is idempotent: a second run finds nothing to do")
        func idempotent() async throws {
            let store = try await storeWithTwins(order: [801, 802])
            _ = try await store.reconcile(at: instant)

            let second = try await store.reconcile(at: Date(timeIntervalSince1970: 10_000))

            #expect(second == ReconciliationSummary())
        }
    }
}
