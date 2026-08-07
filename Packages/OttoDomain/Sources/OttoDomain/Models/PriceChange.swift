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

    public init(
        id: UUID,
        subscriptionID: UUID,
        effectiveDate: CalendarDay,
        oldAmountCents: Int,
        newAmountCents: Int,
        recordedAt: Date,
        source: Source,
        note: String? = nil
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.effectiveDate = effectiveDate
        self.oldAmountCents = oldAmountCents
        self.newAmountCents = newAmountCents
        self.recordedAt = recordedAt
        self.source = source
        self.note = note
    }
}
