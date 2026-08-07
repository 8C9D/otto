import Foundation
import OttoDomain

/// Layer 3 access to price history (spec §5.5). Editing a price never overwrites
/// history - it appends.
public protocol PriceChangeRepository: Sendable {
    /// Appends one price change (idempotently by `id`, so a redelivered save cannot
    /// duplicate history). Throws `RepositoryError.subscriptionNotFound` when the
    /// change's subscription has no persisted record.
    func append(_ change: PriceChange) async throws

    /// Live history for one subscription, ordered by effective date.
    func history(forSubscription subscriptionID: UUID) async throws -> [PriceChange]

    /// Full history for one subscription including tombstones.
    func historyIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [PriceChange]
}
