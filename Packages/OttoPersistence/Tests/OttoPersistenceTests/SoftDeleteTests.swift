import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

@Suite("Soft deletes: default-filtered, retrievable on request, cascading")
struct SoftDeleteTests {

    @Test("a deleted subscription vanishes from normal reads and stays retrievable as a tombstone")
    func subscriptionTombstone() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 8, 15))
        try await store.save(subscription)
        let instant = Date(timeIntervalSince1970: 9_000)

        try await store.deleteSubscription(withID: subscription.id, at: instant)

        #expect(try await store.subscriptions() == [])
        #expect(try await store.subscription(withID: subscription.id) == nil)
        let tombstones = try await store.subscriptionsIncludingDeleted()
        #expect(tombstones.map(\.id) == [subscription.id])
        #expect(tombstones.first?.deletedAt == instant)
    }

    @Test("deleting a subscription cascades soft deletes to every child record")
    func cascade() async throws {
        let (store, container) = try makeStore()
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 1))
        let subscription = try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial)
        try await store.save(subscription)
        try await store.save(try makeBillingEvent(subscriptionID: subscription.id, expectedDate: try day(2026, 9, 1)))
        try await store.save(try makeCancellationEpisode(
            subscriptionID: subscription.id, nextChargeDateIfNotCancelled: try day(2026, 9, 1)
        ))
        try await store.append(try makePriceChange(
            subscriptionID: subscription.id, effectiveDate: try day(2026, 8, 20)
        ))
        let instant = Date(timeIntervalSince1970: 9_000)

        try await store.deleteSubscription(withID: subscription.id, at: instant)

        // Every live read is empty...
        #expect(try await store.events(forSubscription: subscription.id) == [])
        #expect(try await store.openEpisode(forSubscription: subscription.id) == nil)
        #expect(try await store.history(forSubscription: subscription.id) == [])

        // ...every tombstone read still sees the record...
        #expect(try await store.eventsIncludingDeleted(forSubscription: subscription.id).count == 1)
        #expect(try await store.episodesIncludingDeleted(forSubscription: subscription.id).count == 1)
        #expect(try await store.historyIncludingDeleted(forSubscription: subscription.id).count == 1)

        // ...and every stored child carries the cascade instant, trial included.
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<StoredTrialTerm>()).first?.deletedAt == instant)
        #expect(try context.fetch(FetchDescriptor<StoredBillingEvent>()).first?.deletedAt == instant)
        #expect(try context.fetch(FetchDescriptor<StoredCancellationEpisode>()).first?.deletedAt == instant)
        #expect(try context.fetch(FetchDescriptor<StoredPriceChange>()).first?.deletedAt == instant)
    }

    @Test("a cascade never overwrites an earlier tombstone's instant")
    func cascadePreservesEarlierTombstones() async throws {
        let (store, container) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 8, 15))
        try await store.save(subscription)
        try await store.save(try makeBillingEvent(subscriptionID: subscription.id, expectedDate: try day(2026, 9, 15)))

        let earlier = Date(timeIntervalSince1970: 7_000)
        let context = ModelContext(container)
        let event = try #require(try context.fetch(FetchDescriptor<StoredBillingEvent>()).first)
        event.deletedAt = earlier
        try context.save()

        try await store.deleteSubscription(withID: subscription.id, at: Date(timeIntervalSince1970: 9_000))

        let verification = ModelContext(container)
        #expect(try verification.fetch(FetchDescriptor<StoredBillingEvent>()).first?.deletedAt == earlier)
    }

    @Test("deleting an already-deleted subscription keeps the original instant")
    func deleteTwice() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 8, 15))
        try await store.save(subscription)
        let first = Date(timeIntervalSince1970: 7_000)

        try await store.deleteSubscription(withID: subscription.id, at: first)
        try await store.deleteSubscription(withID: subscription.id, at: Date(timeIntervalSince1970: 9_000))

        #expect(try await store.subscriptionsIncludingDeleted().first?.deletedAt == first)
    }

    @Test("deleting a subscription that was never saved is an explicit error")
    func deleteMissing() async throws {
        let (store, _) = try makeStore()
        await #expect(throws: RepositoryError.subscriptionNotFound(try fixtureUUID(42))) {
            try await store.deleteSubscription(withID: try fixtureUUID(42), at: Date(timeIntervalSince1970: 0))
        }
    }

    @Test("a deleted payment method is filtered and retrievable the same way")
    func paymentMethodTombstone() async throws {
        let (store, _) = try makeStore()
        let method = try makePaymentMethod(label: "Visa ..1234", isDefault: false)
        try await store.save(method)

        try await store.deletePaymentMethod(withID: method.id, at: Date(timeIntervalSince1970: 9_000))

        #expect(try await store.paymentMethods() == [])
        #expect(try await store.paymentMethod(withID: method.id) == nil)
        var tombstoned = method
        tombstoned.deletedAt = Date(timeIntervalSince1970: 9_000)
        #expect(try await store.paymentMethodsIncludingDeleted() == [tombstoned])
    }

    @Test("a saved cancellation record clears any tombstone - the slot is live again")
    func cancellationResurrection() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(status: .cancellationPending, cycleStartDay: try day(2026, 5, 20))
        try await store.save(subscription)
        let record = try makeCancellationEpisode(
            subscriptionID: subscription.id, nextChargeDateIfNotCancelled: try day(2026, 9, 20)
        )
        try await store.save(record)
        try await store.deleteSubscription(withID: subscription.id, at: Date(timeIntervalSince1970: 9_000))
        #expect(try await store.openEpisode(forSubscription: subscription.id) == nil)

        try await store.save(record)

        #expect(try await store.openEpisode(forSubscription: subscription.id) == record)
    }
}
