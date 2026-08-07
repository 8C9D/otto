import Foundation

/// The §5.4 v1.9 fold upgrade's result - a tiny bundle because the state, the
/// end, and the outcome move together or not at all.
private struct FoldUpgradedState {
    var state: String
    var endedAt: Date?
    var outcome: String?
}

/// The wire record for `EvidenceNote` (spec §5.4, a list since format v3).
public struct ExportedEvidenceNote: Codable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(_ domain: EvidenceNote) {
        id = domain.id
        text = domain.text
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }

    public func domainValue() -> EvidenceNote {
        EvidenceNote(id: id, text: text, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}

/// The wire record for `CancellationEpisode` (spec §5.4, §3.5) - split from
/// ExportFormatRecords because it carries the format's heaviest upgrade logic:
/// the §5.3a open-or-closed pairing, the v1 closure rule, the §5.4 v1.9 fold
/// upgrade, and the pre-v3 single-evidence-note upgrade.
public struct ExportedCancellationEpisode: Codable, Hashable, Sendable {
    public let id: UUID
    public let subscriptionID: UUID
    public var markedCancelledAt: Date
    /// Absent in v1 files, which never captured what the cancellation
    /// interrupted; the un-cancel restore derives an honest answer for nil.
    public var statusAtStart: String?
    public var nextChargeDateIfNotCancelled: String?
    public var expectedChargeAmountCents: Int?
    public var verificationState: String
    public var unansweredCheckCount: Int
    public var verifiedAt: Date?
    /// Pre-v3's single note - read forever, never written (fresh exports carry
    /// a nil here, which synthesized Codable omits from the file).
    public var legacyEvidenceNote: String?
    /// Absent (nil) exactly in pre-v3 files; `domainValue` upgrades the legacy
    /// single note by `EvidenceNote.legacyNote` - one rule with the SwiftData
    /// migration, so the paths cannot drift.
    public var evidenceNotes: [ExportedEvidenceNote]?
    /// Absent in v1 files; `upgradedFromV1` closes what v1 semantics say was
    /// finished and leaves the rest open (spec §5.3a).
    public var endedAt: Date?
    public var outcome: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, subscriptionID, markedCancelledAt, statusAtStart, nextChargeDateIfNotCancelled
        case expectedChargeAmountCents, verificationState, unansweredCheckCount, verifiedAt
        /// v3 renamed the concept; the old key is read, never written.
        case legacyEvidenceNote = "evidenceNote"
        case evidenceNotes
        case endedAt, outcome, createdAt, updatedAt, deletedAt
    }

    public init(_ domain: CancellationEpisode) {
        id = domain.id
        subscriptionID = domain.subscriptionID
        markedCancelledAt = domain.markedCancelledAt
        statusAtStart = domain.statusAtStart?.rawValue
        nextChargeDateIfNotCancelled = domain.nextChargeDateIfNotCancelled?.description
        expectedChargeAmountCents = domain.expectedChargeAmountCents
        verificationState = domain.verificationState.rawValue
        unansweredCheckCount = domain.unansweredCheckCount
        verifiedAt = domain.verifiedAt
        legacyEvidenceNote = nil
        evidenceNotes = domain.evidenceNotes
            .map(ExportedEvidenceNote.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        endedAt = domain.endedAt
        outcome = domain.outcome?.rawValue
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }

    public func domainValue() throws -> CancellationEpisode {
        let entity = "cancellationEpisode \(id)"
        let upgraded = foldUpgradedRawState()
        let (stateRaw, wireEndedAt, wireOutcome) = (upgraded.state, upgraded.endedAt, upgraded.outcome)
        let state: CancellationEpisode.VerificationState = try wireEnum(
            stateRaw, entity: entity, field: "verificationState"
        )
        let checkDate = try wireDay(
            nextChargeDateIfNotCancelled, entity: entity, field: "nextChargeDateIfNotCancelled"
        )
        // The §5.4 pairing invariant, thrown instead of the domain's precondition.
        guard (checkDate == nil) == (state == .awaitingResumeDate) else {
            throw ExportFormatError.invalidValue(
                entity: entity,
                field: "nextChargeDateIfNotCancelled",
                value: "\(nextChargeDateIfNotCancelled ?? "absent") while \(verificationState)"
            )
        }
        // The §5.3a open-or-closed pairing, thrown for the same reason.
        let domainOutcome: CancellationEpisode.Outcome? = try wireOutcome.map {
            try wireEnum($0, entity: entity, field: "outcome")
        }
        guard (wireEndedAt == nil) == (domainOutcome == nil) else {
            throw ExportFormatError.invalidValue(
                entity: entity,
                field: "endedAt/outcome",
                value: "\(wireEndedAt.map(String.init(describing:)) ?? "absent")/\(wireOutcome ?? "absent")"
            )
        }
        // Only a state a cancellation can interrupt is a valid start
        // (spec §5.3a); anything else in the field is a damaged file.
        let domainStatusAtStart: SubscriptionStatus? = try statusAtStart.map {
            let status: SubscriptionStatus = try wireEnum($0, entity: entity, field: "statusAtStart")
            guard [.trial, .active, .paused].contains(status) else {
                throw ExportFormatError.invalidValue(entity: entity, field: "statusAtStart", value: $0)
            }
            return status
        }
        return CancellationEpisode(
            id: id,
            subscriptionID: subscriptionID,
            markedCancelledAt: markedCancelledAt,
            statusAtStart: domainStatusAtStart,
            nextChargeDateIfNotCancelled: checkDate,
            expectedChargeAmountCents: expectedChargeAmountCents,
            verificationState: state,
            unansweredCheckCount: unansweredCheckCount,
            verifiedAt: verifiedAt,
            evidenceNotes: upgradedEvidenceNotes(),
            endedAt: wireEndedAt,
            outcome: domainOutcome,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    /// The v1.9 folding upgrade, applied at read forever: `.verifiedStopped`
    /// left `verificationState` (reaching that result closes the episode, it
    /// does not set a state), but v1 and v2 files carry the string. A closed
    /// episode keeps `.pending` as its vestigial live state; an open one -
    /// malformed under both old and new semantics, since the single writer
    /// always closed alongside - closes by the same rule v1 records do
    /// (`CancellationEpisode.legacyClosure`), so the upgrade paths cannot drift.
    private func foldUpgradedRawState() -> FoldUpgradedState {
        guard verificationState == "verifiedStopped" else {
            return FoldUpgradedState(state: verificationState, endedAt: endedAt, outcome: outcome)
        }
        var wireEndedAt = endedAt
        var wireOutcome = outcome
        if wireEndedAt == nil && wireOutcome == nil {
            let closure = CancellationEpisode.legacyClosure(
                verificationStateRaw: verificationState,
                verifiedAt: verifiedAt,
                updatedAt: updatedAt
            )
            wireEndedAt = closure.endedAt
            wireOutcome = closure.outcome?.rawValue
        }
        return FoldUpgradedState(
            state: CancellationEpisode.VerificationState.pending.rawValue,
            endedAt: wireEndedAt,
            outcome: wireOutcome
        )
    }

    /// The pre-v3 evidence upgrade, applied at read forever: a file written
    /// before format v3 carries at most one `evidenceNote` string, which
    /// becomes one `EvidenceNote` with a DERIVED id and borrowed timestamps
    /// (`EvidenceNote.legacyNote` - one rule with the SwiftData migration), so
    /// re-importing the same old file cannot duplicate the note. A v3 file's
    /// array passes through verbatim.
    private func upgradedEvidenceNotes() -> [EvidenceNote] {
        if let evidenceNotes {
            return evidenceNotes.map { $0.domainValue() }
        }
        guard let legacyEvidenceNote else { return [] }
        return [EvidenceNote.legacyNote(
            episodeID: id,
            text: legacyEvidenceNote,
            episodeUpdatedAt: updatedAt,
            episodeDeletedAt: deletedAt
        )]
    }

    /// The v1 upgrade: one rule with the SwiftData migration
    /// (`CancellationEpisode.legacyClosure`) - a verified-stopped record closes
    /// at its verification instant, every other state stays open.
    func upgradedFromV1() -> ExportedCancellationEpisode {
        guard endedAt == nil, outcome == nil else { return self }
        let closure = CancellationEpisode.legacyClosure(
            verificationStateRaw: verificationState,
            verifiedAt: verifiedAt,
            updatedAt: updatedAt
        )
        var upgraded = self
        upgraded.endedAt = closure.endedAt
        upgraded.outcome = closure.outcome?.rawValue
        return upgraded
    }
}
