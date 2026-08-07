import Foundation
import OttoDomain

/// The §5.4 v1.9 fold upgrade's result - a tiny bundle because the state, the
/// end, and the outcome move together or not at all.
private struct FoldUpgradedState {
    var state: String?
    var endedAt: Date?
    var outcome: String?
}

extension OttoSchemaV3.StoredCancellationEpisode {
    private static let entityName = "StoredCancellationEpisode"

    func toDomain() throws -> CancellationEpisode {
        let entity = Self.entityName
        let upgraded = foldUpgradedRawState()
        let state: CancellationEpisode.VerificationState = try decodeRaw(
            upgraded.state, entity: entity, field: "verificationState"
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
        let domainOutcome: CancellationEpisode.Outcome? = try upgraded.outcome.map {
            try decodeRaw($0, entity: entity, field: "outcome")
        }
        guard (upgraded.endedAt == nil) == (domainOutcome == nil) else {
            throw MappingError.invalidValue(
                entity: entity,
                field: "endedAt/outcome",
                value: "\(upgraded.endedAt.map(String.init(describing:)) ?? "nil")/\(domainOutcome?.rawValue ?? "nil")"
            )
        }
        return CancellationEpisode(
            id: try require(id, entity: entity, field: "id"),
            subscriptionID: try require(subscriptionID, entity: entity, field: "subscriptionID"),
            markedCancelledAt: try require(markedCancelledAt, entity: entity, field: "markedCancelledAt"),
            statusAtStart: domainStatusAtStart,
            nextChargeDateIfNotCancelled: checkDate,
            // Nil means written before v1.5 stored the amount; the domain
            // backfills it on the next roll-forward rather than inventing one here.
            expectedChargeAmountCents: expectedChargeAmountCents,
            verificationState: state,
            // Written before the field existed means never rolled forward: 0.
            unansweredCheckCount: unansweredCheckCount ?? 0,
            verifiedAt: verifiedAt,
            evidenceNotes: try domainEvidenceNotes(),
            endedAt: upgraded.endedAt,
            outcome: domainOutcome,
            createdAt: try require(createdAt, entity: entity, field: "createdAt"),
            updatedAt: try require(updatedAt, entity: entity, field: "updatedAt"),
            deletedAt: deletedAt
        )
    }

    /// A status no cancellation can interrupt is data damage; nil (a migrated
    /// pre-8.5 episode) is the honest absence the restore derives from, so
    /// damage maps to nil rather than to a lie.
    private var domainStatusAtStart: SubscriptionStatus? {
        statusAtStart
            .flatMap(SubscriptionStatus.init(rawValue:))
            .flatMap { [.trial, .active, .paused].contains($0) ? $0 : nil }
    }

    /// Tombstoned notes ride along - communicable history (spec §3.5) - in
    /// deterministic order so identical stores map to identical values.
    private func domainEvidenceNotes() throws -> [EvidenceNote] {
        try (evidenceNotes ?? [])
            .map { try $0.toDomain() }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    /// The v1.9 folding upgrade, mirrored from the wire format: a stored
    /// "verifiedStopped" STATE predates the fold (the V2→V3 migration rewrites
    /// rows, but a record can arrive from outside it - a restore of an old
    /// snapshot, or a pre-fold device once CloudKit is on). Refusing it would
    /// skip the episode; upgrading it loses nothing. An open row the fold's
    /// semantics say was finished closes by `legacyClosure` - one rule, shared
    /// with the migration and the wire format, so the paths cannot drift.
    private func foldUpgradedRawState() -> FoldUpgradedState {
        guard verificationState == "verifiedStopped" else {
            return FoldUpgradedState(state: verificationState, endedAt: endedAt, outcome: outcome)
        }
        var storedEndedAt = endedAt
        var storedOutcome = outcome
        if storedEndedAt == nil && storedOutcome == nil {
            let closure = CancellationEpisode.legacyClosure(
                verificationStateRaw: verificationState,
                verifiedAt: verifiedAt,
                updatedAt: updatedAt
            )
            storedEndedAt = closure.endedAt
            storedOutcome = closure.outcome?.rawValue
        }
        return FoldUpgradedState(
            state: CancellationEpisode.VerificationState.pending.rawValue,
            endedAt: storedEndedAt,
            outcome: storedOutcome
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
        endedAt = domain.endedAt
        outcome = domain.outcome?.rawValue
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
        syncEvidenceNotes(with: domain)
    }

    /// Notes sync by id, exactly like a subscription's pause episodes: each
    /// domain note updates its record or inserts a new one, and a stored note
    /// the domain value no longer carries is soft-deleted at the episode's
    /// `updatedAt` - the domain array is the whole history, so absence is
    /// deliberate removal, never drift.
    private func syncEvidenceNotes(with domain: CancellationEpisode) {
        let storedNotes = evidenceNotes ?? []
        let storedByID = Dictionary(
            storedNotes.compactMap { record in record.id.map { ($0, record) } },
            uniquingKeysWith: { first, _ in first }
        )
        let domainIDs = Set(domain.evidenceNotes.map(\.id))
        for note in domain.evidenceNotes {
            if let existing = storedByID[note.id] {
                existing.update(from: note)
            } else {
                let record = OttoSchemaV3.StoredEvidenceNote()
                record.episode = self
                record.update(from: note)
            }
        }
        for orphan in storedNotes
        where orphan.id.map({ !domainIDs.contains($0) }) ?? true {
            if orphan.deletedAt == nil { orphan.deletedAt = domain.updatedAt }
        }
    }
}

extension OttoSchemaV3.StoredEvidenceNote {
    private static let entityName = "StoredEvidenceNote"

    func toDomain() throws -> EvidenceNote {
        let entity = Self.entityName
        return EvidenceNote(
            id: try require(id, entity: entity, field: "id"),
            text: try require(text, entity: entity, field: "text"),
            createdAt: try require(createdAt, entity: entity, field: "createdAt"),
            updatedAt: try require(updatedAt, entity: entity, field: "updatedAt"),
            deletedAt: deletedAt
        )
    }

    func update(from domain: EvidenceNote) {
        id = domain.id
        text = domain.text
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }
}
