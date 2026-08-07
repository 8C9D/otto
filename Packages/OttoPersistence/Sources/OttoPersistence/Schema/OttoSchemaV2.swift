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
//
// V2 is Wave 8.5's model lock (spec §5.3a): the one-to-one cancellation slot
// and the single pause-field pair become one-to-many episode tables - the one
// change class that cannot be made cheaply after Wave 6, made while it is
// still cheap. This is the schema-freeze candidate.
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

// The current schema version. Code outside the Schema directory refers to records
// through these aliases only, so moving to a V3 is a one-line change per model.
typealias StoredSubscription = OttoSchemaV2.StoredSubscription
typealias StoredTrialTerm = OttoSchemaV2.StoredTrialTerm
typealias StoredBillingEvent = OttoSchemaV2.StoredBillingEvent
typealias StoredCancellationEpisode = OttoSchemaV2.StoredCancellationEpisode
typealias StoredPauseEpisode = OttoSchemaV2.StoredPauseEpisode
typealias StoredPriceChange = OttoSchemaV2.StoredPriceChange
typealias StoredPaymentMethod = OttoSchemaV2.StoredPaymentMethod
