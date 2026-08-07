import Foundation
import OttoDomain

extension OttoSchemaV1.StoredCancellationRecord {
    private static let entityName = "StoredCancellationRecord"

    func toDomain() throws -> CancellationRecord {
        let entity = Self.entityName
        return CancellationRecord(
            id: try require(id, entity: entity, field: "id"),
            subscriptionID: try require(subscriptionID, entity: entity, field: "subscriptionID"),
            markedCancelledAt: try require(markedCancelledAt, entity: entity, field: "markedCancelledAt"),
            nextChargeDateIfNotCancelled: try CalendarDay.stored(
                nextChargeDateIfNotCancelled, entity: entity, field: "nextChargeDateIfNotCancelled"
            ),
            verificationState: try decodeRaw(verificationState, entity: entity, field: "verificationState"),
            verifiedAt: verifiedAt,
            evidenceNote: evidenceNote,
            createdAt: try require(createdAt, entity: entity, field: "createdAt"),
            updatedAt: try require(updatedAt, entity: entity, field: "updatedAt"),
            deletedAt: deletedAt
        )
    }

    func update(from domain: CancellationRecord) {
        id = domain.id
        subscriptionID = domain.subscriptionID
        markedCancelledAt = domain.markedCancelledAt
        nextChargeDateIfNotCancelled = domain.nextChargeDateIfNotCancelled.yyyymmdd
        verificationState = domain.verificationState.rawValue
        verifiedAt = domain.verifiedAt
        evidenceNote = domain.evidenceNote
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }
}
