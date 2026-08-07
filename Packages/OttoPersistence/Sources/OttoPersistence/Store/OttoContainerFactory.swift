import Foundation
import SwiftData

/// The two containers the app runs on (spec §5.3, Wave 6A): the main store
/// (user data - the schema CloudKit will eventually sync) and the device-state
/// store (this device's bookkeeping - never synced, never exported). They are
/// separate `ModelContainer`s, not two configurations of one, so the main
/// store's staged migration plan never has to reason about a store that holds
/// none of its versioned models - and so no future configuration change can
/// accidentally sweep device state into the synced schema.
public struct OttoContainers: Sendable {
    public let main: ModelContainer
    public let deviceState: ModelContainer
}

/// Builds the app's containers without exposing any model type.
///
/// Every configuration passes `cloudKitDatabase: .none` deliberately: the app's
/// entitlements already carry an iCloud container (Wave 0), and `.automatic`
/// would silently switch sync on. CloudKit stays off until Wave 6B (spec §8),
/// and this is the line that keeps it off. When 6B flips the main store's
/// setting, the device-state store's `.none` is permanent.
public enum OttoContainerFactory {
    /// The on-disk stores the app runs against. The main store keeps its
    /// original default location; the device-state store lives beside it as
    /// `OttoDeviceState.store`.
    public static func localContainers() throws -> OttoContainers {
        let deviceConfiguration = ModelConfiguration(
            "OttoDeviceState", schema: deviceStateSchema, cloudKitDatabase: .none
        )
        return try containers(
            mainConfiguration: ModelConfiguration(schema: mainSchema, cloudKitDatabase: .none),
            deviceConfiguration: deviceConfiguration
        )
    }

    /// Isolated in-memory stores for tests.
    public static func inMemoryContainers() throws -> OttoContainers {
        try containers(
            mainConfiguration: ModelConfiguration(
                schema: mainSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            ),
            deviceConfiguration: ModelConfiguration(
                schema: deviceStateSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )
        )
    }

    /// Explicit-URL variant for migration tests, which build stores on disk.
    static func onDiskContainers(mainURL: URL, deviceStateURL: URL) throws -> OttoContainers {
        try containers(
            mainConfiguration: ModelConfiguration(
                schema: mainSchema, url: mainURL, cloudKitDatabase: .none
            ),
            deviceConfiguration: ModelConfiguration(
                schema: deviceStateSchema, url: deviceStateURL, cloudKitDatabase: .none
            )
        )
    }

    static var mainSchema: Schema {
        Schema(versionedSchema: OttoSchemaV3.self)
    }

    static var deviceStateSchema: Schema {
        Schema(versionedSchema: OttoDeviceStateSchemaV1.self)
    }

    private static func containers(
        mainConfiguration: ModelConfiguration,
        deviceConfiguration: ModelConfiguration
    ) throws -> OttoContainers {
        // The V2→V3 stage needs the device store's location BEFORE the main
        // container opens: the watermark carry-over happens inside the
        // migration, durably, while the V2 column still exists.
        if !deviceConfiguration.isStoredInMemoryOnly {
            OttoMigrationPlan.deviceStateStoreURL.withLock { $0 = deviceConfiguration.url }
        }
        let main = try ModelContainer(
            for: mainSchema,
            migrationPlan: OttoMigrationPlan.self,
            configurations: [mainConfiguration]
        )
        // No migration plan: this store never contains anything the staged
        // plan versions, and its own schema evolves additively if at all.
        let deviceState = try ModelContainer(
            for: deviceStateSchema,
            configurations: [deviceConfiguration]
        )
        return OttoContainers(main: main, deviceState: deviceState)
    }
}
