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
        let billingEvents: MockBillingEventRepository
    }

    private func makeStore() throws -> Fixture {
        let subscriptions = MockSubscriptionRepository()
        let cancellations = MockCancellationRepository()
        let billingEvents = MockBillingEventRepository()
        let store = SubscriptionsStore(
            subscriptionRepository: subscriptions,
            cancellationRepository: cancellations,
            billingEventRepository: billingEvents,
            dates: try fixedDates()
        )
        return Fixture(
            store: store, subscriptions: subscriptions,
            cancellations: cancellations, billingEvents: billingEvents
        )
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

    @Test("unreadable records surface as a count, never silently (spec §5.2b, v1.4)")
    func surfacesUnreadableCount() async throws {
        let fixture = try makeStore()
        await fixture.subscriptions.primeUnreadableCount(2)
        await fixture.store.refresh()
        #expect(fixture.store.unreadableCount == 2)

        await fixture.subscriptions.primeUnreadableCount(0)
        await fixture.store.refresh()
        #expect(fixture.store.unreadableCount == 0)
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

    @Test("an edit that moves the billing sequence earlier rewinds the watermark at save (spec §5.3, v1.7)")
    func editRewindsWatermark() async throws {
        let fixture = try makeStore()
        let old = try makeSubscription(
            index: 1,
            status: .paused,
            cycleStartDay: try day(2026, 1, 1),
            pauseEndsOn: try day(2026, 12, 1),
            lastMaterializedThrough: try day(2026, 12, 15)
        )
        await fixture.subscriptions.seed([old])
        await fixture.billingEvents.seed([
            try makeBillingEvent(subscriptionID: old.id, expectedDate: try day(2026, 1, 1))
        ])

        var edited = old
        edited.pauseEndsOn = try day(2026, 9, 1)
        try await fixture.store.save(edited)

        let saved = try #require(await fixture.subscriptions.savedValues.last)
        #expect(saved.lastMaterializedThrough == (try day(2026, 8, 31)))
    }

    @Test("a save never advances the stored watermark - only a ledger pass does")
    func saveNeverAdvancesWatermark() async throws {
        let fixture = try makeStore()
        let stored = try makeSubscription(
            index: 1,
            cycleStartDay: try day(2026, 1, 1),
            lastMaterializedThrough: try day(2026, 9, 10)
        )
        await fixture.subscriptions.seed([stored])

        var incoming = stored
        incoming.lastMaterializedThrough = try day(2026, 12, 1)
        try await fixture.store.save(incoming)

        let saved = try #require(await fixture.subscriptions.savedValues.last)
        #expect(saved.lastMaterializedThrough == (try day(2026, 9, 10)))
    }

    @Test("a status transition through save keeps the flows' watermark semantics")
    func transitionSaveLeavesWatermark() async throws {
        // An indefinitely paused record's watermark is frozen; a hypothetical
        // edit-path resume must not let the sequence diff rewind it to the anchor.
        let fixture = try makeStore()
        let paused = try makeSubscription(
            index: 1,
            status: .paused,
            cycleStartDay: try day(2026, 1, 1),
            lastMaterializedThrough: try day(2026, 8, 20)
        )
        await fixture.subscriptions.seed([paused])
        await fixture.billingEvents.seed([
            try makeBillingEvent(subscriptionID: paused.id, expectedDate: try day(2026, 1, 1))
        ])

        var resumed = paused
        resumed.storedStatus = .active
        try await fixture.store.save(resumed)

        let saved = try #require(await fixture.subscriptions.savedValues.last)
        #expect(saved.lastMaterializedThrough == (try day(2026, 8, 20)))
    }

    @Test("save and delete fire the mutation hook - the store is the §6.2 reschedule trigger")
    func mutationsTriggerReschedule() async throws {
        let fixture = try makeStore()
        let (store, subscriptions) = (fixture.store, fixture.subscriptions)
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await subscriptions.seed([subscription])
        await store.refresh()

        var mutations = 0
        store.onMutation = { mutations += 1 }

        try await store.save(try makeSubscription(index: 2, cycleStartDay: try day(2026, 2, 1)))
        try await store.delete(subscriptionID: subscription.id)
        #expect(mutations == 2)

        // A failed write must NOT trigger a reschedule - nothing changed.
        await subscriptions.fail(with: TestFailure())
        await #expect(throws: TestFailure.self) {
            try await store.save(try makeSubscription(index: 3, cycleStartDay: try day(2026, 3, 1)))
        }
        #expect(mutations == 2)
    }
}
