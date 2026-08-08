import Foundation
import OttoDomain
import SwiftData

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

    /// Notes upsert by id, exactly like a subscription's pause episodes: each
    /// domain note updates the record carrying its id or inserts a new one. A
    /// stored note the domain value does not carry is left untouched - absence
    /// is not deletion (spec §4a, Wave 6B-Prep); removing a note is the domain
    /// note carrying its tombstone (the evidence flow already writes it), never
    /// an absent array slot.
    ///
    /// A note stored under a DIFFERENT episode is reparented here, not copied
    /// (spec §5.0a): the rival-cancellation merge moves the losers' notes to
    /// the winner, and this is the one place note records come from - so no
    /// applier path can put one note id on records under two parents, the
    /// collision CloudKit turns real in 6B.
    private func syncEvidenceNotes(with domain: CancellationEpisode) {
        let storedByID = Dictionary(
            (evidenceNotes ?? []).compactMap { record in record.id.map { ($0, record) } },
            uniquingKeysWith: { first, _ in first }
        )
        for note in domain.evidenceNotes {
            if let existing = storedByID[note.id] {
                existing.update(from: note)
            } else if let elsewhere = storedNoteAnywhere(id: note.id) {
                elsewhere.episode = self
                elsewhere.update(from: note)
            } else {
                let record = OttoSchemaV3.StoredEvidenceNote()
                record.episode = self
                record.update(from: note)
            }
        }
    }

    /// The whole-store lookup behind the reparent: nil when the id is genuinely
    /// new (or this record is not yet in a context - then nothing can collide).
    /// This runs inside restore's no-throw mutation phase, so a failed fetch
    /// cannot propagate; it is logged and falls back to inserting, which is
    /// the pre-§5.0a behavior rather than silence.
    private func storedNoteAnywhere(id noteID: UUID) -> OttoSchemaV3.StoredEvidenceNote? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<OttoSchemaV3.StoredEvidenceNote>(
            predicate: #Predicate { $0.id == noteID }
        )
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            mappingLogger.error("Evidence-note reparent lookup failed: \(String(describing: error))")
            return nil
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
