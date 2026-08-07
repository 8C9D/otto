import Foundation

/// The record that keeps watching after a cancellation (spec §5.4) - the fix for the
/// failure nothing else in the category addresses: a cancellation performed, charges
/// continuing, noticed weeks later by chance.
///
/// A cancelled subscription is not archived until verification passes. Until then it
/// stays in a watching state, and the app checks back on the next date a charge would
/// have landed. If a charge did arrive, this record holds everything a dispute needs:
/// when it was cancelled, the confirmation evidence, and what arrived anyway.
public struct CancellationRecord: Hashable, Codable, Sendable {

    public enum VerificationState: String, Codable, Hashable, Sendable, CaseIterable {
        /// Waiting for the first would-be charge date to pass.
        case pending
        /// The user confirmed the money stopped; the subscription can be archived.
        case verifiedStopped
        /// A charge arrived after cancellation - surface the dispute summary.
        case stillCharging
    }

    public let subscriptionID: UUID

    /// When the user marked it cancelled - a UTC audit instant, not a billing day.
    public var markedCancelledAt: Date

    /// The last charge that was legitimately due, when the user knows it.
    public var expectedFinalChargeDate: CalendarDay?

    public var verificationState: VerificationState
    public var verifiedAt: Date?

    /// Confirmation number, screenshot reference, rep's name - the dispute evidence.
    public var evidenceNote: String?

    public init(
        subscriptionID: UUID,
        markedCancelledAt: Date,
        expectedFinalChargeDate: CalendarDay? = nil,
        verificationState: VerificationState,
        verifiedAt: Date? = nil,
        evidenceNote: String? = nil
    ) {
        self.subscriptionID = subscriptionID
        self.markedCancelledAt = markedCancelledAt
        self.expectedFinalChargeDate = expectedFinalChargeDate
        self.verificationState = verificationState
        self.verifiedAt = verifiedAt
        self.evidenceNote = evidenceNote
    }
}
