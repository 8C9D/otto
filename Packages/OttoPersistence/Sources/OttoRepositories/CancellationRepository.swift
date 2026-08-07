import Foundation
import OttoDomain

/// Layer 3 access to cancellation records (spec §5.4). A subscription has at most
/// one - the watch on whether the money actually stopped.
public protocol CancellationRepository: Sendable {
    /// Inserts or updates the record for `record.subscriptionID`. Throws
    /// `RepositoryError.subscriptionNotFound` when that subscription has no
    /// persisted record.
    func save(_ record: CancellationRecord) async throws

    /// The live record for one subscription, or nil.
    func record(forSubscription subscriptionID: UUID) async throws -> CancellationRecord?

    /// The record for one subscription even when tombstoned, or nil.
    func recordIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> CancellationRecord?
}
