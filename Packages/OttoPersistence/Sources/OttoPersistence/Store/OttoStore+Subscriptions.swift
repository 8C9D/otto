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
        // The watermark lives in the device-state store (spec §5.3, Wave 6A),
        // written BEFORE the main save: no flow ever advances a watermark
        // through save() (edits rewind it, imports preserve it, and only
        // materialization advances it), so a crash between the two saves can
        // only leave a REGRESSED watermark - the harmless direction.
        try setDeviceWatermark(subscription.lastMaterializedThrough, for: subscription.id)
        try modelContext.save()
    }

    public func subscription(withID id: UUID) async throws -> Subscription? {
        guard let record = try storedSubscription(id: id, includingDeleted: false) else { return nil }
        guard var value = mapSkippingFailures([record], { try $0.toDomain() }).first else { return nil }
        value.lastMaterializedThrough = try deviceWatermark(for: id)
        return value
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

    public func deleteSubscription(withID id: UUID, at instant: Date) async throws {
        guard let record = try storedSubscription(id: id, includingDeleted: true) else {
            throw RepositoryError.subscriptionNotFound(id)
        }
        // The tombstone cascades to every child, preserving any earlier tombstone's
        // instant. Hard deletes happen nowhere (spec §3.5).
        setIfLive(&record.deletedAt, instant)
        if let trial = record.trial { setIfLive(&trial.deletedAt, instant) }
        for episode in record.cancellationEpisodes ?? [] { setIfLive(&episode.deletedAt, instant) }
        for episode in record.pauseEpisodes ?? [] { setIfLive(&episode.deletedAt, instant) }
        for event in record.billingEvents ?? [] { setIfLive(&event.deletedAt, instant) }
        for change in record.priceChanges ?? [] { setIfLive(&change.deletedAt, instant) }
        try modelContext.save()
    }

    private func setIfLive(_ deletedAt: inout Date?, _ instant: Date) {
        if deletedAt == nil { deletedAt = instant }
    }

    private func fetchSubscriptions(_ predicate: Predicate<StoredSubscription>?) throws -> [Subscription] {
        let records = try modelContext.fetch(FetchDescriptor<StoredSubscription>(predicate: predicate))
        return try joiningDeviceWatermarks(
            mapSkippingFailures(records) { try $0.toDomain() }
                .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
        )
    }
}
