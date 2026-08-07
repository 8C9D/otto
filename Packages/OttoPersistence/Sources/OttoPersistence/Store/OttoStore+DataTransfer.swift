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
        let cancellations = try modelContext.fetch(FetchDescriptor<StoredCancellationEpisode>())
        let changes = try modelContext.fetch(FetchDescriptor<StoredPriceChange>())
        return OttoDataSnapshot(
            subscriptions: try subscriptions.map { try $0.toDomain() }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            paymentMethods: try methods.map { try $0.toDomain() }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            billingEvents: try events.map { try $0.toDomain() }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            cancellationEpisodes: try cancellations.map { try $0.toDomain() }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            priceChanges: try changes.map { try $0.toDomain() }
                .sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    /// The atomic apply, sync-aware since Wave 6B-Prep (spec §8): every
    /// snapshot record UPSERTS by id and every stored record the snapshot
    /// does not carry is TOMBSTONED at `instant`, inside ONE transaction - so
    /// a bad import leaves the database exactly as it was (Wave 8: no
    /// half-restore), and under mirroring a restore syncs as ordinary edits
    /// rather than a mass deletion. This method is the ONE holder of
    /// whole-database authority: `save` deliberately cannot remove anything
    /// (§4a), so the explicit diff here - children included - is where a
    /// restore's removals are decided.
    ///
    /// Structured so nothing can throw between the first mutation and the
    /// final `save()`: every refusable condition - dangling references, the
    /// fetches - is checked up front. That is not just tidiness: SwiftData's
    /// `rollback()` can crash on a context holding pending deletes, so the
    /// mutation phase must not have a failure path that needs it. The one
    /// remaining throw is `save()` itself (disk full and the like), where the
    /// on-disk state is still the old one.
    public func restore(_ snapshot: OttoDataSnapshot, at instant: Date) async throws {
        // Refuse-first phase: nothing below this line mutates.
        try refuseUnholdable(snapshot)
        let subscriptions = try existingByID(StoredSubscription.self)
        let methods = try existingByID(StoredPaymentMethod.self)
        let events = try existingByID(StoredBillingEvent.self)
        let cancellations = try existingByID(StoredCancellationEpisode.self)
        let changes = try existingByID(StoredPriceChange.self)

        // Mutation phase: no throws until the single save.
        let parents = restoreSubscriptions(snapshot.subscriptions, existing: subscriptions, at: instant)
        for value in snapshot.paymentMethods {
            let record = methods.records[value.id] ?? inserted(StoredPaymentMethod())
            record.update(from: value)
        }
        for absent in methods.absent(from: snapshot.paymentMethods.map(\.id)) {
            tombstone(&absent.deletedAt, at: instant)
        }
        for value in snapshot.billingEvents {
            let record = events.records[value.id] ?? inserted(StoredBillingEvent())
            record.subscription = record.subscription ?? parents[value.subscriptionID]
            record.update(from: value)
        }
        for absent in events.absent(from: snapshot.billingEvents.map(\.id)) {
            tombstone(&absent.deletedAt, at: instant)
        }
        for value in snapshot.cancellationEpisodes {
            let record = cancellations.records[value.id] ?? inserted(StoredCancellationEpisode())
            record.subscription = record.subscription ?? parents[value.subscriptionID]
            record.update(from: value)
            tombstoneAbsentNotes(of: record, missingFrom: value, at: instant)
        }
        for absent in cancellations.absent(from: snapshot.cancellationEpisodes.map(\.id)) {
            tombstone(&absent.deletedAt, at: instant)
        }
        for value in snapshot.priceChanges {
            let record = changes.records[value.id] ?? inserted(StoredPriceChange())
            record.subscription = record.subscription ?? parents[value.subscriptionID]
            record.update(from: value)
        }
        for absent in changes.absent(from: snapshot.priceChanges.map(\.id)) {
            tombstone(&absent.deletedAt, at: instant)
        }
        try modelContext.save()
    }

    /// The subscription half of the restore diff: upsert by id (children
    /// diffed explicitly), then cascade-tombstone whole aggregates the
    /// snapshot does not carry, mirroring `deleteSubscription`.
    private func restoreSubscriptions(
        _ values: [Subscription],
        existing subscriptions: ExistingRecords<StoredSubscription>,
        at instant: Date
    ) -> [UUID: StoredSubscription] {
        var parents: [UUID: StoredSubscription] = subscriptions.records
        for value in values {
            let record: StoredSubscription
            if let stored = subscriptions.records[value.id] {
                record = stored
            } else {
                record = StoredSubscription()
                modelContext.insert(record)
                parents[value.id] = record
            }
            record.update(from: value)
            tombstoneAbsentChildren(of: record, missingFrom: value, at: instant)
        }
        for absent in subscriptions.absent(from: values.map(\.id)) {
            tombstone(&absent.deletedAt, at: instant)
            if let trial = absent.trial { tombstone(&trial.deletedAt, at: instant) }
            for episode in absent.cancellationEpisodes ?? [] { tombstone(&episode.deletedAt, at: instant) }
            for episode in absent.pauseEpisodes ?? [] { tombstone(&episode.deletedAt, at: instant) }
            for event in absent.billingEvents ?? [] { tombstone(&event.deletedAt, at: instant) }
            for change in absent.priceChanges ?? [] { tombstone(&change.deletedAt, at: instant) }
        }
        return parents
    }

    /// The replace-import watermark reset (spec §5.3, Wave 6B-Prep). Ordered by
    /// the caller AFTER a successful restore, so a refused or failed restore
    /// leaves device state exactly as it was; the crash window between the two
    /// saves is accepted and documented in docs/cloudkit-readiness.md.
    public func resetMaterializationWatermarks() async throws {
        let rows = try deviceStateContext.fetch(FetchDescriptor<StoredMaterializationWatermark>())
        for row in rows { deviceStateContext.delete(row) }
        if deviceStateContext.hasChanges {
            try deviceStateContext.save()
        }
    }

    /// Every reason a restore could be refused, checked before any mutation.
    private func refuseUnholdable(_ snapshot: OttoDataSnapshot) throws {
        let knownSubscriptionIDs = Set(snapshot.subscriptions.map(\.id))
        for event in snapshot.billingEvents
        where !knownSubscriptionIDs.contains(event.subscriptionID) {
            throw RepositoryError.subscriptionNotFound(event.subscriptionID)
        }
        for cancellation in snapshot.cancellationEpisodes
        where !knownSubscriptionIDs.contains(cancellation.subscriptionID) {
            throw RepositoryError.subscriptionNotFound(cancellation.subscriptionID)
        }
        for change in snapshot.priceChanges
        where !knownSubscriptionIDs.contains(change.subscriptionID) {
            throw RepositoryError.subscriptionNotFound(change.subscriptionID)
        }
    }

    /// The restore-side child diff `update(from:)` deliberately does not do
    /// (§4a: a SAVE cannot remove anything): a stored child the snapshot's
    /// aggregate does not carry is tombstoned, because a restore IS the
    /// explicit whole-database statement.
    private func tombstoneAbsentChildren(
        of record: StoredSubscription, missingFrom value: Subscription, at instant: Date
    ) {
        if value.trial == nil, let trial = record.trial {
            tombstone(&trial.deletedAt, at: instant)
        }
        let carried = Set(value.pauseEpisodes.map(\.id))
        for episode in record.pauseEpisodes ?? []
        where episode.id.map({ !carried.contains($0) }) ?? true {
            tombstone(&episode.deletedAt, at: instant)
        }
    }

    private func tombstoneAbsentNotes(
        of record: StoredCancellationEpisode, missingFrom value: CancellationEpisode, at instant: Date
    ) {
        let carried = Set(value.evidenceNotes.map(\.id))
        for note in record.evidenceNotes ?? []
        where note.id.map({ !carried.contains($0) }) ?? true {
            tombstone(&note.deletedAt, at: instant)
        }
    }

    private func tombstone(_ deletedAt: inout Date?, at instant: Date) {
        if deletedAt == nil { deletedAt = instant }
    }

    private func inserted<Record: PersistentModel>(_ record: Record) -> Record {
        modelContext.insert(record)
        return record
    }

    /// One fetch per table, indexed for the diff: records by id, plus the
    /// helper listing those a snapshot does not carry.
    private struct ExistingRecords<Record> {
        let records: [UUID: Record]

        func absent(from carriedIDs: [UUID]) -> [Record] {
            let carried = Set(carriedIDs)
            return records.filter { !carried.contains($0.key) }.map(\.value)
        }
    }

    private func existingByID<Record: PersistentModel & Identified>(
        _ type: Record.Type
    ) throws -> ExistingRecords<Record> {
        let all = try modelContext.fetch(FetchDescriptor<Record>())
        return ExistingRecords(records: Dictionary(
            all.compactMap { record in record.recordID.map { ($0, record) } },
            uniquingKeysWith: { first, _ in first }
        ))
    }
}

/// The one field the restore diff needs from every record type - named apart
/// from `id` so it cannot collide with `PersistentModel`'s identifier.
private protocol Identified {
    var recordID: UUID? { get }
}

extension OttoSchemaV3.StoredSubscription: Identified { var recordID: UUID? { id } }
extension OttoSchemaV3.StoredPaymentMethod: Identified { var recordID: UUID? { id } }
extension OttoSchemaV3.StoredBillingEvent: Identified { var recordID: UUID? { id } }
extension OttoSchemaV3.StoredCancellationEpisode: Identified { var recordID: UUID? { id } }
extension OttoSchemaV3.StoredPriceChange: Identified { var recordID: UUID? { id } }
