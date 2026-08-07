import Foundation
import OttoDomain

extension OttoSchemaV3.StoredPaymentMethod {
    private static let entityName = "StoredPaymentMethod"

    func toDomain() throws -> PaymentMethod {
        let entity = Self.entityName
        return PaymentMethod(
            id: try require(id, entity: entity, field: "id"),
            label: try require(label, entity: entity, field: "label"),
            last4: try require(last4, entity: entity, field: "last4"),
            issuer: try require(issuer, entity: entity, field: "issuer"),
            expiryMonth: try require(expiryMonth, entity: entity, field: "expiryMonth"),
            expiryYear: try require(expiryYear, entity: entity, field: "expiryYear"),
            isDefault: isDefault,
            createdAt: try require(createdAt, entity: entity, field: "createdAt"),
            updatedAt: try require(updatedAt, entity: entity, field: "updatedAt"),
            deletedAt: deletedAt
        )
    }

    func update(from domain: PaymentMethod) {
        id = domain.id
        label = domain.label
        last4 = domain.last4
        issuer = domain.issuer
        expiryMonth = domain.expiryMonth
        expiryYear = domain.expiryYear
        isDefault = domain.isDefault
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }
}
