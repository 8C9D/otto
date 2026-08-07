import Foundation

/// One price change (spec §5.5). Editing a price never overwrites history - it
/// appends one of these, which is what lets Insights show "Netflix has gone up 34%
/// in three years".
public struct PriceChange: Identifiable, Hashable, Codable, Sendable {

    public enum Source: String, Codable, Hashable, Sendable, CaseIterable {
        /// The user edited the price by hand.
        case userEdit
        /// A confirmed charge differed from the expected amount.
        case chargeMismatch
    }

    public let id: UUID
    public let subscriptionID: UUID
    public var effectiveDate: CalendarDay
    public var oldAmountCents: Int
    public var newAmountCents: Int
    public var recordedAt: Date
    public var source: Source
    public var note: String?

    /// Audit instants (spec §5.0), injected by callers - the domain never reads a
    /// clock. `recordedAt` stays separate: it is the domain fact "when the change
    /// was noticed", while `createdAt` is the sync bookkeeping fact "when the row
    /// was written", and an import can legitimately split the two.
    public var createdAt: Date
    public var updatedAt: Date

    /// Soft-delete tombstone: a hard delete cannot be synced (spec §3.5).
    public var deletedAt: Date?

    public init(
        id: UUID,
        subscriptionID: UUID,
        effectiveDate: CalendarDay,
        oldAmountCents: Int,
        newAmountCents: Int,
        recordedAt: Date,
        source: Source,
        note: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.effectiveDate = effectiveDate
        self.oldAmountCents = oldAmountCents
        self.newAmountCents = newAmountCents
        self.recordedAt = recordedAt
        self.source = source
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
