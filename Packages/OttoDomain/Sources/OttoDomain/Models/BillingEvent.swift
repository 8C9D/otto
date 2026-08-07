import Foundation

/// One expected charge - a row in the billing ledger (spec §5.3), the backbone of
/// both verification and reporting. Without it the app has no memory.
public struct BillingEvent: Identifiable, Hashable, Codable, Sendable {

    public enum State: String, Codable, Hashable, Sendable, CaseIterable {
        /// Expected but not yet confirmed either way.
        case upcoming
        /// The user confirmed the charge arrived.
        case confirmedCharged
        /// The user confirmed no charge arrived.
        case confirmedNotCharged
        /// A charge arrived that no schedule predicted.
        case unexpectedCharge
        /// Deliberately skipped, e.g. a vendor-granted free month.
        case skipped
    }

    public let id: UUID
    public let subscriptionID: UUID
    public var expectedDate: CalendarDay
    public var expectedAmountCents: Int
    public var state: State
    public var userConfirmedAt: Date?

    /// What was actually charged, when it differed from the expectation; a difference
    /// triggers a price-change prompt (spec §5.3).
    public var actualAmountCents: Int?

    /// Audit instants (spec §5.0), injected by callers - the domain never reads a clock.
    public var createdAt: Date
    public var updatedAt: Date

    /// Soft-delete tombstone: a hard delete cannot be synced (spec §3.5).
    public var deletedAt: Date?

    public init(
        id: UUID,
        subscriptionID: UUID,
        expectedDate: CalendarDay,
        expectedAmountCents: Int,
        state: State,
        userConfirmedAt: Date? = nil,
        actualAmountCents: Int? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.expectedDate = expectedDate
        self.expectedAmountCents = expectedAmountCents
        self.state = state
        self.userConfirmedAt = userConfirmedAt
        self.actualAmountCents = actualAmountCents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
