import Foundation

/// One piece of dispute evidence (spec §5.4, made a list in v1.9): a call, then
/// an email, then a chargeback filing - a long cancellation fight produces many
/// artifacts, each with its own date. The same one-to-one-for-something-
/// recurring error §5.3a was written to eliminate, caught while a schema change
/// was still cheap. Carries the §5.0 quartet like every persisted record;
/// `createdAt` IS the note's own timestamp.
public struct EvidenceNote: Identifiable, Codable, Hashable, Sendable {
    /// Client-generated (spec §5.0).
    public let id: UUID
    /// Confirmation number, screenshot reference, rep's name.
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Soft-delete tombstone: a hard delete cannot be synced (spec §3.5).
    public var deletedAt: Date?

    public init(id: UUID, text: String, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// The note a pre-v1.9 single `evidenceNote` string becomes - ONE rule,
    /// shared by the SwiftData V2→V3 migration and the export format's pre-v3
    /// import so the two paths cannot drift. The id is DERIVED from the
    /// episode's id (the mask is "EvidNote" in ASCII, arbitrary but frozen), so
    /// re-importing or re-migrating the same data cannot duplicate the note;
    /// the timestamp borrows the episode's `updatedAt` - the last touch that
    /// could have written the note is the closest honest instant the old shape
    /// recorded, and neither caller may read a clock.
    public static func legacyNote(
        episodeID: UUID,
        text: String,
        episodeUpdatedAt: Date,
        episodeDeletedAt: Date? = nil
    ) -> EvidenceNote {
        var bytes = episodeID.uuid
        bytes.0 ^= 0x45; bytes.1 ^= 0x76; bytes.2 ^= 0x69; bytes.3 ^= 0x64
        bytes.4 ^= 0x4E; bytes.5 ^= 0x6F; bytes.6 ^= 0x74; bytes.7 ^= 0x65
        return EvidenceNote(
            id: UUID(uuid: bytes),
            text: text,
            createdAt: episodeUpdatedAt,
            updatedAt: episodeUpdatedAt,
            deletedAt: episodeDeletedAt
        )
    }
}

/// One cancellation in a subscription's life (spec §5.4, §5.3a) - the record
/// that keeps watching after a cancellation, and the fix for the failure nothing
/// else in the category addresses: a cancellation performed, charges continuing,
/// noticed weeks later by chance.
///
/// An episode, not a slot (spec §5.3a): a subscription can be cancelled,
/// resubscribed, and cancelled again, and each cancellation is its own row with
/// its own start, end, and outcome. The current episode is the one with no end
/// date. Nothing is ever cleared on exit - un-cancelling closes the open episode
/// with an `.abandoned` outcome rather than deleting it, because "I thought I'd
/// cancelled this and hadn't" is exactly the data this product is about.
///
/// A cancelled subscription is not archived until verification passes. Until
/// then the open episode stays in a watching state, and the app checks back on
/// the next date a charge would have landed. If a charge did arrive, the episode
/// holds everything a dispute needs: when it was cancelled, the confirmation
/// evidence, and what arrived anyway.
public struct CancellationEpisode: Identifiable, Hashable, Sendable {

    /// Where the watch IS NOW - live states only, meaningful while the episode
    /// is open (spec §5.4, v1.9). How an episode ENDED is `outcome`'s job:
    /// `.verifiedStopped` left this enum in v1.9 because reaching that result
    /// does not set a state, it closes the episode. A closed episode keeps the
    /// last live state as an artifact of when it closed; nothing reads it.
    public enum VerificationState: String, Codable, Hashable, Sendable, CaseIterable {
        /// Waiting for the first would-be charge date to pass.
        case pending
        /// A charge arrived after cancellation - surface the dispute summary.
        case stillCharging
        /// Three consecutive checks went unanswered (spec §5.4): notifications are
        /// not reaching this item and a fourth won't either, so it stops generating
        /// them and escalates to a persistent card in Today instead.
        case needsManualReview
        /// An indefinitely paused subscription was cancelled (spec §5.4, v1.5;
        /// built in Wave 7): there is no determinate would-be charge date and
        /// Otto does not guess one - a verification answered against a
        /// fabricated date is worse than no verification. The check is deferred,
        /// the subscription surfaces in Today's needs-review, and the watch
        /// starts the moment the user supplies the resume date.
        case awaitingResumeDate
    }

    /// How a closed episode ended (spec §5.3a). Paired with `endedAt` by
    /// construction: an episode is either open (neither set) or closed (both).
    public enum Outcome: String, Codable, Hashable, Sendable, CaseIterable {
        /// Verification passed - the money is confirmed stopped and the
        /// subscription archived alongside.
        case verifiedStopped
        /// The user un-cancelled: the cancellation was a mistake, or was never
        /// completed with the vendor. The episode is history, never deleted.
        case abandoned
        /// Closed by the pre-v2.1 convergence rule, which kept the newest
        /// rival open and closed the rest. §4a principle 2a (v2.1) merges
        /// rivals into the earliest and tombstones the losers instead, so
        /// nothing writes this anymore - but stored and exported episodes can
        /// carry it forever, so the case stays (spec §5.6's raw-string rule).
        case superseded
    }

    /// Client-generated (spec §5.0): a record with no id of its own cannot be
    /// addressed individually by sync.
    public let id: UUID

    public let subscriptionID: UUID

    /// When the user marked it cancelled - the episode's start, a UTC audit
    /// instant, not a billing day.
    public var markedCancelledAt: Date

    /// The stored lifecycle state the cancellation interrupted - what an
    /// un-cancel restores (spec §5.3a). Recorded rather than derived because
    /// the one ambiguity (a trial cancelled before conversion versus a
    /// confirmed conversion, both of which keep their trial term) is exactly
    /// the kind the dispute-summary rule forbids inferring heuristically.
    /// Nil only on episodes migrated from pre-8.5 records, which never stored
    /// it; the restore path derives the best honest answer for those.
    public var statusAtStart: SubscriptionStatus?

    /// The date a charge would land if the cancellation silently failed - the
    /// verification trigger (spec §5.4). Computed once at cancellation time from
    /// the immutable anchor and the cycle: `markedCancelledAt` is a UTC instant,
    /// so no calendar-day fallback is derivable from it later without a timezone,
    /// and a "next date after today" fallback would drift later every day the app
    /// goes unopened.
    ///
    /// Nil exactly while `verificationState` is `.awaitingResumeDate` - the
    /// indefinitely-paused cancellation, where no honest date exists and none is
    /// fabricated (spec §5.4, v1.5). Every other state carries a date; the
    /// pairing is a construction invariant.
    public var nextChargeDateIfNotCancelled: CalendarDay?

    /// What the watched charge would cost if it arrived (spec §5.4, added v1.5).
    /// Stored at cancellation for the same reason the date is: the amount is
    /// unrecoverable later - a hand-edited price overwrites the only other place
    /// it lives - and the dispute summary must contain no heuristics. Rolls
    /// forward with the date. Nil only on records written before v1.5; the §5.4
    /// roll-forward backfills those on its next pass.
    public var expectedChargeAmountCents: Int?

    public var verificationState: VerificationState

    /// How many consecutive checks have gone unanswered (spec §5.4, added v1.3).
    /// The roll-forward keeps watching until this reaches three; past that the
    /// episode escalates to `needsManualReview`. Wave 5's verification flow owns
    /// incrementing and resetting it.
    public var unansweredCheckCount: Int

    public var verifiedAt: Date?

    /// The dispute evidence, one note per artifact (spec §5.4, a list since
    /// v1.9). Tombstoned notes ride along as communicable history (spec §3.5);
    /// `liveEvidenceNotes` is the read every consumer wants.
    public var evidenceNotes: [EvidenceNote]

    /// When the episode closed. Nil while it is current (spec §5.3a: the
    /// current episode is the one with no end date).
    public var endedAt: Date?

    /// Why it closed. Paired with `endedAt` by construction.
    public var outcome: Outcome?

    /// Audit instants (spec §5.0), injected by callers - the domain never reads a clock.
    public var createdAt: Date
    public var updatedAt: Date

    /// Soft-delete tombstone: a hard delete cannot be synced (spec §3.5).
    public var deletedAt: Date?

    public init(
        id: UUID,
        subscriptionID: UUID,
        markedCancelledAt: Date,
        statusAtStart: SubscriptionStatus? = nil,
        nextChargeDateIfNotCancelled: CalendarDay?,
        expectedChargeAmountCents: Int? = nil,
        verificationState: VerificationState,
        unansweredCheckCount: Int = 0,
        verifiedAt: Date? = nil,
        evidenceNotes: [EvidenceNote] = [],
        endedAt: Date? = nil,
        outcome: Outcome? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        precondition(
            (nextChargeDateIfNotCancelled == nil) == (verificationState == .awaitingResumeDate),
            "A CancellationEpisode has no check date exactly while awaiting a resume date (spec §5.4)"
        )
        precondition(
            (endedAt == nil) == (outcome == nil),
            "A CancellationEpisode is open (no end, no outcome) or closed (both) - never half (spec §5.3a)"
        )
        self.id = id
        self.subscriptionID = subscriptionID
        self.markedCancelledAt = markedCancelledAt
        self.statusAtStart = statusAtStart
        self.nextChargeDateIfNotCancelled = nextChargeDateIfNotCancelled
        self.expectedChargeAmountCents = expectedChargeAmountCents
        self.verificationState = verificationState
        self.unansweredCheckCount = unansweredCheckCount
        self.verifiedAt = verifiedAt
        self.evidenceNotes = evidenceNotes
        self.endedAt = endedAt
        self.outcome = outcome
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Current, in §5.3a's sense. Deleted episodes are tombstoned history and
    /// never current; callers filter those where it matters.
    public var isOpen: Bool { endedAt == nil }

    /// The evidence a dispute (or the UI) actually shows: live notes, oldest
    /// first, ties broken by id so identical data always reads identically.
    public var liveEvidenceNotes: [EvidenceNote] {
        evidenceNotes
            .filter { $0.deletedAt == nil }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }
}

// MARK: - Upgrading pre-episode records (spec §5.3a)

extension CancellationEpisode {
    /// How a pre-episode (v1) cancellation record closes when it becomes an
    /// episode - ONE rule, shared by the SwiftData V1→V2 migration and the
    /// export format's v1 import so the two paths cannot drift: a
    /// verified-stopped record was finished (its subscription archived
    /// alongside), so it closes at its verification instant; every other state
    /// was still watching, waiting, or disputing, and stays open. Raw strings
    /// because both callers hold raw storage, not domain values.
    public static func legacyClosure(
        verificationStateRaw: String?,
        verifiedAt: Date?,
        updatedAt: Date?
    ) -> (endedAt: Date?, outcome: Outcome?) {
        // The literal is v1's wire value: the STATE case was removed in v1.9
        // (the §5.4 folding - reaching the result closes the episode instead),
        // but old files and stores carry the string forever.
        guard verificationStateRaw == "verifiedStopped",
              let endedAt = verifiedAt ?? updatedAt
        else { return (nil, nil) }
        return (endedAt, .verifiedStopped)
    }
}

extension PauseEpisode {
    /// Whether a pre-episode (v1) record's pause state becomes an open episode -
    /// the same single-rule arrangement as `CancellationEpisode.legacyClosure`.
    /// A `.paused` record always does (spec §5.3a's invariant requires the
    /// episode even when v1 recorded neither date); a cancellation or archive
    /// that happened mid-pause kept its fields and stays an open episode (the
    /// pause never ended - billing never resumed). Pause fields beside a stored
    /// `.active` or `.trial` cannot be produced by any flow and are dropped as
    /// noise rather than migrated into an invariant violation.
    public static func legacyEpisodeExists(
        statusRaw: String?,
        hasStart: Bool,
        hasScheduledResume: Bool
    ) -> Bool {
        let paused = SubscriptionStatus.paused.rawValue
        let eligible: Set<String> = [
            paused,
            SubscriptionStatus.cancellationPending.rawValue,
            SubscriptionStatus.cancelled.rawValue,
            SubscriptionStatus.archived.rawValue
        ]
        guard let statusRaw, eligible.contains(statusRaw) else { return false }
        return statusRaw == paused || hasStart || hasScheduledResume
    }
}

// MARK: - Codable

extension CancellationEpisode: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, subscriptionID, markedCancelledAt, statusAtStart, nextChargeDateIfNotCancelled
        case expectedChargeAmountCents, verificationState, unansweredCheckCount
        case verifiedAt, evidenceNotes, endedAt, outcome, createdAt, updatedAt, deletedAt
    }

    // Hand-written so decoding routes through both construction invariants
    // instead of assigning stored properties directly, which is what a
    // synthesized decoder does.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(VerificationState.self, forKey: .verificationState)
        let checkDate = try container.decodeIfPresent(CalendarDay.self, forKey: .nextChargeDateIfNotCancelled)
        guard (checkDate == nil) == (state == .awaitingResumeDate) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "A CancellationEpisode has no check date exactly while awaiting a resume date (spec §5.4)"
            ))
        }
        let endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        let outcome = try container.decodeIfPresent(Outcome.self, forKey: .outcome)
        guard (endedAt == nil) == (outcome == nil) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "A CancellationEpisode is open (no end, no outcome) or closed (both) - never half (spec §5.3a)"
            ))
        }
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            subscriptionID: try container.decode(UUID.self, forKey: .subscriptionID),
            markedCancelledAt: try container.decode(Date.self, forKey: .markedCancelledAt),
            statusAtStart: try container.decodeIfPresent(SubscriptionStatus.self, forKey: .statusAtStart),
            nextChargeDateIfNotCancelled: checkDate,
            expectedChargeAmountCents: try container.decodeIfPresent(Int.self, forKey: .expectedChargeAmountCents),
            verificationState: state,
            unansweredCheckCount: try container.decode(Int.self, forKey: .unansweredCheckCount),
            verifiedAt: try container.decodeIfPresent(Date.self, forKey: .verifiedAt),
            evidenceNotes: try container.decodeIfPresent([EvidenceNote].self, forKey: .evidenceNotes) ?? [],
            endedAt: endedAt,
            outcome: outcome,
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(subscriptionID, forKey: .subscriptionID)
        try container.encode(markedCancelledAt, forKey: .markedCancelledAt)
        try container.encodeIfPresent(statusAtStart, forKey: .statusAtStart)
        try container.encodeIfPresent(nextChargeDateIfNotCancelled, forKey: .nextChargeDateIfNotCancelled)
        try container.encodeIfPresent(expectedChargeAmountCents, forKey: .expectedChargeAmountCents)
        try container.encode(verificationState, forKey: .verificationState)
        try container.encode(unansweredCheckCount, forKey: .unansweredCheckCount)
        try container.encodeIfPresent(verifiedAt, forKey: .verifiedAt)
        try container.encode(evidenceNotes, forKey: .evidenceNotes)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encodeIfPresent(outcome, forKey: .outcome)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}
