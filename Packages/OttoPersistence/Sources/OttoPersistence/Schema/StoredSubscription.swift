import Foundation
import SwiftData

extension OttoSchemaV1 {
    /// Persistence record for `Subscription` (spec §5.1). Fields the domain requires
    /// are stored optional and their absence is a mapping error; only fields with a
    /// true domain default carry a storage default, so a partially synced record can
    /// never silently invent data.
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
        /// yyyymmdd
        var pauseEndsOn: Int?
        /// yyyymmdd - when the pause began (Wave 7): the freeze point for §5.1's
        /// paused-spend price. Optional like every stored field; nil on rows
        /// paused before the field existed, and Insights falls back to the
        /// current price for those.
        var pausedOn: Int?
        /// yyyymmdd - the §5.3 materialization watermark (added v1.5). Optional
        /// like every stored field, which doubles as the migration: pre-v1.5 rows
        /// read nil, materialize from today once, and carry a watermark after
        /// their first pass. An additive optional is lightweight-migratable, which
        /// is why this lands before Wave 6 turns on CloudKit.
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

        @Relationship(deleteRule: .cascade, inverse: \StoredCancellationRecord.subscription)
        var cancellationRecord: StoredCancellationRecord?

        @Relationship(deleteRule: .cascade, inverse: \StoredPriceChange.subscription)
        var priceChanges: [StoredPriceChange]?

        init() {}
    }
}
