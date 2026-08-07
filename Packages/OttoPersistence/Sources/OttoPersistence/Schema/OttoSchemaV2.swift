import Foundation
import SwiftData

// The FROZEN second schema version - Wave 8.5's model lock (spec §5.3a), the
// shape that replaced V1's one-to-one cancellation slot and pause-field pair
// with episode tables. Kept byte-for-byte because it is the source side of the
// V2→V3 migration and must match existing stores exactly. Never edit these
// models; schema changes happen in a new version.
//
// Wave 6A (spec §5.3) moved `lastMaterializedThrough` off `StoredSubscription`:
// the watermark is device bookkeeping, and it must be out of the synced schema
// before CloudKit ever sees it. V3 drops the field; the migration carries the
// values into the device-state store.
enum OttoSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            StoredSubscription.self,
            StoredTrialTerm.self,
            StoredBillingEvent.self,
            StoredCancellationEpisode.self,
            StoredPauseEpisode.self,
            StoredPriceChange.self,
            StoredPaymentMethod.self
        ]
    }
}

extension OttoSchemaV2 {
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
        /// yyyymmdd
        var cycleStartDay: Int?
        var reminderLeadDays: Int?
        var sameDayReminder: Bool = false
        /// yyyymmdd - V2's device-local watermark, migrated into the
        /// device-state store by the V2→V3 stage.
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

        @Relationship(deleteRule: .cascade, inverse: \OttoSchemaV2.StoredTrialTerm.subscription)
        var trial: OttoSchemaV2.StoredTrialTerm?

        @Relationship(deleteRule: .cascade, inverse: \OttoSchemaV2.StoredBillingEvent.subscription)
        var billingEvents: [OttoSchemaV2.StoredBillingEvent]?

        @Relationship(deleteRule: .cascade, inverse: \OttoSchemaV2.StoredCancellationEpisode.subscription)
        var cancellationEpisodes: [OttoSchemaV2.StoredCancellationEpisode]?

        @Relationship(deleteRule: .cascade, inverse: \OttoSchemaV2.StoredPauseEpisode.subscription)
        var pauseEpisodes: [OttoSchemaV2.StoredPauseEpisode]?

        @Relationship(deleteRule: .cascade, inverse: \OttoSchemaV2.StoredPriceChange.subscription)
        var priceChanges: [OttoSchemaV2.StoredPriceChange]?

        init() {}
    }

    @Model
    final class StoredTrialTerm {
        var id: UUID?
        /// yyyymmdd
        var startDate: Int?
        var lengthDays: Int?
        var bufferDays: Int?
        var convertsToAmountCents: Int?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: OttoSchemaV2.StoredSubscription?

        init() {}
    }

    @Model
    final class StoredBillingEvent {
        var id: UUID?
        var subscriptionID: UUID?
        /// yyyymmdd
        var expectedDate: Int?
        var expectedAmountCents: Int?
        var state: String?
        var userConfirmedAt: Date?
        var acknowledgedAt: Date?
        var actualAmountCents: Int?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: OttoSchemaV2.StoredSubscription?

        init() {}
    }

    @Model
    final class StoredCancellationEpisode {
        var id: UUID?
        var subscriptionID: UUID?
        var markedCancelledAt: Date?
        var statusAtStart: String?
        /// yyyymmdd
        var nextChargeDateIfNotCancelled: Int?
        var expectedChargeAmountCents: Int?
        var verificationState: String?
        var unansweredCheckCount: Int?
        var verifiedAt: Date?
        var evidenceNote: String?
        var endedAt: Date?
        var outcome: String?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: OttoSchemaV2.StoredSubscription?

        init() {}
    }

    @Model
    final class StoredPauseEpisode {
        var id: UUID?
        /// yyyymmdd
        var startedOn: Int?
        /// yyyymmdd
        var scheduledResumeOn: Int?
        /// yyyymmdd
        var endedOn: Int?
        var outcome: String?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: OttoSchemaV2.StoredSubscription?

        init() {}
    }

    @Model
    final class StoredPriceChange {
        var id: UUID?
        var subscriptionID: UUID?
        /// yyyymmdd
        var effectiveDate: Int?
        var oldAmountCents: Int?
        var newAmountCents: Int?
        var source: String?
        var note: String?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: OttoSchemaV2.StoredSubscription?

        init() {}
    }

    @Model
    final class StoredPaymentMethod {
        var id: UUID?
        var label: String?
        var last4: String?
        var issuer: String?
        var expiryMonth: Int?
        var expiryYear: Int?
        var isDefault: Bool = false
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        init() {}
    }
}
