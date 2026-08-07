import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

@Suite("BillingEvent materialization (spec §5.3)")
struct MaterializationTests {

    @Test("rows are created for every billing date inside the horizon and none beyond it")
    func horizonCoverage() async throws {
        let (store, _) = try makeStore()
        // Jan 31 monthly exercises the clamp: inside [Aug 6, Nov 4] the charges are
        // Aug 31, Sep 30, Oct 31.
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
        try await store.save(subscription)

        let created = try await store.materializeEvents(for: subscription, from: try day(2026, 8, 6), horizonDays: 90)

        let expectedDates = [try day(2026, 8, 31), try day(2026, 9, 30), try day(2026, 10, 31)]
        #expect(created.map(\.expectedDate) == expectedDates)
        #expect(created.allSatisfy { $0.state == .upcoming })
        #expect(created.allSatisfy { $0.expectedAmountCents == subscription.amountCents })
        #expect(created.allSatisfy { $0.subscriptionID == subscription.id })

        let persisted = try await store.events(forSubscription: subscription.id)
        #expect(persisted.map(\.expectedDate) == expectedDates)
    }

    @Test("a charge landing today is materialized - today is inside the horizon")
    func includesToday() async throws {
        let (store, _) = try makeStore()
        let today = try day(2026, 8, 6)
        let subscription = try makeSubscription(cycleStartDay: today)
        try await store.save(subscription)

        let created = try await store.materializeEvents(for: subscription, from: today, horizonDays: 90)

        #expect(created.first?.expectedDate == today)
    }

    @Test("re-running is idempotent and creates no duplicates")
    func idempotent() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
        try await store.save(subscription)
        let today = try day(2026, 8, 6)

        let first = try await store.materializeEvents(for: subscription, from: today, horizonDays: 90)
        let second = try await store.materializeEvents(for: subscription, from: today, horizonDays: 90)

        #expect(first.count == 3)
        #expect(second == [])
        #expect(try await store.events(forSubscription: subscription.id).count == 3)
    }

    @Test("a longer horizon on a later run creates only the missing rows")
    func extendingHorizon() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
        try await store.save(subscription)
        let today = try day(2026, 8, 6)

        let first = try await store.materializeEvents(for: subscription, from: today, horizonDays: 30)
        let second = try await store.materializeEvents(for: subscription, from: today, horizonDays: 90)

        #expect(first.map(\.expectedDate) == [try day(2026, 8, 31)])
        #expect(second.map(\.expectedDate) == [try day(2026, 9, 30), try day(2026, 10, 31)])
    }

    @Test("a soft-deleted row is never resurrected by re-materialization")
    func tombstoneNotResurrected() async throws {
        let (store, container) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
        try await store.save(subscription)
        let today = try day(2026, 8, 6)
        _ = try await store.materializeEvents(for: subscription, from: today, horizonDays: 90)

        let context = ModelContext(container)
        let events = try context.fetch(FetchDescriptor<StoredBillingEvent>())
        let target = try #require(events.first { $0.expectedDate == 20260930 })
        target.deletedAt = Date(timeIntervalSince1970: 9_000)
        try context.save()

        let fresh = OttoStore(modelContainer: container)
        let created = try await fresh.materializeEvents(for: subscription, from: today, horizonDays: 90)

        #expect(created == [])
        #expect(try await fresh.events(forSubscription: subscription.id).count == 2)
    }

    @Test("only an active subscription materializes rows", arguments: [
        SubscriptionStatus.trial, .paused, .cancellationPending, .cancelled, .archived
    ])
    func nonActiveStatusesMaterializeNothing(status: SubscriptionStatus) async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(status: status, cycleStartDay: try day(2026, 1, 31))
        try await store.save(subscription)

        let created = try await store.materializeEvents(for: subscription, from: try day(2026, 8, 6), horizonDays: 90)

        #expect(created == [])
        #expect(try await store.events(forSubscription: subscription.id) == [])
    }

    @Test("materializing for an unsaved subscription is an explicit error")
    func unsavedSubscription() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))

        await #expect(throws: RepositoryError.subscriptionNotFound(subscription.id)) {
            _ = try await store.materializeEvents(for: subscription, from: try day(2026, 8, 6), horizonDays: 90)
        }
    }

    @Test("an anchor beyond the horizon produces nothing - rows past the horizon do not exist")
    func anchorBeyondHorizon() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2027, 3, 1))
        try await store.save(subscription)

        let created = try await store.materializeEvents(for: subscription, from: try day(2026, 8, 6), horizonDays: 90)

        #expect(created == [])
    }
}
