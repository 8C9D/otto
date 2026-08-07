import Foundation

/// The record that keeps watching after a cancellation (spec §5.4) - the fix for the
/// failure nothing else in the category addresses: a cancellation performed, charges
/// continuing, noticed weeks later by chance.
///
/// A cancelled subscription is not archived until verification passes. Until then it
/// stays in a watching state, and the app checks back on the next date a charge would
/// have landed. If a charge did arrive, this record holds everything a dispute needs:
/// when it was cancelled, the confirmation evidence, and what arrived anyway.
public struct CancellationRecord: Identifiable, Hashable, Codable, Sendable {

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
    }

    /// Client-generated (spec §5.0): a record with no id of its own cannot be
    /// addressed individually by sync.
    public let id: UUID

    public let subscriptionID: UUID

    /// When the user marked it cancelled - a UTC audit instant, not a billing day.
    public var markedCancelledAt: Date

    /// The date a charge would land if the cancellation silently failed - the
    /// verification trigger (spec §5.4). Required, and computed once at cancellation
    /// time from the immutable anchor and the cycle: `markedCancelledAt` is a UTC
    /// instant, so no calendar-day fallback is derivable from it later without a
    /// timezone, and a "next date after today" fallback would drift later every day
    /// the app goes unopened.
    public var nextChargeDateIfNotCancelled: CalendarDay

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
        nextChargeDateIfNotCancelled: CalendarDay,
        verificationState: VerificationState,
        unansweredCheckCount: Int = 0,
        verifiedAt: Date? = nil,
        evidenceNote: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.markedCancelledAt = markedCancelledAt
        self.nextChargeDateIfNotCancelled = nextChargeDateIfNotCancelled
        self.verificationState = verificationState
        self.unansweredCheckCount = unansweredCheckCount
        self.verifiedAt = verifiedAt
        self.evidenceNote = evidenceNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
