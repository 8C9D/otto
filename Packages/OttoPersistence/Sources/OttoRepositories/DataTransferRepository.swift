import Foundation
import OttoDomain

/// The export/import seam (spec §3.5: export is a first-class feature, and the
/// CloudKit escape hatch after Wave 6). Unlike the per-entity repositories this
/// one moves the WHOLE database, because export must be complete to be a backup
/// and import must be atomic to be trustworthy.
/// What a restore does about this device's materialization watermarks
/// (spec §5.3). The caller knows which import strategy produced the snapshot;
/// the store owns the entire §5.3 sequence for whichever policy is named, so
/// no caller can order the dirty flag, the restore, and the reconstruction
/// wrongly - the v2.2 crash window lived in exactly that caller-owned gap.
public enum RestoreWatermarkPolicy: Hashable, Sendable {
    /// A merge: the ledger only grows, so the stored watermarks still vouch
    /// only for rows that exist. They are left untouched.
    case keep
    /// A replace: the ledger becomes what the file carries, so every
    /// watermark must be reconstructed from it. The store writes the §5.3
    /// dirty flag durably first, and the flag is cleared in the same save
    /// that commits the reconstruction - a crash between the two saves
    /// self-heals on the next watermark access.
    case reconstruct
}

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
    ///
    /// `watermarks` names the §5.3 policy: `.reconstruct` for a replace
    /// (dirty flag, restore, reconstruction - sequenced by the store),
    /// `.keep` for a merge.
    func restore(
        _ snapshot: OttoDataSnapshot, at instant: Date, watermarks: RestoreWatermarkPolicy
    ) async throws

    /// Rebuilds every materialization watermark on this device from the
    /// current ledger (spec §5.3, v2.1). After a replace the database is
    /// exactly what the file describes, and this device's past observation
    /// vouches for rows the file may not carry - but a nil watermark is the
    /// founding hazard with no safe fallback (the next pass would observe from
    /// today and skip the window). The file carries no watermark by design,
    /// and needs none: the latest imported `expectedDate` for a subscription
    /// IS what "materialized through" means, so each live subscription's
    /// watermark becomes that date - or its anchor when it has no ledger rows,
    /// NEVER today. Both branches land safe: re-materializing from the anchor
    /// is wasteful and harmless; observing from today is the hazard.
    ///
    /// `restore(_:at:watermarks: .reconstruct)` runs this itself; it remains
    /// callable for the rare direct rebuild. A merge never needs it.
    func reconstructMaterializationWatermarks() async throws
}
