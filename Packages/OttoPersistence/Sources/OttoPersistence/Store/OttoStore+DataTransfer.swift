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
    ///
    /// With `.reconstruct` the store owns the whole §5.3 sequence: dirty flag
    /// durably first, main-store save, then watermark reconstruction whose
    /// save also clears the flag. A crash between the two saves leaves the
    /// flag set, and every watermark access reconstructs before reading while
    /// it is - the v2.2 stale-ahead window self-heals instead of persisting.
    public func restore(
        _ snapshot: OttoDataSnapshot, at instant: Date, watermarks: RestoreWatermarkPolicy
    ) async throws {
        try restoreThroughMainSave(snapshot, at: instant, markingDirty: watermarks == .reconstruct)
        if watermarks == .reconstruct {
            try reconstructWatermarksNow()
        }
    }

    /// Everything up to and including the main-store save - the first of the
    /// two saves. Internal seam so the crash-window test can interrupt between
    /// the saves through the real production path rather than a simulation.
    func restoreThroughMainSave(
        _ snapshot: OttoDataSnapshot, at instant: Date, markingDirty: Bool
    ) throws {
        // Refuse-first phase: nothing below this line mutates.
        try refuseUnlessSyncDisengaged()
        try refuseUnholdable(snapshot)
        let subscriptions = try existingByID(StoredSubscription.self)
        let methods = try existingByID(StoredPaymentMethod.self)
        let events = try existingByID(StoredBillingEvent.self)
        let cancellations = try existingByID(StoredCancellationEpisode.self)
        let changes = try existingByID(StoredPriceChange.self)

        // The §5.3 dirty flag, durable BEFORE the main store can change: a
        // crash anywhere past this line reconstructs on the next watermark
        // access. Last in the refuse phase, so a refused restore writes none.
        if markingDirty {
            try markRestoreDirty(at: instant)
        }

        // Mutation phase: no throws until the single save.
        let parents = restoreSubscriptions(snapshot.subscriptions, existing: subscriptions, at: instant)
        for value in snapshot.paymentMethods {
            let record = methods.records[value.id] ?? inserted(StoredPaymentMethod())
            record.update(from: value)
        }
        for absent in methods.absent(from: snapshot.paymentMethods.map(\.id)) {
            tombstone(&absent.deletedAt, notBefore: absent.createdAt, at: instant)
        }
        for value in snapshot.billingEvents {
            let record = events.records[value.id] ?? inserted(StoredBillingEvent())
            record.subscription = record.subscription ?? parents[value.subscriptionID]
            record.update(from: value)
        }
        for absent in events.absent(from: snapshot.billingEvents.map(\.id)) {
            tombstone(&absent.deletedAt, notBefore: absent.createdAt, at: instant)
        }
        for value in snapshot.cancellationEpisodes {
            let record = cancellations.records[value.id] ?? inserted(StoredCancellationEpisode())
            record.subscription = record.subscription ?? parents[value.subscriptionID]
            record.update(from: value)
            tombstoneAbsentNotes(of: record, missingFrom: value, at: instant)
        }
        for absent in cancellations.absent(from: snapshot.cancellationEpisodes.map(\.id)) {
            tombstone(&absent.deletedAt, notBefore: absent.createdAt, at: instant)
        }
        for value in snapshot.priceChanges {
            let record = changes.records[value.id] ?? inserted(StoredPriceChange())
            record.subscription = record.subscription ?? parents[value.subscriptionID]
            record.update(from: value)
        }
        for absent in changes.absent(from: snapshot.priceChanges.map(\.id)) {
            tombstone(&absent.deletedAt, notBefore: absent.createdAt, at: instant)
        }
        try commitRestore(markingDirty: markingDirty)
    }

    /// The first of the two saves. A failed save persists nothing, so the
    /// stored watermarks still match the on-disk ledger and the flag is
    /// retracted. Best-effort: the retraction's own save can fail right after
    /// succeeding moments ago - the §5.3 double fault - which leaves the next
    /// access reconstructing over a ledger that was never replaced. That path
    /// is why reconstruction takes the MINIMUM of current and reconstructed
    /// (v2.5): even then, a deliberately rewound watermark cannot be advanced
    /// past its stranded gap.
    private func commitRestore(markingDirty: Bool) throws {
        do {
            try modelContext.save()
        } catch {
            if markingDirty { try? clearRestoreDirtyFlag() }
            throw error
        }
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
            tombstone(&absent.deletedAt, notBefore: absent.createdAt, at: instant)
            if let trial = absent.trial { tombstone(&trial.deletedAt, notBefore: trial.createdAt, at: instant) }
            for episode in absent.cancellationEpisodes ?? [] {
                tombstone(&episode.deletedAt, notBefore: episode.createdAt, at: instant)
            }
            for episode in absent.pauseEpisodes ?? [] {
                tombstone(&episode.deletedAt, notBefore: episode.createdAt, at: instant)
            }
            for event in absent.billingEvents ?? [] {
                tombstone(&event.deletedAt, notBefore: event.createdAt, at: instant)
            }
            for change in absent.priceChanges ?? [] {
                tombstone(&change.deletedAt, notBefore: change.createdAt, at: instant)
            }
        }
        return parents
    }

    /// Spec §8 (v2.1): `restore()` STRUCTURALLY requires the kill switch.
    /// "Engage the kill switch before restoring during an incident" was a
    /// documented rule, and this project's history is documentation failing
    /// where structure holds - a rule that must be remembered DURING an
    /// incident will not be. Restoring into a live mirror would let syncing
    /// edits land on rows mid-restore, so a restore runs only while sync
    /// cannot - which takes BOTH checks: the flags must be disengaged (never
    /// enabled, or braked), AND the container this session actually opened
    /// must be sync-off, because the kill switch acts at the next launch and
    /// an incident is exactly when it was engaged mid-session, minutes ago.
    /// The mode check cannot fire until 6B gives the mode a second case; it
    /// is wired now, like the factory's own rails, so it is load-bearing
    /// before the day it first matters. The error's message tells the user
    /// exactly what to do - engage the switch, relaunch, restore again.
    private func refuseUnlessSyncDisengaged() throws {
        let sync = syncState()
        let flagsDisengaged = !sync.isEnabled || sync.killSwitchEngaged
        if !flagsDisengaged || mainSyncMode != .off {
            throw RepositoryError.restoreRequiresSyncDisengaged
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
            tombstone(&trial.deletedAt, notBefore: trial.createdAt, at: instant)
        }
        let carried = Set(value.pauseEpisodes.map(\.id))
        for episode in record.pauseEpisodes ?? []
        where episode.id.map({ !carried.contains($0) }) ?? true {
            tombstone(&episode.deletedAt, notBefore: episode.createdAt, at: instant)
        }
    }

    private func tombstoneAbsentNotes(
        of record: StoredCancellationEpisode, missingFrom value: CancellationEpisode, at instant: Date
    ) {
        let carried = Set(value.evidenceNotes.map(\.id))
        for note in record.evidenceNotes ?? []
        where note.id.map({ !carried.contains($0) }) ?? true {
            tombstone(&note.deletedAt, notBefore: note.createdAt, at: instant)
        }
    }

    /// A tombstone never predates the record it closes (docs/sync-safety.md):
    /// a device clock set back behind the row's own creation would otherwise
    /// write `deletedAt < createdAt`, the shape found in real exported data.
    private func tombstone(_ deletedAt: inout Date?, notBefore createdAt: Date?, at instant: Date) {
        if deletedAt == nil { deletedAt = monotonicStamp(instant, notBefore: createdAt) }
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
