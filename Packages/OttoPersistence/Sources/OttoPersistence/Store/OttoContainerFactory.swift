import SwiftData

/// Builds the app's `ModelContainer` without exposing any model type.
///
/// Both configurations pass `cloudKitDatabase: .none` deliberately: the app's
/// entitlements already carry an iCloud container (Wave 0), and `.automatic` would
/// silently switch sync on. CloudKit stays off until Wave 6 (spec §8), and this is
/// the line that keeps it off.
public enum OttoContainerFactory {
    /// The on-disk local store the app runs against.
    public static func localContainer() throws -> ModelContainer {
        try makeContainer(ModelConfiguration(schema: currentSchema, cloudKitDatabase: .none))
    }

    /// An isolated in-memory store for tests.
    public static func inMemoryContainer() throws -> ModelContainer {
        try makeContainer(
            ModelConfiguration(schema: currentSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    static var currentSchema: Schema {
        Schema(versionedSchema: OttoSchemaV1.self)
    }

    private static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: currentSchema,
            migrationPlan: OttoMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
