import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import os

/// One error log per skipped record; see MappingError for the skip policy.
let mappingLogger = Logger(subsystem: "com.arthurzhang.otto", category: "persistence")

/// The SwiftData implementation of every repository protocol - one actor over one
/// model context, so a write and its cascade always happen on the same serialized
/// context. Callers hold it as the protocols; the concrete type exists only to be
/// constructed and injected.
///
/// Reads never surface a `MappingError`: an unmappable record (a partially synced
/// arrival, once CloudKit is on) is skipped with an error log, because in domain
/// terms it is not there yet. Reads exclude tombstones unless the method name says
/// otherwise. No method reads a clock - every instant is a parameter or a field of
/// the value being saved.
@ModelActor
public actor OttoStore {

    // MARK: - Shared helpers

    func liveOnly<Record>(_ records: [Record], deletedAt: (Record) -> Date?) -> [Record] {
        records.filter { deletedAt($0) == nil }
    }

    /// Maps records to domain values, skipping (with a log) any that fail.
    func mapSkippingFailures<Record, Value>(
        _ records: [Record],
        _ transform: (Record) throws -> Value
    ) -> [Value] {
        records.compactMap { record in
            do {
                return try transform(record)
            } catch {
                mappingLogger.error("Skipping unmappable record: \(String(describing: error))")
                return nil
            }
        }
    }

    func storedSubscription(id: UUID, includingDeleted: Bool) throws -> StoredSubscription? {
        var descriptor = FetchDescriptor<StoredSubscription>(
            predicate: includingDeleted
                ? #Predicate { $0.id == id }
                : #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
