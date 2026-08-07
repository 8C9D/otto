import Foundation
import SwiftData

// The device-state store (spec §5.3): a second, LOCAL-ONLY store for anything
// that describes this device's progress rather than the user's data. The
// watermark is its first inhabitant and deliberately not its last - the store
// is named for its purpose (device-scoped bookkeeping), not for the watermark,
// so the next device-scoped thing (settings, if they ever leave UserDefaults)
// has a home without a second relocation.
//
// This schema is NOT part of `OttoMigrationPlan`: its store lives in its own
// file, is opened by its own container without a migration plan, and never
// gains a CloudKit configuration. Keeping it out of the versioned main-store
// chain is what keeps its table out of the synced store file entirely - the
// artifact-level guarantee Wave 6A exists to make.
enum OttoDeviceStateSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [StoredMaterializationWatermark.self]
    }
}

extension OttoDeviceStateSchemaV1 {
    /// This device's §5.3 materialization watermark for one subscription: the
    /// last day through which a ledger pass here has observed its expected
    /// charges. One row per subscription, keyed by scalar id - the subscription
    /// lives in a different store, so no relationship is possible, which is
    /// itself the point. No §5.0 audit quartet: this is bookkeeping a device
    /// could regenerate, not communicable user data, and it is never synced,
    /// exported, or merged.
    @Model
    final class StoredMaterializationWatermark {
        var subscriptionID: UUID?
        /// yyyymmdd
        var lastMaterializedThrough: Int?

        init() {}
    }
}

typealias StoredMaterializationWatermark = OttoDeviceStateSchemaV1.StoredMaterializationWatermark
