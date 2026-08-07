import Foundation
import SwiftData

extension OttoSchemaV1 {
    /// Persistence record for `CancellationRecord` (spec §5.4) - at most one per
    /// subscription, reached through the one-to-one relationship. Carries the same
    /// scalar `subscriptionID` as `StoredBillingEvent`, for the same reasons.
    @Model
    final class StoredCancellationRecord {
        var id: UUID?
        var subscriptionID: UUID?
        var markedCancelledAt: Date?
        /// yyyymmdd - required in the domain (spec §5.4, v1.1).
        var nextChargeDateIfNotCancelled: Int?
        /// The watched charge's amount, stored at cancellation (spec §5.4, added
        /// v1.5). Nil on pre-v1.5 rows; the domain treats nil as "not captured"
        /// and the roll-forward backfills it, so no migration stage is needed.
        var expectedChargeAmountCents: Int?
        var verificationState: String?
        /// Consecutive unanswered checks (spec §5.4, added v1.3). Optional like every
        /// stored field; mapping reads nil as 0, so pre-v1.3 rows need no migration.
        var unansweredCheckCount: Int?
        var verifiedAt: Date?
        var evidenceNote: String?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: StoredSubscription?

        init() {}
    }
}
