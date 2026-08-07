import Foundation
import OttoDomain
import OttoRepositories
import SwiftData

extension OttoStore: CancellationRepository {
    public func save(_ episode: CancellationEpisode) async throws {
        guard let parent = try storedSubscription(id: episode.subscriptionID, includingDeleted: true) else {
            throw RepositoryError.subscriptionNotFound(episode.subscriptionID)
        }
        // Episodes upsert by their own id (spec §5.3a): a subscription holds
        // many, so there is no slot to reuse - a new id is a new row, and
        // closing or editing an episode rewrites the row that carries its id.
        let stored: StoredCancellationEpisode
        if let existing = try storedEpisode(id: episode.id) {
            stored = existing
        } else {
            stored = StoredCancellationEpisode()
            modelContext.insert(stored)
            stored.subscription = parent
        }
        stored.update(from: episode)
        try modelContext.save()
    }

    public func openEpisode(forSubscription subscriptionID: UUID) async throws -> CancellationEpisode? {
        try fetchEpisodes(subscriptionID: subscriptionID, includingDeleted: false)
            .first { $0.isOpen }
    }

    public func episodes(forSubscription subscriptionID: UUID) async throws -> [CancellationEpisode] {
        try fetchEpisodes(subscriptionID: subscriptionID, includingDeleted: false)
    }

    public func episodesIncludingDeleted(
        forSubscription subscriptionID: UUID
    ) async throws -> [CancellationEpisode] {
        try fetchEpisodes(subscriptionID: subscriptionID, includingDeleted: true)
    }

    private func storedEpisode(id: UUID) throws -> StoredCancellationEpisode? {
        var descriptor = FetchDescriptor<StoredCancellationEpisode>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchEpisodes(
        subscriptionID: UUID, includingDeleted: Bool
    ) throws -> [CancellationEpisode] {
        let records = try modelContext.fetch(
            FetchDescriptor<StoredCancellationEpisode>(
                predicate: includingDeleted
                    ? #Predicate { $0.subscriptionID == subscriptionID }
                    : #Predicate { $0.subscriptionID == subscriptionID && $0.deletedAt == nil }
            )
        )
        // Newest cancellation first: the open episode (if any) leads, and
        // history reads in reverse chronology.
        return mapSkippingFailures(records) { try $0.toDomain() }
            .sorted { ($0.markedCancelledAt, $0.id.uuidString) > ($1.markedCancelledAt, $1.id.uuidString) }
    }
}
