import Foundation

/// Failures a repository can report beyond what the storage framework throws.
public enum RepositoryError: Error, Equatable, Sendable {
    /// A child record (billing event, cancellation record, price change) was saved
    /// for a subscription that has no persisted record.
    case subscriptionNotFound(UUID)
    case paymentMethodNotFound(UUID)
}
