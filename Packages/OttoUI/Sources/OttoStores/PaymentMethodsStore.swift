import Foundation
import Observation
import OttoDomain
import OttoRepositories

/// The observable list of payment methods, and since Wave 7 the writes behind
/// the management screen (spec §5.5) and the inline creation on Add/Edit.
@MainActor
@Observable
public final class PaymentMethodsStore {
    public private(set) var state: LoadState<[PaymentMethod]> = .loading

    private let repository: any PaymentMethodRepository
    private let dates: DateProvider

    public init(repository: any PaymentMethodRepository, dates: DateProvider = .live) {
        self.repository = repository
        self.dates = dates
    }

    public func refresh() async {
        do {
            state = .loaded(try await repository.paymentMethods())
        } catch {
            state = .failed(error)
        }
    }

    /// Inserts or updates, keeping "default" singular: marking one card the
    /// default unmarks every other - two defaults is a state the picker could
    /// not explain. Errors throw to the caller; the published list is untouched
    /// by a failed write.
    public func save(_ method: PaymentMethod) async throws {
        if method.isDefault {
            let others = try await repository.paymentMethods()
            for var other in others where other.id != method.id && other.isDefault {
                other.isDefault = false
                other.updatedAt = method.updatedAt
                try await repository.save(other)
            }
        }
        try await repository.save(method)
        await refresh()
    }

    /// Soft-deletes at the current instant. Subscriptions keep their
    /// `paymentMethodID`; a dangling reference renders as "None recorded"
    /// rather than blocking the delete or silently clearing the field.
    public func delete(paymentMethodID: UUID) async throws {
        try await repository.deletePaymentMethod(withID: paymentMethodID, at: dates.now())
        await refresh()
    }
}
