import Foundation
import SwiftData

extension OttoSchemaV1 {
    /// Persistence record for `CancellationRecord` (spec §5.4) - at most one per
    /// subscription, reached through the one-to-one relationship. Carries the same
    /// scalar `subscriptionID` as `StoredBillingEvent`, for the same reasons.
    @Model
    final class StoredCancellationRecord {
        var subscriptionID: UUID?
        var markedCancelledAt: Date?
        /// yyyymmdd - required in the domain (spec §5.4, v1.1).
        var nextChargeDateIfNotCancelled: Int?
        var verificationState: String?
        var verifiedAt: Date?
        var evidenceNote: String?
        var deletedAt: Date?

        var subscription: StoredSubscription?

        init() {}
    }
}
