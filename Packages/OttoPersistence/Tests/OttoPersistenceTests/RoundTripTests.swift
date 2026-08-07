import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

extension SerializedPersistenceTests {
    @Suite("Round-trips: domain -> persistence -> domain, unchanged")
    struct RoundTripTests {

        @Test("a fully populated subscription with a trial survives unchanged")
        func subscriptionFull() async throws {
            let (store, _) = try makeStore()
            let trial = try makeTrialTerm(startDate: try day(2026, 8, 1))
            let original = try makeSubscription(
                status: .trial,
                cycleStartDay: try day(2026, 8, 1),
                trial: trial
            )

            try await store.save(original)
            let loaded = try await store.subscription(withID: original.id)

            #expect(loaded == original)
        }

        @Test("a minimal subscription - every optional nil - survives unchanged")
        func subscriptionMinimal() async throws {
            let (store, _) = try makeStore()
            let original = Subscription(
                id: try fixtureUUID(1),
                name: "Bare",
                category: .other,
                status: .active,
                amountCents: 500,
                currencyCode: "CAD",
                cycle: .annual,
                cycleStartDay: try day(2026, 2, 28),
                reminderLeadDays: 3,
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0)
            )

            try await store.save(original)
            let loaded = try await store.subscription(withID: original.id)

            #expect(loaded == original)
        }

        @Test("saving twice updates in place rather than duplicating")
        func subscriptionUpsert() async throws {
            let (store, _) = try makeStore()
            var subscription = try makeSubscription(cycleStartDay: try day(2026, 8, 15))
            try await store.save(subscription)

            subscription.amountCents = 1299
            subscription.notes = nil
            subscription.updatedAt = Date(timeIntervalSince1970: 5_000)
            try await store.save(subscription)

            let all = try await store.subscriptions()
            #expect(all == [subscription])
        }

        @Test("removing the trial on save soft-deletes its record, and a re-added trial reuses it")
        func trialLifecycle() async throws {
            let (store, containers) = try makeStore()
            let trial = try makeTrialTerm(startDate: try day(2026, 8, 1))
            var subscription = try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial)
            try await store.save(subscription)

            subscription.trial = nil
            subscription.storedStatus = .active
            try await store.save(subscription)
            #expect(try await store.subscription(withID: subscription.id)?.trial == nil)

            let context = ModelContext(containers.main)
            let storedTrials = try context.fetch(FetchDescriptor<StoredTrialTerm>())
            #expect(storedTrials.count == 1)
            #expect(storedTrials.first?.deletedAt == subscription.updatedAt)

            subscription.trial = trial
            subscription.storedStatus = .trial
            try await store.save(subscription)
            #expect(try await store.subscription(withID: subscription.id)?.trial == trial)
        }

        @Test("a billing event survives unchanged")
        func billingEvent() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 8, 15))
            try await store.save(subscription)
            let original = try makeBillingEvent(subscriptionID: subscription.id, expectedDate: try day(2026, 12, 31))

            try await store.save(original)
            let loaded = try await store.events(forSubscription: subscription.id)

            #expect(loaded == [original])
        }

        @Test("a billing event for an unsaved subscription is refused")
        func billingEventWithoutParent() async throws {
            let (store, _) = try makeStore()
            let orphan = try makeBillingEvent(subscriptionID: try fixtureUUID(7), expectedDate: try day(2026, 9, 1))

            await #expect(throws: RepositoryError.subscriptionNotFound(try fixtureUUID(7))) {
                try await store.save(orphan)
            }
        }

        @Test("a cancellation record survives unchanged")
        func cancellationEpisode() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(status: .cancellationPending, cycleStartDay: try day(2026, 5, 20))
            try await store.save(subscription)
            // Non-default v1.3 fields included, so the round-trip proves they persist.
            let original = try makeCancellationEpisode(
                subscriptionID: subscription.id,
                nextChargeDateIfNotCancelled: try day(2026, 9, 20),
                verificationState: .needsManualReview,
                unansweredCheckCount: 3,
                evidenceNote: "confirmation #12345"
            )

            try await store.save(original)
            let loaded = try await store.openEpisode(forSubscription: subscription.id)

            #expect(loaded == original)
        }

        @Test("a price change survives unchanged")
        func priceChange() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 8, 15))
            try await store.save(subscription)
            let original = try makePriceChange(
                subscriptionID: subscription.id,
                effectiveDate: try day(2026, 10, 1),
                source: .chargeMismatch,
                note: "vendor raised the price"
            )

            try await store.append(original)
            let loaded = try await store.history(forSubscription: subscription.id)

            #expect(loaded == [original])
        }

        @Test("a payment method survives unchanged")
        func paymentMethod() async throws {
            let (store, _) = try makeStore()
            let original = try makePaymentMethod()

            try await store.save(original)
            let loaded = try await store.paymentMethod(withID: original.id)

            #expect(loaded == original)
        }
    }
}
