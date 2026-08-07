import Foundation
import SwiftData

extension OttoSchemaV2 {
    /// Persistence record for `Subscription` (spec §5.1). Fields the domain requires
    /// are stored optional and their absence is a mapping error; only fields with a
    /// true domain default carry a storage default, so a partially synced record can
    /// never silently invent data.
    ///
    /// V2 (spec §5.3a): the `pausedOn`/`pauseEndsOn` pair became the one-to-many
    /// `pauseEpisodes`, and the one-to-one `cancellationRecord` slot became the
    /// one-to-many `cancellationEpisodes`.
    @Model
    final class StoredSubscription {
        var id: UUID?
        var name: String?
        var vendorURL: String?
        var category: String?
        var status: String?
        var amountCents: Int?
        var currencyCode: String?
        var cycleUnit: String?
        var cycleInterval: Int?
        /// yyyymmdd - the single anchor of record, immutable in the domain.
        var cycleStartDay: Int?
        var reminderLeadDays: Int?
        var sameDayReminder: Bool = false
        /// yyyymmdd - the §5.3 materialization watermark (added v1.5). Optional
        /// like every stored field, which doubles as the migration: pre-v1.5 rows
        /// read nil, materialize from today once, and carry a watermark after
        /// their first pass. Device-local; Wave 6's first schema act is moving it
        /// into the local-only configuration before CloudKit sees the schema.
        var lastMaterializedThrough: Int?
        var paymentMethodID: UUID?
        var cancellationURL: String?
        var cancellationNotes: String?
        /// yyyymmdd
        var lastUsedDate: Int?
        var notes: String?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \StoredTrialTerm.subscription)
        var trial: StoredTrialTerm?

        @Relationship(deleteRule: .cascade, inverse: \StoredBillingEvent.subscription)
        var billingEvents: [StoredBillingEvent]?

        @Relationship(deleteRule: .cascade, inverse: \StoredCancellationEpisode.subscription)
        var cancellationEpisodes: [StoredCancellationEpisode]?

        @Relationship(deleteRule: .cascade, inverse: \StoredPauseEpisode.subscription)
        var pauseEpisodes: [StoredPauseEpisode]?

        @Relationship(deleteRule: .cascade, inverse: \StoredPriceChange.subscription)
        var priceChanges: [StoredPriceChange]?

        init() {}
    }
}
