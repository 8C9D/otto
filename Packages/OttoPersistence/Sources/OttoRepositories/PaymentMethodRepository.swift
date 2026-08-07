import Foundation
import OttoDomain

/// Layer 3 access to payment methods (spec §5.5).
public protocol PaymentMethodRepository: Sendable {
    /// Inserts or updates by `id`.
    func save(_ method: PaymentMethod) async throws

    /// The live payment method with this id, or nil.
    func paymentMethod(withID id: UUID) async throws -> PaymentMethod?

    /// All live payment methods.
    func paymentMethods() async throws -> [PaymentMethod]

    /// All payment methods including tombstones.
    func paymentMethodsIncludingDeleted() async throws -> [PaymentMethod]

    /// Soft-deletes at the given instant. Throws
    /// `RepositoryError.paymentMethodNotFound` when no record exists.
    func deletePaymentMethod(withID id: UUID, at instant: Date) async throws
}
