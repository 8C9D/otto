import Foundation
import OttoDomain

/// The export/import seam (spec §3.5: export is a first-class feature, and the
/// CloudKit escape hatch after Wave 6). Unlike the per-entity repositories this
/// one moves the WHOLE database, because export must be complete to be a backup
/// and import must be atomic to be trustworthy.
public protocol DataTransferRepository: Sendable {
    /// Everything the store holds, tombstones included. Throws on the first
    /// unreadable record instead of skipping it: a silently incomplete backup
    /// is worse than a failed one.
    func completeSnapshot() async throws -> OttoDataSnapshot

    /// Atomically makes the store's LIVE contents exactly `snapshot` - all of
    /// it or none of it. Callers resolve merges first (`resolveImport`); by
    /// the time this runs the snapshot IS the desired database.
    ///
    /// Sync-aware by construction (spec §8, Wave 6B-Prep): every record is
    /// UPSERTED by id and every stored record the snapshot does not carry is
    /// TOMBSTONED at `instant` - never hard-deleted. Under mirroring the old
    /// wipe-and-reinsert restore was a mass cloud deletion plus a resurrection
    /// vector for offline devices; expressed as updates and tombstones, a
    /// restore syncs as ordinary edits. The explicit whole-database diff here
    /// is exactly the authority `save` deliberately no longer has (§4a).
    func restore(_ snapshot: OttoDataSnapshot, at instant: Date) async throws

    /// Rebuilds every materialization watermark on this device from the ledger
    /// a replace-import just restored (spec §5.3, v2.1). After the database
    /// becomes exactly what the file describes, this device's past observation
    /// vouches for rows the file may not carry - but a nil watermark is the
    /// founding hazard with no safe fallback (the next pass would observe from
    /// today and skip the window). The file carries no watermark by design,
    /// and needs none: the latest imported `expectedDate` for a subscription
    /// IS what "materialized through" means, so each live subscription's
    /// watermark becomes that date - or its anchor when it has no ledger rows,
    /// NEVER today. Both branches land safe: re-materializing from the anchor
    /// is wasteful and harmless; observing from today is the hazard. A merge
    /// never calls this.
    func reconstructMaterializationWatermarks() async throws
}
