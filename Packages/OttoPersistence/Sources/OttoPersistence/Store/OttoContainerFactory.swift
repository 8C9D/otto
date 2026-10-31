import CoreData
import Foundation
import OttoRepositories
import SwiftData
import os

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
    /// The asked-for mirrored store failed to open and this session fell back
    /// to the local one. The app must still open: the flags that caused the
    /// failure live in `UserDefaults`, and the only screen that can change
    /// them is behind this launch.
    public let mirroredOpenFailed: Bool

    /// What this launch's main store is actually doing, for everything above
    /// the factory.
    public var syncSessionMode: SyncSessionMode { mainSyncMode.sessionMode }
}

/// Builds the app's containers without exposing any model type.
///
/// Every configuration passes `cloudKitDatabase: .none` deliberately: the app's
/// entitlements carry an iCloud container (Wave 0), and `.automatic` would
/// silently switch sync on. `mainStoreSyncMode(for:cloudContainerIdentifier:)`
/// below is the single decision point that can turn mirroring on - and the
/// runtime kill switch sits on that path, so disabling sync never requires
/// shipping a build. The device-state store's `.none` is permanent.
public enum OttoContainerFactory {

    private static let syncOpenLogger = Logger(subsystem: "com.arthurzhang.otto", category: "sync")

    /// What the main store's configuration should do about sync. An enum
    /// rather than `ModelConfiguration.CloudKitDatabase` so the decision is
    /// equatable and testable.
    enum MainStoreSyncMode: Hashable {
        case off
        case cloudKitPrivate(containerIdentifier: String)

        var cloudKitDatabase: ModelConfiguration.CloudKitDatabase {
            switch self {
            case .off: .none
            case .cloudKitPrivate(let containerIdentifier): .private(containerIdentifier)
            }
        }

        var sessionMode: SyncSessionMode {
            switch self {
            case .off: .off
            case .cloudKitPrivate: .mirrored
            }
        }
    }

    /// THE sync decision (spec §8, Wave 6B). Three things must all hold: the
    /// user turned sync on, the kill switch is not engaged, and this BUILD
    /// names a container. The last is what keeps a release off until its
    /// CloudKit schema is deployed to production - a nil identifier means
    /// "this build has nowhere to sync to", whatever the flags say.
    static func mainStoreSyncMode(
        for state: SyncState, cloudContainerIdentifier: String?
    ) -> MainStoreSyncMode {
        // The kill switch wins over everything.
        guard state.isEnabled, !state.killSwitchEngaged,
              let cloudContainerIdentifier, !cloudContainerIdentifier.isEmpty
        else { return .off }
        return .cloudKitPrivate(containerIdentifier: cloudContainerIdentifier)
    }

    /// The on-disk stores the app runs against. The main store keeps its
    /// original default location; the device-state store lives beside it as
    /// `OttoDeviceState.store`.
    ///
    /// `cloudContainerIdentifier` defaults to nil so that no caller can reach
    /// mirroring by omission: the composition root is the one place that
    /// passes it. Mirroring needs the file left exactly where it was - the same
    /// default location - because turning sync on must not move anyone's data.
    public static func localContainers(
        syncState: SyncState = .load(),
        cloudContainerIdentifier: String? = nil
    ) throws -> OttoContainers {
        try opening(
            mainStoreSyncMode(for: syncState, cloudContainerIdentifier: cloudContainerIdentifier)
        ) { mode, failed in
            try localContainers(syncMode: mode, mirroredOpenFailed: failed)
        }
    }

    /// Opens `mode`, falling back to the local store if a mirrored open fails.
    /// Only the mirrored open gets a second try: if the LOCAL store cannot
    /// open, that is the failure the launch screen exists to report.
    static func opening(
        _ mode: MainStoreSyncMode,
        with open: (MainStoreSyncMode, _ mirroredOpenFailed: Bool) throws -> OttoContainers
    ) throws -> OttoContainers {
        do {
            return try open(mode, false)
        } catch {
            guard mode != .off else { throw error }
            syncOpenLogger.error("""
                mirrored store failed to open; continuing locally: \(String(describing: error), privacy: .public)
                """)
            return try open(.off, true)
        }
    }

    private static func localContainers(
        syncMode: MainStoreSyncMode, mirroredOpenFailed: Bool
    ) throws -> OttoContainers {
        try containers(
            mainConfiguration: ModelConfiguration(
                schema: mainSchema,
                cloudKitDatabase: syncMode.cloudKitDatabase
            ),
            deviceConfiguration: ModelConfiguration(
                "OttoDeviceState", schema: deviceStateSchema, cloudKitDatabase: .none
            ),
            mainSyncMode: syncMode,
            mirroredOpenFailed: mirroredOpenFailed
        )
    }

    /// Pushes the whole V3 schema to the CloudKit DEVELOPMENT environment.
    ///
    /// Required once before the schema is deployed to production: the framework
    /// otherwise creates record fields lazily, from values actually exported,
    /// so an attribute that happened to be nil on every record never reaches
    /// the schema - and production rejects it the first time it is non-nil.
    /// SwiftData has no equivalent, so this drops to the `CoreData` container
    /// over the same model, on a throwaway store: the placeholder records it
    /// uploads must never touch the user's.
    ///
    /// Debug-only by its one caller; it needs a signed-in iCloud account.
    public static func initializeCloudKitSchema(containerIdentifier: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OttoCloudKitSchema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: OttoSchemaV3.models) else {
            throw SchemaInitializationError.modelUnavailable
        }
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("schema.store"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

        let container = NSPersistentCloudKitContainer(name: "OttoSchemaInitialization", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        try container.initializeCloudKitSchema()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    enum SchemaInitializationError: Error {
        case modelUnavailable
    }

    /// Isolated in-memory stores for tests. `recordingSyncMode` states the mode
    /// the store BELIEVES it opened with, without any CloudKit behind it: the
    /// guards read that value, and a host test has no iCloud to open a real one.
    public static func inMemoryContainers() throws -> OttoContainers {
        try inMemoryContainers(recordingSyncMode: .off)
    }

    static func inMemoryContainers(recordingSyncMode: MainStoreSyncMode) throws -> OttoContainers {
        try containers(
            mainConfiguration: ModelConfiguration(
                schema: mainSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            ),
            deviceConfiguration: ModelConfiguration(
                schema: deviceStateSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            ),
            mainSyncMode: recordingSyncMode
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
        mainSyncMode: MainStoreSyncMode,
        mirroredOpenFailed: Bool = false
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
        return OttoContainers(
            main: main, deviceState: deviceState,
            mainSyncMode: mainSyncMode, mirroredOpenFailed: mirroredOpenFailed
        )
    }
}
