import Foundation
import OttoDomain
import OttoRepositories
import SwiftData

extension OttoStore: SubscriptionRepository {
    public func save(_ subscription: Subscription) async throws {
        let record: StoredSubscription
        if let existing = try storedSubscription(id: subscription.id, includingDeleted: true) {
            record = existing
        } else {
            record = StoredSubscription()
            modelContext.insert(record)
        }
        record.update(from: subscription)
        // The watermark is untouched here (spec §5.3, Wave 6B-Prep): the domain
        // value no longer carries it, and a save can neither advance nor lose
        // this device's ledger progress. Entry initialisation and edit rewinds
        // go through the explicit watermark operations.
        try modelContext.save()
    }

    public func subscription(withID id: UUID) async throws -> Subscription? {
        guard let record = try storedSubscription(id: id, includingDeleted: false) else { return nil }
        return mapSkippingFailures([record], { try $0.toDomain() }).first
    }

    public func subscriptions() async throws -> [Subscription] {
        try fetchSubscriptions(#Predicate { $0.deletedAt == nil })
    }

    public func subscriptionsIncludingDeleted() async throws -> [Subscription] {
        try fetchSubscriptions(nil)
    }

    public func unreadableSubscriptionCount() async throws -> Int {
        let records = try modelContext.fetch(
            FetchDescriptor<StoredSubscription>(predicate: #Predicate { $0.deletedAt == nil })
        )
        // The same mapping `subscriptions()` performs, counted instead of skipped:
        // whatever that read drops, this read reports (spec §5.2b, v1.4).
        return records.count { (try? $0.toDomain()) == nil }
    }

    public func subscriptionReadRepairs() async throws -> [SubscriptionReadRepairReport] {
        let records = try modelContext.fetch(
            FetchDescriptor<StoredSubscription>(predicate: #Predicate { $0.deletedAt == nil })
        )
        // The same mapping `subscriptions()` performs, reporting what it
        // repaired instead of discarding the notes (spec §4a, Wave 6B-Prep).
        return records.compactMap { record in
            var repairs: [SubscriptionReadRepair] = []
            guard let value = try? record.toDomain(collecting: &repairs), !repairs.isEmpty else {
                return nil
            }
            return SubscriptionReadRepairReport(
                subscriptionID: value.id, name: value.name, repairs: repairs
            )
        }
        .sorted { ($0.name, $0.subscriptionID.uuidString) < ($1.name, $1.subscriptionID.uuidString) }
    }

    public func deleteSubscription(withID id: UUID, at instant: Date) async throws {
        guard let record = try storedSubscription(id: id, includingDeleted: true) else {
            throw RepositoryError.subscriptionNotFound(id)
        }
        // The tombstone cascades to every child, preserving any earlier tombstone's
        // instant. Hard deletes happen nowhere (spec §3.5).
        setIfLive(&record.deletedAt, notBefore: record.createdAt, instant)
        if let trial = record.trial { setIfLive(&trial.deletedAt, notBefore: trial.createdAt, instant) }
        for episode in record.cancellationEpisodes ?? [] {
            setIfLive(&episode.deletedAt, notBefore: episode.createdAt, instant)
        }
        for episode in record.pauseEpisodes ?? [] {
            setIfLive(&episode.deletedAt, notBefore: episode.createdAt, instant)
        }
        for event in record.billingEvents ?? [] {
            setIfLive(&event.deletedAt, notBefore: event.createdAt, instant)
        }
        for change in record.priceChanges ?? [] {
            setIfLive(&change.deletedAt, notBefore: change.createdAt, instant)
        }
        try modelContext.save()
    }

    /// A tombstone never predates the record it closes (docs/sync-safety.md):
    /// a device clock set back behind the row's own creation would otherwise
    /// write `deletedAt < createdAt`, the shape found in real exported data.
    private func setIfLive(_ deletedAt: inout Date?, notBefore createdAt: Date?, _ instant: Date) {
        if deletedAt == nil { deletedAt = monotonicStamp(instant, notBefore: createdAt) }
    }

    private func fetchSubscriptions(_ predicate: Predicate<StoredSubscription>?) throws -> [Subscription] {
        let records = try modelContext.fetch(FetchDescriptor<StoredSubscription>(predicate: predicate))
        return mapSkippingFailures(records) { try $0.toDomain() }
            .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
    }
}
