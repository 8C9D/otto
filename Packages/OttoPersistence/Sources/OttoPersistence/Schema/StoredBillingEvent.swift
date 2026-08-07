import Foundation
import SwiftData

extension OttoSchemaV1 {
    /// Persistence record for `BillingEvent` (spec §5.3), one row per expected
    /// charge. `subscriptionID` is stored as a scalar beside the relationship: the
    /// relationship is the structural link that cascades, the scalar is the domain
    /// identity that survives a partially synced parent and keeps predicates plain.
    /// The store writes both together, and mapping reads the scalar.
    @Model
    final class StoredBillingEvent {
        var id: UUID?
        var subscriptionID: UUID?
        /// yyyymmdd
        var expectedDate: Int?
        var expectedAmountCents: Int?
        var state: String?
        var userConfirmedAt: Date?
        var actualAmountCents: Int?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: StoredSubscription?

        init() {}
    }
}
