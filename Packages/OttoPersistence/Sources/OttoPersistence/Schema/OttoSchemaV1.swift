import SwiftData

// The persistence schema, versioned from the first commit (Wave 2 constraint 4):
// once CloudKit is on (Wave 6), only lightweight-migration-compatible changes are
// permitted, so the migration machinery has to predate the constraint.
//
// Every @Model here is a PERSISTENCE RECORD ONLY, and internal on purpose: nothing
// above layer 2 can even name one. The shapes are deliberately CloudKit-compatible
// now, ahead of Wave 6, because retrofitting them later means migrating data that
// already exists on devices:
//   - no @Attribute(.unique) anywhere
//   - every property optional or carrying a default
//   - every relationship optional, with an explicit inverse
//   - no .deny delete rules
// The resulting optionals-with-defaults ugliness is absorbed entirely by the
// mapping layer; the domain never sees it.
//
// Storage shapes (decision record, Wave 2): calendar days are single Ints in
// yyyymmdd form, billing cycles are two scalar columns, enums are stable raw
// strings, money is integer cents, and UUIDs are client-generated (spec §3.5).
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

// The current schema version. Code outside the Schema directory refers to records
// through these aliases only, so moving to a V2 is a one-line change per model.
typealias StoredSubscription = OttoSchemaV1.StoredSubscription
typealias StoredTrialTerm = OttoSchemaV1.StoredTrialTerm
typealias StoredBillingEvent = OttoSchemaV1.StoredBillingEvent
typealias StoredCancellationRecord = OttoSchemaV1.StoredCancellationRecord
typealias StoredPriceChange = OttoSchemaV1.StoredPriceChange
typealias StoredPaymentMethod = OttoSchemaV1.StoredPaymentMethod
