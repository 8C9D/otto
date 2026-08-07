import Foundation
import OttoDomain

extension OttoSchemaV2.StoredCancellationEpisode {
    private static let entityName = "StoredCancellationEpisode"

    func toDomain() throws -> CancellationEpisode {
        let entity = Self.entityName
        let state: CancellationEpisode.VerificationState = try decodeRaw(
            verificationState, entity: entity, field: "verificationState"
        )
        // The check date is required in every state except the deferred one
        // (spec §5.4): an .awaitingResumeDate episode has no honest date and
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
        // Open or closed, never half (spec §5.3a) - refused here for the same
        // reason as the date pairing above.
        let domainOutcome: CancellationEpisode.Outcome? = try self.outcome.map {
            try decodeRaw($0, entity: entity, field: "outcome")
        }
        guard (endedAt == nil) == (domainOutcome == nil) else {
            throw MappingError.invalidValue(
                entity: entity,
                field: "endedAt/outcome",
                value: "\(endedAt.map(String.init(describing:)) ?? "nil")/\(domainOutcome?.rawValue ?? "nil")"
            )
        }
        // A status no cancellation can interrupt is data damage; nil (a
        // migrated pre-8.5 episode) is the honest absence the restore derives
        // from, so damage maps to nil rather than to a lie.
        let statusAtStart: SubscriptionStatus? = self.statusAtStart
            .flatMap(SubscriptionStatus.init(rawValue:))
            .flatMap { [.trial, .active, .paused].contains($0) ? $0 : nil }
        return CancellationEpisode(
            id: try require(id, entity: entity, field: "id"),
            subscriptionID: try require(subscriptionID, entity: entity, field: "subscriptionID"),
            markedCancelledAt: try require(markedCancelledAt, entity: entity, field: "markedCancelledAt"),
            statusAtStart: statusAtStart,
            nextChargeDateIfNotCancelled: checkDate,
            // Nil means written before v1.5 stored the amount; the domain
            // backfills it on the next roll-forward rather than inventing one here.
            expectedChargeAmountCents: expectedChargeAmountCents,
            verificationState: state,
            // Written before the field existed means never rolled forward: 0.
            unansweredCheckCount: unansweredCheckCount ?? 0,
            verifiedAt: verifiedAt,
            evidenceNote: evidenceNote,
            endedAt: endedAt,
            outcome: domainOutcome,
            createdAt: try require(createdAt, entity: entity, field: "createdAt"),
            updatedAt: try require(updatedAt, entity: entity, field: "updatedAt"),
            deletedAt: deletedAt
        )
    }

    func update(from domain: CancellationEpisode) {
        id = domain.id
        subscriptionID = domain.subscriptionID
        markedCancelledAt = domain.markedCancelledAt
        statusAtStart = domain.statusAtStart?.rawValue
        nextChargeDateIfNotCancelled = domain.nextChargeDateIfNotCancelled?.yyyymmdd
        expectedChargeAmountCents = domain.expectedChargeAmountCents
        verificationState = domain.verificationState.rawValue
        unansweredCheckCount = domain.unansweredCheckCount
        verifiedAt = domain.verifiedAt
        evidenceNote = domain.evidenceNote
        endedAt = domain.endedAt
        outcome = domain.outcome?.rawValue
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }
}
