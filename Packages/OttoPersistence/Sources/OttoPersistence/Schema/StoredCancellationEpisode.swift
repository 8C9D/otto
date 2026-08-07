import Foundation
import SwiftData

extension OttoSchemaV2 {
    /// Persistence record for `CancellationEpisode` (spec §5.4, §5.3a) - one row
    /// per cancellation, reached through the one-to-many relationship, because a
    /// subscription can be cancelled, resubscribed, and cancelled again. The
    /// current episode is the one with no `endedAt`. Carries the same scalar
    /// `subscriptionID` as `StoredBillingEvent`, for the same reasons.
    @Model
    final class StoredCancellationEpisode {
        var id: UUID?
        var subscriptionID: UUID?
        var markedCancelledAt: Date?
        /// The stored status the cancellation interrupted - what an un-cancel
        /// restores (spec §5.3a). Nil on episodes migrated from pre-8.5
        /// records, which never captured it.
        var statusAtStart: String?
        /// yyyymmdd. Required in the domain for every state except
        /// `.awaitingResumeDate` (spec §5.4): a deferred check stores no date
        /// because none honestly exists; the mapping enforces the pairing.
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
        /// When the episode closed; nil while it is current (spec §5.3a). The
        /// mapping enforces the pairing with `outcome`.
        var endedAt: Date?
        var outcome: String?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: StoredSubscription?

        init() {}
    }
}
