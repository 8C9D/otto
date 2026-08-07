import Foundation
import OttoRepositories
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
    /// The sync decision the main container was actually OPENED with. The §8
    /// restore guard needs the session's real mode, not the current flags: the
    /// kill switch acts at the next launch, so mid-session flags and the live
    /// container can disagree in exactly the window an incident occupies.
    let mainSyncMode: OttoContainerFactory.MainStoreSyncMode
}

/// Builds the app's containers without exposing any model type.
///
/// Every configuration passes `cloudKitDatabase: .none` deliberately: the app's
/// entitlements already carry an iCloud container (Wave 0), and `.automatic`
/// would silently switch sync on. CloudKit stays off until Wave 6B (spec §8);
/// `mainStoreSyncMode(for:)` below is the single decision point that keeps it
/// off - and the runtime kill switch already sits on that path, so disabling
/// sync will never require shipping a build. The device-state store's `.none`
/// is permanent.
public enum OttoContainerFactory {

    /// What the main store's configuration should do about sync. An enum
    /// rather than `ModelConfiguration.CloudKitDatabase` so the decision is
    /// equatable and testable; today it has exactly one case.
    enum MainStoreSyncMode: Hashable {
        case off

        var cloudKitDatabase: ModelConfiguration.CloudKitDatabase {
            switch self {
            case .off: .none
            }
        }
    }

    /// THE sync decision (spec §8, Wave 6B-Prep). The kill switch and the
    /// enable flag are consulted on the real path now, while every branch
    /// still answers `.off` - so when Wave 6B adds the cloud case, the guard
    /// rails are already load-bearing and already tested, not freshly wired
    /// on the day they first matter.
    static func mainStoreSyncMode(for state: SyncState) -> MainStoreSyncMode {
        // The kill switch wins over everything, including future enablement.
        guard state.isEnabled, !state.killSwitchEngaged else { return .off }
        // Wave 6B replaces this line - and ONLY this line - with the private
        // CloudKit database mode. Until then, enabled-and-unkilled still
        // means off, because there is nothing safe to turn on.
        return .off
    }

    /// The on-disk stores the app runs against. The main store keeps its
    /// original default location; the device-state store lives beside it as
    /// `OttoDeviceState.store`.
    public static func localContainers(
        syncState: SyncState = .load()
    ) throws -> OttoContainers {
        let deviceConfiguration = ModelConfiguration(
            "OttoDeviceState", schema: deviceStateSchema, cloudKitDatabase: .none
        )
        let syncMode = mainStoreSyncMode(for: syncState)
        return try containers(
            mainConfiguration: ModelConfiguration(
                schema: mainSchema,
                cloudKitDatabase: syncMode.cloudKitDatabase
            ),
            deviceConfiguration: deviceConfiguration,
            mainSyncMode: syncMode
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
            ),
            mainSyncMode: .off
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
            ),
            mainSyncMode: .off
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
        deviceConfiguration: ModelConfiguration,
        mainSyncMode: MainStoreSyncMode
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
        return OttoContainers(main: main, deviceState: deviceState, mainSyncMode: mainSyncMode)
    }
}
