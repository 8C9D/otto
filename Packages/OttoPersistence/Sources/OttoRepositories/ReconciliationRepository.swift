import Foundation
import OttoDomain

/// What one reconciliation pass did - counted, so nothing about the outcome
/// is silent, and so tests can assert convergence exactly.
public struct ReconciliationSummary: Hashable, Sendable {
    /// Duplicate `(subscriptionID, expectedDate)` ledger groups merged: the
    /// earliest-created row survived with acknowledgement and confirmation
    /// state folded in, the twins were tombstoned.
    public var mergedLedgerGroups = 0
    /// Rival open cancellation groups merged (spec §4a principle 2a): the
    /// earliest episode survived with the losers' notes and progress folded
    /// in, the losers were tombstoned.
    public var mergedCancellationGroups = 0
    /// Subscriptions whose §4a read repairs were written back to the store.
    public var persistedReadRepairs = 0

    public init(mergedLedgerGroups: Int = 0, mergedCancellationGroups: Int = 0, persistedReadRepairs: Int = 0) {
        self.mergedLedgerGroups = mergedLedgerGroups
        self.mergedCancellationGroups = mergedCancellationGroups
        self.persistedReadRepairs = persistedReadRepairs
    }
}

/// The post-sync convergence pass (spec §5.3 v2.0, §4a). Wave 6B runs this
/// after sync settles; until then it exists, is tested, and is safe to run at
/// any time - on a store no sync has touched it does nothing.
///
/// Every decision inside is a pure domain rule over record data (never a
/// clock), so two devices running the pass independently reach the same live
/// rows and the same merged state; `instant` stamps only tombstones and
/// updated audit fields.
public protocol ReconciliationRepository: Sendable {
    func reconcile(at instant: Date) async throws -> ReconciliationSummary
}
