import Foundation
import SwiftData

extension OttoSchemaV1 {
    /// Persistence record for `PriceChange` (spec §5.5) - append-only history.
    @Model
    final class StoredPriceChange {
        var id: UUID?
        var subscriptionID: UUID?
        /// yyyymmdd
        var effectiveDate: Int?
        var oldAmountCents: Int?
        var newAmountCents: Int?
        var recordedAt: Date?
        var source: String?
        var note: String?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: StoredSubscription?

        init() {}
    }
}
