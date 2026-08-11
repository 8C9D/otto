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

        /// R0-9. `schemas` and `stages` are two independent literals, and until
        /// this test nothing related them: appending `OttoSchemaV4` to
        /// `schemas` and pointing `mainSchema` at it - with no stage - left all
        /// 118 tests green, while the carry-over that moves user data out of V3
        /// did not exist. That is the contract's own named hazard in its next
        /// form, and this file exists to catch such a mistake at the moment it
        /// is made rather than on a device.
        ///
        /// It asserts the CHAIN, not just the count. A count catches the
        /// forgotten stage; only the chain catches a stage that was added and
        /// wired wrong - `V2 → V4`, a duplicate, a reordering - each of which
        /// leaves a version no stage reaches while the arithmetic still works.
        @Test("every schema version after the first is reached by a stage, in order")
        func stagesChainTheSchemas() throws {
            let versions = OttoMigrationPlan.schemas.map { $0.versionIdentifier }
            let stages = OttoMigrationPlan.stages
            // A degenerate plan proves nothing: a single-version chain would
            // satisfy every assertion below by having none to make.
            #expect(versions.count >= 2)
            #expect(!stages.isEmpty)
            #expect(
                stages.count == versions.count - 1,
                "\(versions.count) schema versions need \(versions.count - 1) stages, found \(stages.count)"
            )

            for (index, stage) in stages.enumerated() where index + 1 < versions.count {
                let hop = try #require(
                    Self.versions(of: stage),
                    """
                    could not read stage \(index)'s versions - MigrationStage's payload no longer \
                    reflects as (fromVersion, toVersion), so THIS GUARD IS NOT GUARDING. Fix the \
                    extraction; do not delete the test.
                    """
                )
                #expect(
                    hop.fromVersion == versions[index],
                    "stage \(index) starts at \(hop.fromVersion), not \(versions[index])"
                )
                #expect(
                    hop.toVersion == versions[index + 1],
                    "stage \(index) ends at \(hop.toVersion), not \(versions[index + 1])"
                )
            }
        }

        /// The two schema versions a `MigrationStage` connects.
        ///
        /// `MigrationStage` publishes no accessor for them, so this reads the
        /// enum's own payload by reflection - which works identically for
        /// `.lightweight` and `.custom`, both of whose payloads label their
        /// first two elements `fromVersion` and `toVersion`.
        ///
        /// It FAILS CLOSED on purpose: an extraction that finds nothing returns
        /// nil and the caller records an issue naming that cause, because a
        /// guard that quietly stops guarding is the exact failure this file was
        /// rebuilt to prevent.
        private static func versions(
            of stage: MigrationStage
        ) -> (fromVersion: Schema.Version, toVersion: Schema.Version)? {
            guard let payload = Mirror(reflecting: stage).children.first?.value else { return nil }
            var fromVersion: Schema.Version?
            var toVersion: Schema.Version?
            for child in Mirror(reflecting: payload).children {
                guard let schema = child.value as? any VersionedSchema.Type else { continue }
                switch child.label {
                case "fromVersion": fromVersion = schema.versionIdentifier
                case "toVersion": toVersion = schema.versionIdentifier
                default: continue
                }
            }
            guard let fromVersion, let toVersion else { return nil }
            return (fromVersion, toVersion)
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
