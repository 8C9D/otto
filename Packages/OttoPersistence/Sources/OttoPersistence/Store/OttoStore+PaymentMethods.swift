import Foundation
import OttoDomain
import OttoRepositories
import SwiftData

extension OttoStore: PaymentMethodRepository {
    public func save(_ method: PaymentMethod) async throws {
        let record: StoredPaymentMethod
        if let existing = try storedMethod(id: method.id) {
            record = existing
        } else {
            record = StoredPaymentMethod()
            modelContext.insert(record)
        }
        record.update(from: method)
        try modelContext.save()
    }

    public func paymentMethod(withID id: UUID) async throws -> PaymentMethod? {
        guard let record = try storedMethod(id: id), record.deletedAt == nil else { return nil }
        return mapSkippingFailures([record]) { try $0.toDomain() }.first
    }

    public func paymentMethods() async throws -> [PaymentMethod] {
        try fetchMethods(includingDeleted: false)
    }

    public func paymentMethodsIncludingDeleted() async throws -> [PaymentMethod] {
        try fetchMethods(includingDeleted: true)
    }

    public func deletePaymentMethod(withID id: UUID, at instant: Date) async throws {
        guard let record = try storedMethod(id: id) else {
            throw RepositoryError.paymentMethodNotFound(id)
        }
        if record.deletedAt == nil {
            // Never before the record's own creation (docs/sync-safety.md).
            record.deletedAt = monotonicStamp(instant, notBefore: record.createdAt)
        }
        try modelContext.save()
    }

    private func storedMethod(id: UUID) throws -> StoredPaymentMethod? {
        var descriptor = FetchDescriptor<StoredPaymentMethod>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchMethods(includingDeleted: Bool) throws -> [PaymentMethod] {
        var records = try modelContext.fetch(FetchDescriptor<StoredPaymentMethod>())
        if !includingDeleted {
            records = liveOnly(records, deletedAt: \.deletedAt)
        }
        return mapSkippingFailures(records) { try $0.toDomain() }
            .sorted { ($0.label, $0.id.uuidString) < ($1.label, $1.id.uuidString) }
    }
}
