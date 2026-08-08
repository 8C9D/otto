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
        [StoredMaterializationWatermark.self, StoredRestoreDirtyFlag.self]
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

extension OttoDeviceStateSchemaV1 {
    /// The §5.3 restore dirty flag (v2.2): its presence means a replace-restore
    /// began and its watermark reconstruction has not committed, so the stored
    /// watermarks may vouch for ledger rows the database does not have - the
    /// stale-ahead direction the design refuses. Written durably BEFORE the
    /// restore's main-store save, deleted in the same device-store save that
    /// writes the reconstructed watermarks; while present, every watermark
    /// access reconstructs first, so the crash window between the two saves
    /// self-heals through the mechanism that already exists. Existence IS the
    /// flag; the instant is diagnostic only. Additive to this schema, which is
    /// local-only, outside the migration plan, and not part of frozen V3.
    @Model
    final class StoredRestoreDirtyFlag {
        var markedAt: Date?

        init() {}
    }
}

typealias StoredMaterializationWatermark = OttoDeviceStateSchemaV1.StoredMaterializationWatermark
typealias StoredRestoreDirtyFlag = OttoDeviceStateSchemaV1.StoredRestoreDirtyFlag
