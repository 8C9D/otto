import Foundation
import OttoDomain
import OttoRepositories
import SwiftData

extension OttoStore: DataTransferRepository {

    /// Every record in the store as domain values, tombstones included. Reads
    /// here THROW on a mapping failure instead of skipping (the one read that
    /// does): an export with a silently missing row is a backup with a hole in
    /// it, discovered exactly when the backup is needed.
    public func completeSnapshot() async throws -> OttoDataSnapshot {
        let subscriptions = try modelContext.fetch(FetchDescriptor<StoredSubscription>())
        let methods = try modelContext.fetch(FetchDescriptor<StoredPaymentMethod>())
        let events = try modelContext.fetch(FetchDescriptor<StoredBillingEvent>())
        let cancellations = try modelContext.fetch(FetchDescriptor<StoredCancellationRecord>())
        let changes = try modelContext.fetch(FetchDescriptor<StoredPriceChange>())
        return OttoDataSnapshot(
            subscriptions: try subscriptions.map { try $0.toDomain() }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            paymentMethods: try methods.map { try $0.toDomain() }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            billingEvents: try events.map { try $0.toDomain() }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            cancellationRecords: try cancellations.map { try $0.toDomain() }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            priceChanges: try changes.map { try $0.toDomain() }
                .sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    /// The atomic apply: every existing record is deleted and the snapshot's
    /// records inserted inside ONE transaction, so a bad import leaves the
    /// database exactly as it was (Wave 8: no half-restore).
    ///
    /// Structured so nothing can throw between the first mutation and the
    /// final `save()`: every refusable condition - dangling references, the
    /// fetches - is checked up front. That is not just tidiness: SwiftData's
    /// `rollback()` can crash on a context holding pending deletes, so the
    /// mutation phase must not have a failure path that needs it. The one
    /// remaining throw is `save()` itself (disk full and the like), where the
    /// on-disk state is still the old one.
    public func restore(_ snapshot: OttoDataSnapshot) async throws {
        // Refuse-first phase: nothing below this line mutates.
        try refuseUnholdable(snapshot)
        let existingSubscriptions = try modelContext.fetch(FetchDescriptor<StoredSubscription>())
        let existingMethods = try modelContext.fetch(FetchDescriptor<StoredPaymentMethod>())

        // Mutation phase: no throws until the single save.
        for record in existingSubscriptions {
            // Children cascade with their parent.
            modelContext.delete(record)
        }
        for record in existingMethods {
            modelContext.delete(record)
        }
        insert(snapshot)
        try modelContext.save()
    }

    /// Every reason a restore could be refused, checked before the wipe.
    private func refuseUnholdable(_ snapshot: OttoDataSnapshot) throws {
        let knownSubscriptionIDs = Set(snapshot.subscriptions.map(\.id))
        for event in snapshot.billingEvents
        where !knownSubscriptionIDs.contains(event.subscriptionID) {
            throw RepositoryError.subscriptionNotFound(event.subscriptionID)
        }
        for cancellation in snapshot.cancellationRecords
        where !knownSubscriptionIDs.contains(cancellation.subscriptionID) {
            throw RepositoryError.subscriptionNotFound(cancellation.subscriptionID)
        }
        for change in snapshot.priceChanges
        where !knownSubscriptionIDs.contains(change.subscriptionID) {
            throw RepositoryError.subscriptionNotFound(change.subscriptionID)
        }
    }

    /// Inserts every record. Non-throwing by design - `refuseUnholdable` runs
    /// first, so the parent lookups cannot miss (the guards are compile-time
    /// necessity, not reachable paths).
    private func insert(_ snapshot: OttoDataSnapshot) {
        var parents: [UUID: StoredSubscription] = [:]
        for subscription in snapshot.subscriptions {
            let record = StoredSubscription()
            modelContext.insert(record)
            record.update(from: subscription)
            parents[subscription.id] = record
        }
        for method in snapshot.paymentMethods {
            let record = StoredPaymentMethod()
            modelContext.insert(record)
            record.update(from: method)
        }
        for event in snapshot.billingEvents {
            guard let parent = parents[event.subscriptionID] else { continue }
            let record = StoredBillingEvent()
            modelContext.insert(record)
            record.subscription = parent
            record.update(from: event)
        }
        for cancellation in snapshot.cancellationRecords {
            guard let parent = parents[cancellation.subscriptionID] else { continue }
            let record = StoredCancellationRecord()
            modelContext.insert(record)
            parent.cancellationRecord = record
            record.update(from: cancellation)
        }
        for change in snapshot.priceChanges {
            guard let parent = parents[change.subscriptionID] else { continue }
            let record = StoredPriceChange()
            modelContext.insert(record)
            record.subscription = parent
            record.update(from: change)
        }
    }
}
