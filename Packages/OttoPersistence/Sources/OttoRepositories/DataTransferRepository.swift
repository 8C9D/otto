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
}
