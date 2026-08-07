import Foundation
import SwiftData
import Testing
@testable import OttoPersistence

/// The highest-value guard in this wave: CloudKit (Wave 6) requires model shapes -
/// no unique constraints, everything optional or defaulted, relationships optional
/// with inverses, no .deny delete rules - that are easy to break by accident in the
/// months before it is switched on. Retrofitting them later means migrating data
/// that already exists on devices, so any schema change that violates them must
/// fail HERE, at the moment of the mistake.
extension SerializedPersistenceTests {
    @Suite("CloudKit compatibility (Wave 6 readiness)")
    struct CloudKitCompatibilityTests {

        @Test("no attribute is unique, and every attribute is optional or has a default")
        func attributes() {
            let schema = Schema(versionedSchema: OttoSchemaV2.self)
            for entity in schema.entities {
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
            let schema = Schema(versionedSchema: OttoSchemaV2.self)
            for entity in schema.entities {
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

        @Test("the schema actually contains all seven models - the assertions above cover everything")
        func coverage() {
            let schema = Schema(versionedSchema: OttoSchemaV2.self)
            #expect(schema.entities.count == 7)
        }
    }
}
