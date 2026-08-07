import Foundation
import OttoDomain

extension OttoSchemaV2.StoredBillingEvent {
    private static let entityName = "StoredBillingEvent"

    func toDomain() throws -> BillingEvent {
        let entity = Self.entityName
        return BillingEvent(
            id: try require(id, entity: entity, field: "id"),
            subscriptionID: try require(subscriptionID, entity: entity, field: "subscriptionID"),
            expectedDate: try CalendarDay.stored(expectedDate, entity: entity, field: "expectedDate"),
            expectedAmountCents: try require(expectedAmountCents, entity: entity, field: "expectedAmountCents"),
            state: try decodeRaw(state, entity: entity, field: "state"),
            userConfirmedAt: userConfirmedAt,
            acknowledgedAt: acknowledgedAt,
            actualAmountCents: actualAmountCents,
            createdAt: try require(createdAt, entity: entity, field: "createdAt"),
            updatedAt: try require(updatedAt, entity: entity, field: "updatedAt"),
            deletedAt: deletedAt
        )
    }

    func update(from domain: BillingEvent) {
        id = domain.id
        subscriptionID = domain.subscriptionID
        expectedDate = domain.expectedDate.yyyymmdd
        expectedAmountCents = domain.expectedAmountCents
        state = domain.state.rawValue
        userConfirmedAt = domain.userConfirmedAt
        acknowledgedAt = domain.acknowledgedAt
        actualAmountCents = domain.actualAmountCents
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }
}
