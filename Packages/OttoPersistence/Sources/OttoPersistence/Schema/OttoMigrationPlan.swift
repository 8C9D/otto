import SwiftData

/// The migration plan, scaffolded while there is only one version so that the
/// machinery exists before CloudKit makes migrations constrained (Wave 6). A V2
/// appends its schema to `schemas` and its stage - lightweight only, once CloudKit
/// is on - to `stages`.
enum OttoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OttoSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
