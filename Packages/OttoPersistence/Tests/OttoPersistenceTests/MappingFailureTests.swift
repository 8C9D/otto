import Foundation
import OttoDomain
import SwiftData
import Testing
@testable import OttoPersistence

extension SerializedPersistenceTests {
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
            let (store, containers) = try makeStore()
            try await store.save(try makeSubscription(cycleStartDay: try day(2026, 8, 15)))
            let context = ModelContext(containers.main)
            let record = try #require(try context.fetch(FetchDescriptor<StoredSubscription>()).first)
            record.cycleStartDay = 20260230
            #expect(throws: MappingError.self) {
                try record.toDomain()
            }
        }

        @Test("an unknown enum raw string throws .invalidValue - never a silent fallback")
        func unknownRawThrows() async throws {
            let (store, containers) = try makeStore()
            try await store.save(try makeSubscription(cycleStartDay: try day(2026, 8, 15)))
            let context = ModelContext(containers.main)
            let record = try #require(try context.fetch(FetchDescriptor<StoredSubscription>()).first)
            record.status = "hibernating"
            #expect(throws: MappingError.self) {
                try record.toDomain()
            }
        }

        @Test("a list read skips the unmappable record and returns the rest")
        func readSkipsBadRecord() async throws {
            let containers = try OttoContainerFactory.inMemoryContainers()
            let context = ModelContext(containers.main)

            let partial = StoredSubscription()
            partial.id = try fixtureUUID(1)
            context.insert(partial)
            try context.save()

            let store = OttoStore(containers: containers)
            try await store.save(try makeSubscription(index: 2, cycleStartDay: try day(2026, 8, 15)))

            let loaded = try await store.subscriptions()
            #expect(loaded.map(\.id) == [try fixtureUUID(2)])
        }

        @Test("whatever the list read drops, the unreadable count reports (spec §5.2b, v1.4)")
        func unreadableCountMatchesSkippedRecords() async throws {
            let containers = try OttoContainerFactory.inMemoryContainers()
            let context = ModelContext(containers.main)
            let store = OttoStore(containers: containers)
            try await store.save(try makeSubscription(index: 2, cycleStartDay: try day(2026, 8, 15)))
            #expect(try await store.unreadableSubscriptionCount() == 0)

            let partial = StoredSubscription()
            partial.id = try fixtureUUID(1)
            context.insert(partial)
            // A tombstoned unmappable record is not missing from any list the user
            // sees, so it must not inflate the count.
            let deletedPartial = StoredSubscription()
            deletedPartial.id = try fixtureUUID(3)
            deletedPartial.deletedAt = Date(timeIntervalSince1970: 9_000)
            context.insert(deletedPartial)
            try context.save()

            let fresh = OttoStore(containers: containers)
            #expect(try await fresh.unreadableSubscriptionCount() == 1)
            #expect(try await fresh.subscriptions().count == 1)
        }

        @Test("a single-record fetch treats an unmappable record as absent")
        func fetchSkipsBadRecord() async throws {
            let containers = try OttoContainerFactory.inMemoryContainers()
            let context = ModelContext(containers.main)

            let partial = StoredSubscription()
            partial.id = try fixtureUUID(1)
            context.insert(partial)
            try context.save()

            let store = OttoStore(containers: containers)
            #expect(try await store.subscription(withID: try fixtureUUID(1)) == nil)
        }

        @Test("one bad billing event does not take down the subscription's ledger read")
        func eventReadSkipsBadRow() async throws {
            let (store, containers) = try makeStore()
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 8, 15))
            try await store.save(subscription)
            try await store.save(try makeBillingEvent(subscriptionID: subscription.id, expectedDate: try day(2026, 9, 15)))

            let context = ModelContext(containers.main)
            let bad = StoredBillingEvent()
            bad.id = try fixtureUUID(999)
            bad.subscriptionID = subscription.id
            // state and expectedDate deliberately left nil
            context.insert(bad)
            try context.save()

            let fresh = OttoStore(containers: containers)
            let events = try await fresh.events(forSubscription: subscription.id)
            #expect(events.map(\.id) == [try fixtureUUID(100)])
        }

        @Test("a stored .trial subscription with no trial term reads degraded, never unreadable (spec §4a)")
        func trialWithoutTermReadsDegraded() async throws {
            let (store, containers) = try makeStore()
            let trial = try makeTrialTerm(startDate: try day(2026, 8, 1))
            try await store.save(try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial))

            // Simulate the parent arriving before its trial child (ordinary
            // under per-record sync): the status says .trial but the term is
            // gone. Before v2.0 this refused the whole record - a sync
            // artifact became a dead subscription on every device.
            let context = ModelContext(containers.main)
            let record = try #require(try context.fetch(FetchDescriptor<StoredSubscription>()).first)
            record.trial = nil
            try context.save()

            let fresh = OttoStore(containers: containers)
            let loaded = try #require(try await fresh.subscriptions().first)
            // Readable, as a trial that never reaches conversion until the
            // term arrives - nothing is invented, and nothing is refused.
            #expect(loaded.storedStatus == .trial)
            #expect(loaded.trial == nil)
            #expect(try await fresh.unreadableSubscriptionCount() == 0)
            let reports = try await fresh.subscriptionReadRepairs()
            #expect(reports.map(\.repairs) == [[.trialWithoutTerm]])
        }

        @Test("a subscription whose trial record is unmappable is itself skipped, not half-loaded")
        func brokenTrialSkipsSubscription() async throws {
            let (store, containers) = try makeStore()
            let trial = try makeTrialTerm(startDate: try day(2026, 8, 1))
            try await store.save(try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial))

            let context = ModelContext(containers.main)
            let storedTrial = try #require(try context.fetch(FetchDescriptor<StoredTrialTerm>()).first)
            storedTrial.lengthDays = nil
            try context.save()

            let fresh = OttoStore(containers: containers)
            // A subscription claiming a trial it cannot produce would be a lie; skipping
            // the whole record is the documented policy.
            #expect(try await fresh.subscriptions() == [])
        }
    }
}
