import SwiftData

// The persistence schema, versioned from the first commit (Wave 2 constraint 4):
// once CloudKit is on (Wave 6B), only lightweight-migration-compatible changes
// are permitted, so the migration machinery has to predate the constraint.
//
// Every @Model here is a PERSISTENCE RECORD ONLY, and internal on purpose: nothing
// above layer 2 can even name one. The shapes are deliberately CloudKit-compatible
// now, ahead of Wave 6B, because retrofitting them later means migrating data that
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
//
// V3 is Wave 6A's relocation (spec §5.3): `lastMaterializedThrough` leaves
// `StoredSubscription` for the device-state store, so the schema CloudKit will
// sync no longer contains anything device-scoped. This is the frozen schema.
enum OttoSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

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

// The current schema version. Code outside the Schema directory refers to records
// through these aliases only, so moving to a V4 is a one-line change per model.
typealias StoredSubscription = OttoSchemaV3.StoredSubscription
typealias StoredTrialTerm = OttoSchemaV3.StoredTrialTerm
typealias StoredBillingEvent = OttoSchemaV3.StoredBillingEvent
typealias StoredCancellationEpisode = OttoSchemaV3.StoredCancellationEpisode
typealias StoredPauseEpisode = OttoSchemaV3.StoredPauseEpisode
typealias StoredPriceChange = OttoSchemaV3.StoredPriceChange
typealias StoredPaymentMethod = OttoSchemaV3.StoredPaymentMethod
