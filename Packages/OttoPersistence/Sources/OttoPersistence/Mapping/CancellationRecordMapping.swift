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
            // Nil means written before v1.5 stored the amount; the domain
            // backfills it on the next roll-forward rather than inventing one here.
            expectedChargeAmountCents: expectedChargeAmountCents,
            verificationState: try decodeRaw(verificationState, entity: entity, field: "verificationState"),
            // Written before the field existed means never rolled forward: 0.
            unansweredCheckCount: unansweredCheckCount ?? 0,
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
        expectedChargeAmountCents = domain.expectedChargeAmountCents
        verificationState = domain.verificationState.rawValue
        unansweredCheckCount = domain.unansweredCheckCount
        verifiedAt = domain.verifiedAt
        evidenceNote = domain.evidenceNote
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }
}
