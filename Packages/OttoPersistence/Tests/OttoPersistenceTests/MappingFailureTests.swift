import Foundation
import OttoDomain
import SwiftData
import Testing
@testable import OttoPersistence

@Suite("Mapping failures: nil required fields throw in mapping, and reads skip the record")
struct MappingFailureTests {

    @Test("a record missing a required field throws .missingField from the mapping layer")
    func missingFieldThrows() throws {
        let record = StoredSubscription()
        record.id = try fixtureUUID(1)
        // name deliberately left nil
        #expect(throws: MappingError.self) {
            try record.toDomain()
        }
    }

    @Test("a record holding an impossible date throws .invalidValue from the mapping layer")
    func invalidValueThrows() async throws {
        let (store, container) = try makeStore()
        try await store.save(try makeSubscription(cycleStartDay: try day(2026, 8, 15)))
        let context = ModelContext(container)
        let record = try #require(try context.fetch(FetchDescriptor<StoredSubscription>()).first)
        record.cycleStartDay = 20260230
        #expect(throws: MappingError.self) {
            try record.toDomain()
        }
    }

    @Test("an unknown enum raw string throws .invalidValue - never a silent fallback")
    func unknownRawThrows() async throws {
        let (store, container) = try makeStore()
        try await store.save(try makeSubscription(cycleStartDay: try day(2026, 8, 15)))
        let context = ModelContext(container)
        let record = try #require(try context.fetch(FetchDescriptor<StoredSubscription>()).first)
        record.status = "hibernating"
        #expect(throws: MappingError.self) {
            try record.toDomain()
        }
    }

    @Test("a list read skips the unmappable record and returns the rest")
    func readSkipsBadRecord() async throws {
        let container = try OttoContainerFactory.inMemoryContainer()
        let context = ModelContext(container)

        let partial = StoredSubscription()
        partial.id = try fixtureUUID(1)
        context.insert(partial)
        try context.save()

        let store = OttoStore(modelContainer: container)
        try await store.save(try makeSubscription(index: 2, cycleStartDay: try day(2026, 8, 15)))

        let loaded = try await store.subscriptions()
        #expect(loaded.map(\.id) == [try fixtureUUID(2)])
    }

    @Test("a single-record fetch treats an unmappable record as absent")
    func fetchSkipsBadRecord() async throws {
        let container = try OttoContainerFactory.inMemoryContainer()
        let context = ModelContext(container)

        let partial = StoredSubscription()
        partial.id = try fixtureUUID(1)
        context.insert(partial)
        try context.save()

        let store = OttoStore(modelContainer: container)
        #expect(try await store.subscription(withID: try fixtureUUID(1)) == nil)
    }

    @Test("one bad billing event does not take down the subscription's ledger read")
    func eventReadSkipsBadRow() async throws {
        let (store, container) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 8, 15))
        try await store.save(subscription)
        try await store.save(try makeBillingEvent(subscriptionID: subscription.id, expectedDate: try day(2026, 9, 15)))

        let context = ModelContext(container)
        let bad = StoredBillingEvent()
        bad.id = try fixtureUUID(999)
        bad.subscriptionID = subscription.id
        // state and expectedDate deliberately left nil
        context.insert(bad)
        try context.save()

        let fresh = OttoStore(modelContainer: container)
        let events = try await fresh.events(forSubscription: subscription.id)
        #expect(events.map(\.id) == [try fixtureUUID(100)])
    }

    @Test("a subscription whose trial record is unmappable is itself skipped, not half-loaded")
    func brokenTrialSkipsSubscription() async throws {
        let (store, container) = try makeStore()
        let trial = try #require(TrialTerm(
            startDate: try day(2026, 8, 1), lengthDays: 14, bufferDays: 2, convertsToAmountCents: 1599
        ))
        try await store.save(try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial))

        let context = ModelContext(container)
        let storedTrial = try #require(try context.fetch(FetchDescriptor<StoredTrialTerm>()).first)
        storedTrial.lengthDays = nil
        try context.save()

        let fresh = OttoStore(modelContainer: container)
        // A subscription claiming a trial it cannot produce would be a lie; skipping
        // the whole record is the documented policy.
        #expect(try await fresh.subscriptions() == [])
    }
}
