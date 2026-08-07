import Foundation
import OttoDomain

extension OttoSchemaV1.StoredPriceChange {
    private static let entityName = "StoredPriceChange"

    func toDomain() throws -> PriceChange {
        let entity = Self.entityName
        return PriceChange(
            id: try require(id, entity: entity, field: "id"),
            subscriptionID: try require(subscriptionID, entity: entity, field: "subscriptionID"),
            effectiveDate: try CalendarDay.stored(effectiveDate, entity: entity, field: "effectiveDate"),
            oldAmountCents: try require(oldAmountCents, entity: entity, field: "oldAmountCents"),
            newAmountCents: try require(newAmountCents, entity: entity, field: "newAmountCents"),
            recordedAt: try require(recordedAt, entity: entity, field: "recordedAt"),
            source: try decodeRaw(source, entity: entity, field: "source"),
            note: note,
            createdAt: try require(createdAt, entity: entity, field: "createdAt"),
            updatedAt: try require(updatedAt, entity: entity, field: "updatedAt"),
            deletedAt: deletedAt
        )
    }

    func update(from domain: PriceChange) {
        id = domain.id
        subscriptionID = domain.subscriptionID
        effectiveDate = domain.effectiveDate.yyyymmdd
        oldAmountCents = domain.oldAmountCents
        newAmountCents = domain.newAmountCents
        recordedAt = domain.recordedAt
        source = domain.source.rawValue
        note = domain.note
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }
}
