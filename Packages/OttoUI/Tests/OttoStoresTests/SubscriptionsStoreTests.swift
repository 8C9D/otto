import Foundation
import Testing
import OttoDomain
@testable import OttoStores

@MainActor
@Suite("SubscriptionsStore: explicit states, repository-only mutations")
struct SubscriptionsStoreTests {

    private struct Fixture {
        let store: SubscriptionsStore
        let subscriptions: MockSubscriptionRepository
        let cancellations: MockCancellationRepository
    }

    private func makeStore() throws -> Fixture {
        let subscriptions = MockSubscriptionRepository()
        let cancellations = MockCancellationRepository()
        let store = SubscriptionsStore(
            subscriptionRepository: subscriptions,
            cancellationRepository: cancellations,
            dates: try fixedDates()
        )
        return Fixture(store: store, subscriptions: subscriptions, cancellations: cancellations)
    }

    @Test("before the first refresh the state is loading - never an implicit empty")
    func startsLoading() throws {
        let store = try makeStore().store
        #expect(store.subscriptions.isLoading)
        #expect(store.subscriptions.value == nil)
        #expect(store.overview == nil)
    }

    @Test("an empty repository loads as an explicit empty list, distinct from loading")
    func loadsEmpty() async throws {
        let store = try makeStore().store
        await store.refresh()
        #expect(store.subscriptions.value?.isEmpty == true)
        #expect(!store.subscriptions.isLoading)
    }

    @Test("refresh loads subscriptions and the cancellation records that go with them")
    func loadsData() async throws {
        let fixture = try makeStore()
        let (store, subscriptions, cancellations) = (fixture.store, fixture.subscriptions, fixture.cancellations)
        let active = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        let cancelled = try makeSubscription(index: 2, status: .cancelled, cycleStartDay: try day(2026, 5, 20))
        let record = try makeCancellationRecord(
            subscriptionID: cancelled.id, nextChargeDateIfNotCancelled: try day(2026, 8, 20)
        )
        await subscriptions.seed([active, cancelled])
        await cancellations.seed([record])

        await store.refresh()

        #expect(store.subscriptions.value == [active, cancelled])
        #expect(store.cancellations == [cancelled.id: record])
        #expect(store.overview != nil)
    }

    @Test("a repository error surfaces as failed - never as an empty list")
    func errorSurfaces() async throws {
        let fixture = try makeStore()
        let (store, subscriptions) = (fixture.store, fixture.subscriptions)
        await subscriptions.fail(with: TestFailure())

        await store.refresh()

        #expect(store.subscriptions.error is TestFailure)
        #expect(store.subscriptions.value == nil)
    }

    @Test("a cancellation-repository error also fails the load rather than dropping records")
    func cancellationErrorSurfaces() async throws {
        let fixture = try makeStore()
        let (store, subscriptions, cancellations) = (fixture.store, fixture.subscriptions, fixture.cancellations)
        let cancelled = try makeSubscription(index: 1, status: .cancelled, cycleStartDay: try day(2026, 5, 20))
        await subscriptions.seed([cancelled])
        await cancellations.fail(with: TestFailure())

        await store.refresh()

        #expect(store.subscriptions.error is TestFailure)
    }

    @Test("recovering from a failure loads normally on the next refresh")
    func recovery() async throws {
        let fixture = try makeStore()
        let (store, subscriptions) = (fixture.store, fixture.subscriptions)
        await subscriptions.fail(with: TestFailure())
        await store.refresh()
        #expect(store.subscriptions.error != nil)

        await subscriptions.recover()
        await store.refresh()
        #expect(store.subscriptions.value == [])
    }

    @Test("save writes through the repository and the new subscription appears on refresh")
    func saveThenRefresh() async throws {
        let fixture = try makeStore()
        let (store, subscriptions) = (fixture.store, fixture.subscriptions)
        await store.refresh()
        let added = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))

        try await store.save(added)

        #expect(await subscriptions.savedValues == [added])
        #expect(store.subscriptions.value == [added])
    }

    @Test("a failed save throws to the caller and leaves the published state untouched")
    func failedSave() async throws {
        let fixture = try makeStore()
        let (store, subscriptions) = (fixture.store, fixture.subscriptions)
        let existing = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await subscriptions.seed([existing])
        await store.refresh()

        await subscriptions.fail(with: TestFailure())
        await #expect(throws: TestFailure.self) {
            try await store.save(try makeSubscription(index: 2, cycleStartDay: try day(2026, 2, 1)))
        }

        #expect(store.subscriptions.value == [existing])
    }

    @Test("delete tombstones at the provider's instant and the list refreshes without it")
    func delete() async throws {
        let fixture = try makeStore()
        let (store, subscriptions) = (fixture.store, fixture.subscriptions)
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await subscriptions.seed([subscription])
        await store.refresh()

        try await store.delete(subscriptionID: subscription.id)

        #expect(store.subscriptions.value == [])
        let tombstone = try await subscriptions.subscriptionsIncludingDeleted().first
        #expect(tombstone?.deletedAt == Date(timeIntervalSince1970: 10_000))
    }
}
