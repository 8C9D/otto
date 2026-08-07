import Foundation
import OttoDomain

extension OttoSchemaV1.StoredCancellationRecord {
    private static let entityName = "StoredCancellationRecord"

    func toDomain() throws -> CancellationRecord {
        let entity = Self.entityName
        let state: CancellationRecord.VerificationState = try decodeRaw(
            verificationState, entity: entity, field: "verificationState"
        )
        // The check date is required in every state except the deferred one
        // (spec §5.4): an .awaitingResumeDate record has no honest date and
        // stores none, while a nil date anywhere else is a corrupt record and
        // refused loudly - the domain's construction invariant would trap on it.
        let checkDate: CalendarDay?
        if state == .awaitingResumeDate {
            guard nextChargeDateIfNotCancelled == nil else {
                throw MappingError.invalidValue(
                    entity: entity,
                    field: "nextChargeDateIfNotCancelled",
                    value: "\(nextChargeDateIfNotCancelled.map(String.init) ?? "nil") while awaiting a resume date"
                )
            }
            checkDate = nil
        } else {
            checkDate = try CalendarDay.stored(
                nextChargeDateIfNotCancelled, entity: entity, field: "nextChargeDateIfNotCancelled"
            )
        }
        return CancellationRecord(
            id: try require(id, entity: entity, field: "id"),
            subscriptionID: try require(subscriptionID, entity: entity, field: "subscriptionID"),
            markedCancelledAt: try require(markedCancelledAt, entity: entity, field: "markedCancelledAt"),
            nextChargeDateIfNotCancelled: checkDate,
            // Nil means written before v1.5 stored the amount; the domain
            // backfills it on the next roll-forward rather than inventing one here.
            expectedChargeAmountCents: expectedChargeAmountCents,
            verificationState: state,
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
        nextChargeDateIfNotCancelled = domain.nextChargeDateIfNotCancelled?.yyyymmdd
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
