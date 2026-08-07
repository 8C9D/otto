import Foundation
import OttoDomain

/// Layer 3 access to subscriptions (spec §3.4). Implementations accept and return
/// domain values only; no persistence type ever crosses this boundary.
///
/// Every read excludes soft-deleted records unless the method name says otherwise -
/// tombstone filtering is the repository's default, not a thing callers remember
/// (Wave 2 constraint 7).
public protocol SubscriptionRepository: Sendable {
    /// Inserts or updates by `id`, including the embedded trial term. Writes the
    /// domain value verbatim - `deletedAt` included - but never cascades; use
    /// `deleteSubscription(withID:at:)` to delete.
    func save(_ subscription: Subscription) async throws

    /// The live subscription with this id, or nil when none exists or it is deleted.
    func subscription(withID id: UUID) async throws -> Subscription?

    /// All live subscriptions.
    func subscriptions() async throws -> [Subscription]

    /// All subscriptions including tombstones - for sync, export, and audits only.
    func subscriptionsIncludingDeleted() async throws -> [Subscription]

    /// Soft-deletes the subscription at the given instant and cascades the tombstone
    /// to its trial term, billing events, cancellation record, and price changes.
    /// Hard deletes happen nowhere (spec §3.5).
    func deleteSubscription(withID id: UUID, at instant: Date) async throws
}
