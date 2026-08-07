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

    /// Atomically replaces the store's contents with `snapshot` - all of it or
    /// none of it. Callers resolve merges first (`resolveImport`); by the time
    /// this runs the snapshot IS the desired database.
    func restore(_ snapshot: OttoDataSnapshot) async throws

    /// Clears every materialization watermark on this device - the
    /// replace-import reset (spec §5.3, Wave 6B-Prep): after the database
    /// becomes exactly what the file describes, this device's past observation
    /// vouches for ledger rows the file may not carry, so every subscription
    /// re-observes from its next pass. A merge never calls this.
    func resetMaterializationWatermarks() async throws
}
