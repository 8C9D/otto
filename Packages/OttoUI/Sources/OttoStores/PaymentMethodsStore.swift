import Foundation
import Observation
import OttoDomain
import OttoRepositories

/// The observable list of payment methods. Wave 3 only reads it - the Add/Edit
/// picker - and the management screen arrives with Wave 7.
@MainActor
@Observable
public final class PaymentMethodsStore {
    public private(set) var state: LoadState<[PaymentMethod]> = .loading

    private let repository: any PaymentMethodRepository

    public init(repository: any PaymentMethodRepository) {
        self.repository = repository
    }

    public func refresh() async {
        do {
            state = .loaded(try await repository.paymentMethods())
        } catch {
            state = .failed(error)
        }
    }
}
