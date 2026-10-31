import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

/// The long-lived `OttoStore` context must see what a CloudKit import commits,
/// because the import is written by the framework's own context, not this one.
///
/// A second context over the same container is the closest a host test gets to
/// that writer. This was feared to be a Wave 6B blocker - a registered object
/// keeping its cached values - and measured false, fields and relationships
/// both, so these pin the measurement. They are a stand-in: the real import is
/// covered only by `docs/sync-verification.md`'s two-device run.
extension SerializedPersistenceTests {
    @Suite("Another writer's commits reach the store's context (spec §8, Wave 6B)")
    struct RemoteWriteVisibilityTests {

        private func onDiskStore() throws -> (store: OttoStore, containers: OttoContainers) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let containers = try containerCreationLock.withLock {
                try OttoContainerFactory.onDiskContainers(
                    mainURL: directory.appendingPathComponent("main.store"),
                    deviceStateURL: directory.appendingPathComponent("device.store")
                )
            }
            return (OttoStore(containers: containers, syncState: { SyncState() }), containers)
        }

        private func storedSubscription(_ id: UUID, in context: ModelContext) throws -> StoredSubscription {
            try #require(try context.fetch(
                FetchDescriptor<StoredSubscription>(predicate: #Predicate { $0.id == id })
            ).first)
        }

        @Test("an edited field and a changed ledger row are read fresh")
        func editedFieldsAreFresh() async throws {
            let (store, containers) = try onDiskStore()
            let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await store.save(subscription)
            let event = try makeBillingEvent(
                index: 101, subscriptionID: subscription.id, expectedDate: try day(2026, 12, 15)
            )
            try await store.save(event)
            // Both read through the store first, so its context has seen them.
            _ = try await store.subscriptions()
            _ = try await store.events(forSubscription: subscription.id)

            let writer = ModelContext(containers.main)
            try storedSubscription(subscription.id, in: writer).name = "Edited elsewhere"
            let eventID = event.id
            let row = try #require(try writer.fetch(
                FetchDescriptor<StoredBillingEvent>(predicate: #Predicate { $0.id == eventID })
            ).first)
            row.actualAmountCents = 4242
            try writer.save()

            #expect(try await store.subscription(withID: subscription.id)?.name == "Edited elsewhere")
            #expect(try await store.events(forSubscription: subscription.id).first?.actualAmountCents == 4242)
        }

        @Test("a child arriving through a relationship the store already faulted is seen")
        func arrivingChildIsSeen() async throws {
            let (store, containers) = try onDiskStore()
            let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await store.save(subscription)
            #expect(try await store.subscription(withID: subscription.id)?.pauseEpisodes.isEmpty == true)

            let writer = ModelContext(containers.main)
            let record = try storedSubscription(subscription.id, in: writer)
            let episode = StoredPauseEpisode()
            writer.insert(episode)
            episode.id = UUID()
            episode.startedOn = 20260201
            episode.createdAt = Date(timeIntervalSince1970: 5_000)
            episode.updatedAt = Date(timeIntervalSince1970: 5_000)
            episode.subscription = record
            record.status = SubscriptionStatus.paused.rawValue
            try writer.save()

            #expect(try await store.subscription(withID: subscription.id)?.pauseEpisodes.count == 1)
            #expect(try await store.completeSnapshot().subscriptions.first?.pauseEpisodes.count == 1)
        }
    }
}
