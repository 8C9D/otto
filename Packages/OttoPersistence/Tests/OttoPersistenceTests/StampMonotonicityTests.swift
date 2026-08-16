import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// ⛔ The device clock is not a monotonic source (docs/sync-safety.md): real
// exported data carries records whose `deletedAt` PRECEDES their `createdAt`,
// written under the advanced clock of this project's own verification procedure
// and tombstoned after the clock was restored. Every store write that stamps an
// instant clamps it, so the shape cannot be produced here again.
extension SerializedPersistenceTests {
    @Suite("Store stamps never move backwards (docs/sync-safety.md)")
    struct StampMonotonicityTests {

        /// Behind every fixture stamp - the clock as it reads after being set
        /// back past the moment the records were written.
        private let setBackClock = Date(timeIntervalSince1970: 500)
        private let fixtureCreated = Date(timeIntervalSince1970: 1_000)
        private let fixtureUpdated = Date(timeIntervalSince1970: 2_000)

        @Test("⛔ the delete cascade cannot tombstone a record before it was created")
        func deleteCascadeTombstonesNoEarlierThanCreation() async throws {
            let (store, containers) = try makeStore()
            let trial = try makeTrialTerm(startDate: try day(2026, 8, 1))
            let subscription = try makeSubscription(
                status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial
            )
            try await store.save(subscription)
            try await store.save(try makeBillingEvent(
                subscriptionID: subscription.id, expectedDate: try day(2026, 9, 1)
            ))
            try await store.save(try makeCancellationEpisode(
                subscriptionID: subscription.id, nextChargeDateIfNotCancelled: try day(2026, 9, 1)
            ))
            try await store.append(try makePriceChange(
                subscriptionID: subscription.id, effectiveDate: try day(2026, 8, 20)
            ))

            try await store.deleteSubscription(withID: subscription.id, at: setBackClock)

            // The delete happened - every live read is empty - but no tombstone
            // claims the record died before it existed.
            #expect(try await store.subscriptions() == [])
            let tombstone = try #require(try await store.subscriptionsIncludingDeleted().first)
            #expect(tombstone.deletedAt == fixtureCreated)
            let context = ModelContext(containers.main)
            #expect(try context.fetch(FetchDescriptor<StoredTrialTerm>()).first?.deletedAt == fixtureCreated)
            #expect(try context.fetch(FetchDescriptor<StoredBillingEvent>()).first?.deletedAt == fixtureCreated)
            #expect(
                try context.fetch(FetchDescriptor<StoredCancellationEpisode>()).first?.deletedAt == fixtureCreated
            )
            #expect(try context.fetch(FetchDescriptor<StoredPriceChange>()).first?.deletedAt == fixtureCreated)
        }

        @Test("an honest clock still stamps the honest instant")
        func honestDeleteStampsTheInstant() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 8, 15))
            try await store.save(subscription)
            let instant = Date(timeIntervalSince1970: 9_000)

            try await store.deleteSubscription(withID: subscription.id, at: instant)

            #expect(try await store.subscriptionsIncludingDeleted().first?.deletedAt == instant)
        }

        @Test("the reconciliation pass writes no regressive stamp under a set-back clock")
        func reconciliationDoesNotRegressStamps() async throws {
            let (store, _) = try makeStore()
            try await store.save(try makeSubscription(cycleStartDay: try day(2026, 1, 15)))
            // The shape two devices' independent materialization passes leave
            // behind: live twins on one (subscriptionID, expectedDate).
            for index in [801, 802] {
                try await store.save(BillingEvent(
                    id: try fixtureUUID(index),
                    subscriptionID: try fixtureUUID(0),
                    expectedDate: try day(2026, 8, 15),
                    expectedAmountCents: 1099,
                    state: index == 802 ? .confirmedCharged : .upcoming,
                    userConfirmedAt: index == 802 ? Date(timeIntervalSince1970: 6_000) : nil,
                    createdAt: fixtureCreated,
                    updatedAt: fixtureUpdated
                ))
            }

            let summary = try await store.reconcile(at: setBackClock)

            #expect(summary.mergedLedgerGroups == 1)
            let rows = try await store.eventsIncludingDeleted(forSubscription: try fixtureUUID(0))
            #expect(rows.count == 2)
            for row in rows {
                // The merge was written, and every stamp it wrote still sits at
                // or after the stamps the row already carried.
                #expect(row.updatedAt >= fixtureUpdated)
                if let deleted = row.deletedAt {
                    #expect(deleted >= row.createdAt)
                }
            }
            let survivor = try #require(rows.first { $0.deletedAt == nil })
            #expect(survivor.state == .confirmedCharged)
        }
    }
}
