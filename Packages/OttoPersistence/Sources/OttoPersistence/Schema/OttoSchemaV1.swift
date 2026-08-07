import Foundation
import SwiftData

// The FROZEN first schema version - the shape Waves 2 through 8 wrote to disk,
// kept byte-for-byte (class names, property names, storage shapes) because it
// is the source side of the V1→V2 migration and must match existing stores
// exactly. Never edit these models; schema changes happen in a new version.
//
// Wave 8.5 (spec §5.3a) replaced two of these shapes: the one-to-one
// `StoredCancellationRecord` slot and the `pausedOn`/`pauseEndsOn` field pair
// both modelled something that recurs, and V2 turns both into one-to-many
// episode tables. The migration in `OttoMigrationPlan` carries the data across.
enum OttoSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            StoredSubscription.self,
            StoredTrialTerm.self,
            StoredBillingEvent.self,
            StoredCancellationRecord.self,
            StoredPriceChange.self,
            StoredPaymentMethod.self
        ]
    }
}

extension OttoSchemaV1 {
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
        /// yyyymmdd - V1's single resume date, migrated into the open episode.
        var pauseEndsOn: Int?
        /// yyyymmdd - V1's single pause start, migrated into the open episode.
        var pausedOn: Int?
        /// yyyymmdd
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

        @Relationship(deleteRule: .cascade, inverse: \OttoSchemaV1.StoredTrialTerm.subscription)
        var trial: OttoSchemaV1.StoredTrialTerm?

        @Relationship(deleteRule: .cascade, inverse: \OttoSchemaV1.StoredBillingEvent.subscription)
        var billingEvents: [OttoSchemaV1.StoredBillingEvent]?

        @Relationship(deleteRule: .cascade, inverse: \OttoSchemaV1.StoredCancellationRecord.subscription)
        var cancellationRecord: OttoSchemaV1.StoredCancellationRecord?

        @Relationship(deleteRule: .cascade, inverse: \OttoSchemaV1.StoredPriceChange.subscription)
        var priceChanges: [OttoSchemaV1.StoredPriceChange]?

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

        var subscription: OttoSchemaV1.StoredSubscription?

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

        var subscription: OttoSchemaV1.StoredSubscription?

        init() {}
    }

    /// V1's one-to-one cancellation slot - the shape §5.3a replaced. Exists
    /// only as the migration source; the live model is V2's
    /// `StoredCancellationEpisode`.
    @Model
    final class StoredCancellationRecord {
        var id: UUID?
        var subscriptionID: UUID?
        var markedCancelledAt: Date?
        /// yyyymmdd
        var nextChargeDateIfNotCancelled: Int?
        var expectedChargeAmountCents: Int?
        var verificationState: String?
        var unansweredCheckCount: Int?
        var verifiedAt: Date?
        var evidenceNote: String?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: OttoSchemaV1.StoredSubscription?

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

        var subscription: OttoSchemaV1.StoredSubscription?

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
