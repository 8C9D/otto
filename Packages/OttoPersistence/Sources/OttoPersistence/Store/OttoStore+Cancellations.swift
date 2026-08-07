import Foundation
import OttoDomain
import OttoRepositories
import SwiftData

extension OttoStore: CancellationRepository {
    public func save(_ record: CancellationRecord) async throws {
        guard let parent = try storedSubscription(id: record.subscriptionID, includingDeleted: true) else {
            throw RepositoryError.subscriptionNotFound(record.subscriptionID)
        }
        // The one-to-one slot holds at most one record, so a save reuses whatever is
        // there - clearing any tombstone, because an explicit save means the record
        // is live again (cancel → verify → later cancel again).
        let stored: StoredCancellationRecord
        if let existing = parent.cancellationRecord {
            stored = existing
        } else {
            stored = StoredCancellationRecord()
            modelContext.insert(stored)
            parent.cancellationRecord = stored
        }
        stored.update(from: record)
        stored.deletedAt = nil
        try modelContext.save()
    }

    public func record(forSubscription subscriptionID: UUID) async throws -> CancellationRecord? {
        try fetchRecord(subscriptionID: subscriptionID, includingDeleted: false)
    }

    public func recordIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> CancellationRecord? {
        try fetchRecord(subscriptionID: subscriptionID, includingDeleted: true)
    }

    private func fetchRecord(subscriptionID: UUID, includingDeleted: Bool) throws -> CancellationRecord? {
        var descriptor = FetchDescriptor<StoredCancellationRecord>(
            predicate: includingDeleted
                ? #Predicate { $0.subscriptionID == subscriptionID }
                : #Predicate { $0.subscriptionID == subscriptionID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        return mapSkippingFailures([record]) { try $0.toDomain() }.first
    }
}
