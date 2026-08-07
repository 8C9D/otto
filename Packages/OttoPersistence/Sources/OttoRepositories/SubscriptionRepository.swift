import Foundation
import OttoDomain

/// Layer 3 access to subscriptions (spec §3.4). Implementations accept and return
/// domain values only; no persistence type ever crosses this boundary.
///
/// Every read excludes soft-deleted records unless the method name says otherwise -
/// tombstone filtering is the repository's default, not a thing callers remember
/// (Wave 2 constraint 7).
public protocol SubscriptionRepository: Sendable {
    /// Inserts or updates by `id`, applying embedded children (trial term,
    /// pause episodes) to identified records. Writes each carried value
    /// verbatim - `deletedAt` included - but **absence is not deletion**
    /// (spec §4a): a stored child the value does not carry is left untouched,
    /// so a stale snapshot cannot remove a record it never saw. Deleting a
    /// child is saving it WITH its tombstone; deleting the subscription is
    /// `deleteSubscription(withID:at:)`.
    func save(_ subscription: Subscription) async throws

    /// The live subscription with this id, or nil when none exists or it is deleted.
    func subscription(withID id: UUID) async throws -> Subscription?

    /// All live subscriptions.
    func subscriptions() async throws -> [Subscription]

    /// All subscriptions including tombstones - for sync, export, and audits only.
    func subscriptionsIncludingDeleted() async throws -> [Subscription]

    /// How many live subscription records could not be read as domain values
    /// (spec §5.2b, v1.4). The read policy skips unmappable records, which is loud
    /// in the console and invisible in the UI - so this count feeds Today's
    /// aggregate needs-review card, and it must never stay at zero while records
    /// are missing from `subscriptions()`.
    func unreadableSubscriptionCount() async throws -> Int

    /// Soft-deletes the subscription at the given instant and cascades the tombstone
    /// to its trial term, billing events, cancellation record, and price changes.
    /// Hard deletes happen nowhere (spec §3.5).
    func deleteSubscription(withID id: UUID, at instant: Date) async throws
}
