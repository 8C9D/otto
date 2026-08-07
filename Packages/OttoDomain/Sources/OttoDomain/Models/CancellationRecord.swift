import Foundation

/// The record that keeps watching after a cancellation (spec §5.4) - the fix for the
/// failure nothing else in the category addresses: a cancellation performed, charges
/// continuing, noticed weeks later by chance.
///
/// A cancelled subscription is not archived until verification passes. Until then it
/// stays in a watching state, and the app checks back on the next date a charge would
/// have landed. If a charge did arrive, this record holds everything a dispute needs:
/// when it was cancelled, the confirmation evidence, and what arrived anyway.
public struct CancellationRecord: Identifiable, Hashable, Sendable {

    public enum VerificationState: String, Codable, Hashable, Sendable, CaseIterable {
        /// Waiting for the first would-be charge date to pass.
        case pending
        /// The user confirmed the money stopped; the subscription can be archived.
        case verifiedStopped
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

    /// Client-generated (spec §5.0): a record with no id of its own cannot be
    /// addressed individually by sync.
    public let id: UUID

    public let subscriptionID: UUID

    /// When the user marked it cancelled - a UTC audit instant, not a billing day.
    public var markedCancelledAt: Date

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
    /// record escalates to `needsManualReview`. Wave 5's verification flow owns
    /// incrementing and resetting it.
    public var unansweredCheckCount: Int

    public var verifiedAt: Date?

    /// Confirmation number, screenshot reference, rep's name - the dispute evidence.
    public var evidenceNote: String?

    /// Audit instants (spec §5.0), injected by callers - the domain never reads a clock.
    public var createdAt: Date
    public var updatedAt: Date

    /// Soft-delete tombstone: a hard delete cannot be synced (spec §3.5).
    public var deletedAt: Date?

    public init(
        id: UUID,
        subscriptionID: UUID,
        markedCancelledAt: Date,
        nextChargeDateIfNotCancelled: CalendarDay?,
        expectedChargeAmountCents: Int? = nil,
        verificationState: VerificationState,
        unansweredCheckCount: Int = 0,
        verifiedAt: Date? = nil,
        evidenceNote: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        precondition(
            (nextChargeDateIfNotCancelled == nil) == (verificationState == .awaitingResumeDate),
            "A CancellationRecord has no check date exactly while awaiting a resume date (spec §5.4)"
        )
        self.id = id
        self.subscriptionID = subscriptionID
        self.markedCancelledAt = markedCancelledAt
        self.nextChargeDateIfNotCancelled = nextChargeDateIfNotCancelled
        self.expectedChargeAmountCents = expectedChargeAmountCents
        self.verificationState = verificationState
        self.unansweredCheckCount = unansweredCheckCount
        self.verifiedAt = verifiedAt
        self.evidenceNote = evidenceNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// MARK: - Codable

extension CancellationRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, subscriptionID, markedCancelledAt, nextChargeDateIfNotCancelled
        case expectedChargeAmountCents, verificationState, unansweredCheckCount
        case verifiedAt, evidenceNote, createdAt, updatedAt, deletedAt
    }

    // Hand-written so decoding routes through the date-state invariant instead of
    // assigning stored properties directly, which is what a synthesized decoder does.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(VerificationState.self, forKey: .verificationState)
        let checkDate = try container.decodeIfPresent(CalendarDay.self, forKey: .nextChargeDateIfNotCancelled)
        guard (checkDate == nil) == (state == .awaitingResumeDate) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "A CancellationRecord has no check date exactly while awaiting a resume date (spec §5.4)"
            ))
        }
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            subscriptionID: try container.decode(UUID.self, forKey: .subscriptionID),
            markedCancelledAt: try container.decode(Date.self, forKey: .markedCancelledAt),
            nextChargeDateIfNotCancelled: checkDate,
            expectedChargeAmountCents: try container.decodeIfPresent(Int.self, forKey: .expectedChargeAmountCents),
            verificationState: state,
            unansweredCheckCount: try container.decode(Int.self, forKey: .unansweredCheckCount),
            verifiedAt: try container.decodeIfPresent(Date.self, forKey: .verifiedAt),
            evidenceNote: try container.decodeIfPresent(String.self, forKey: .evidenceNote),
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
        try container.encodeIfPresent(nextChargeDateIfNotCancelled, forKey: .nextChargeDateIfNotCancelled)
        try container.encodeIfPresent(expectedChargeAmountCents, forKey: .expectedChargeAmountCents)
        try container.encode(verificationState, forKey: .verificationState)
        try container.encode(unansweredCheckCount, forKey: .unansweredCheckCount)
        try container.encodeIfPresent(verifiedAt, forKey: .verifiedAt)
        try container.encodeIfPresent(evidenceNote, forKey: .evidenceNote)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}
