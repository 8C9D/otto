import Foundation
import SwiftData
import Testing
@testable import OttoPersistence

/// The Wave 2 guard, made structurally unable to go stale in Wave 6B-Prep. It
/// spent Wave 6A green while asserting `OttoSchemaV2` after V3 became real -
/// a guard pinned to a version number stops guarding without ever failing. It
/// now derives everything from `OttoContainerFactory.mainSchema` - the schema
/// the app actually opens - so a new model or a new version is walked the
/// moment the factory adopts it, with no name here to forget to update; and
/// the first test pins the factory to the migration plan's terminal version,
/// so the factory itself cannot silently lag the plan.
///
/// What it guards: CloudKit (Wave 6B) requires model shapes - no unique
/// constraints, everything optional or defaulted, relationships optional with
/// inverses, no .deny delete rules - that are easy to break by accident in
/// the months before it is switched on. Retrofitting them later means
/// migrating data that already exists on devices, so any schema change that
/// violates them must fail HERE, at the moment of the mistake.
extension SerializedPersistenceTests {
    @Suite("CloudKit compatibility (Wave 6 readiness)")
    struct CloudKitCompatibilityTests {

        @Test("the schema under test IS the schema the app opens, at the migration plan's terminal version")
        func guardTargetsTheLiveSchema() throws {
            let live = OttoContainerFactory.mainSchema
            let terminal = try #require(OttoMigrationPlan.schemas.last)
            // The factory sits at the end of the migration chain - the exact
            // staleness that happened once: a plan that moved on while a
            // version-pinned reference stayed green.
            #expect(live.version == terminal.versionIdentifier)
            #expect(Set(live.entities.map(\.name)) == Set(terminal.models.map { Schema.entityName(for: $0) }))
            // A degenerate walk proves nothing: the guard must be walking
            // real entities for the assertions below to mean anything.
            #expect(live.entities.count == terminal.models.count)
            #expect(!live.entities.isEmpty)
        }

        @Test("no attribute is unique, and every attribute is optional or has a default")
        func attributes() {
            for entity in OttoContainerFactory.mainSchema.entities {
                for attribute in entity.attributes {
                    #expect(
                        !attribute.isUnique,
                        "\(entity.name).\(attribute.name) is unique; CloudKit forbids unique constraints"
                    )
                    #expect(
                        attribute.isOptional || attribute.defaultValue != nil,
                        "\(entity.name).\(attribute.name) is required with no default; CloudKit forbids that"
                    )
                }
            }
        }

        @Test("every relationship is optional, has an explicit inverse, and never denies deletes")
        func relationships() {
            for entity in OttoContainerFactory.mainSchema.entities {
                for relationship in entity.relationships {
                    #expect(
                        relationship.isOptional,
                        "\(entity.name).\(relationship.name) is a required relationship; CloudKit forbids that"
                    )
                    #expect(
                        relationship.deleteRule != .deny,
                        "\(entity.name).\(relationship.name) uses .deny; CloudKit does not support it"
                    )
                    #expect(
                        relationship.inverseName != nil,
                        "\(entity.name).\(relationship.name) has no inverse; CloudKit requires one"
                    )
                }
            }
        }

        @Test("the synced schema contains nothing device-scoped: no watermark field, no watermark entity")
        func nothingDeviceScoped() {
            for entity in OttoContainerFactory.mainSchema.entities {
                #expect(
                    entity.attributes.allSatisfy { $0.name != "lastMaterializedThrough" },
                    "\(entity.name) still carries the device-local watermark (spec §5.3)"
                )
            }
            #expect(OttoContainerFactory.mainSchema.entities.allSatisfy {
                $0.name != "StoredMaterializationWatermark"
            })
        }
    }
}
