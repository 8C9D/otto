import Foundation
import OttoDomain
import OttoRepositories
import SwiftData

extension OttoStore: PriceChangeRepository {
    public func append(_ change: PriceChange) async throws {
        let record: StoredPriceChange
        if let existing = try storedChange(id: change.id) {
            // History is append-only; matching an id means the same append was
            // delivered twice, and rewriting it keeps the operation idempotent.
            record = existing
        } else {
            guard let parent = try storedSubscription(id: change.subscriptionID, includingDeleted: true) else {
                throw RepositoryError.subscriptionNotFound(change.subscriptionID)
            }
            record = StoredPriceChange()
            modelContext.insert(record)
            record.subscription = parent
        }
        record.update(from: change)
        try modelContext.save()
    }

    public func history(forSubscription subscriptionID: UUID) async throws -> [PriceChange] {
        try fetchHistory(subscriptionID: subscriptionID, includingDeleted: false)
    }

    public func historyIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [PriceChange] {
        try fetchHistory(subscriptionID: subscriptionID, includingDeleted: true)
    }

    private func storedChange(id: UUID) throws -> StoredPriceChange? {
        var descriptor = FetchDescriptor<StoredPriceChange>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchHistory(subscriptionID: UUID, includingDeleted: Bool) throws -> [PriceChange] {
        var records = try modelContext.fetch(
            FetchDescriptor<StoredPriceChange>(predicate: #Predicate { $0.subscriptionID == subscriptionID })
        )
        if !includingDeleted {
            records = liveOnly(records, deletedAt: \.deletedAt)
        }
        return mapSkippingFailures(records) { try $0.toDomain() }
            .sorted { ($0.effectiveDate, $0.recordedAt) < ($1.effectiveDate, $1.recordedAt) }
    }
}
