import Foundation
import OttoDomain

/// Layer 3 access to cancellation episodes (spec §5.4, §5.3a). A subscription
/// can carry many - one per cancellation in its life - and at most one is open
/// (no `endedAt`): the watch on whether the money actually stopped.
public protocol CancellationRepository: Sendable {
    /// Inserts or updates the episode carrying `episode.id`. Throws
    /// `RepositoryError.subscriptionNotFound` when `episode.subscriptionID`
    /// names no persisted subscription.
    func save(_ episode: CancellationEpisode) async throws

    /// The live open episode for one subscription - the current cancellation,
    /// §5.3a's "episode with no end date" - or nil when nothing is watching.
    func openEpisode(forSubscription subscriptionID: UUID) async throws -> CancellationEpisode?

    /// Every live episode for one subscription, newest first.
    func episodes(forSubscription subscriptionID: UUID) async throws -> [CancellationEpisode]

    /// Every episode for one subscription even when tombstoned, newest first.
    func episodesIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [CancellationEpisode]
}
