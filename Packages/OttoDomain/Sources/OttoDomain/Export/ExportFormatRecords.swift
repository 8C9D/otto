import Foundation

// The remaining format v1 wire records - see ExportFormat.swift for the
// format's conventions and the reason these are their own types.

public struct ExportedPaymentMethod: Codable, Hashable, Sendable {
    public let id: UUID
    public var label: String
    public var last4: String
    public var issuer: String
    public var expiryMonth: Int
    public var expiryYear: Int
    public var isDefault: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(_ domain: PaymentMethod) {
        id = domain.id
        label = domain.label
        last4 = domain.last4
        issuer = domain.issuer
        expiryMonth = domain.expiryMonth
        expiryYear = domain.expiryYear
        isDefault = domain.isDefault
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }

    public func domainValue() throws -> PaymentMethod {
        PaymentMethod(
            id: id, label: label, last4: last4, issuer: issuer,
            expiryMonth: expiryMonth, expiryYear: expiryYear, isDefault: isDefault,
            createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}

public struct ExportedBillingEvent: Codable, Hashable, Sendable {
    public let id: UUID
    public let subscriptionID: UUID
    public var expectedDate: String
    public var expectedAmountCents: Int
    public var state: String
    public var userConfirmedAt: Date?
    public var acknowledgedAt: Date?
    public var actualAmountCents: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(_ domain: BillingEvent) {
        id = domain.id
        subscriptionID = domain.subscriptionID
        expectedDate = domain.expectedDate.description
        expectedAmountCents = domain.expectedAmountCents
        state = domain.state.rawValue
        userConfirmedAt = domain.userConfirmedAt
        acknowledgedAt = domain.acknowledgedAt
        actualAmountCents = domain.actualAmountCents
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }

    public func domainValue() throws -> BillingEvent {
        let entity = "billingEvent \(id)"
        return BillingEvent(
            id: id,
            subscriptionID: subscriptionID,
            expectedDate: try wireDay(expectedDate, entity: entity, field: "expectedDate"),
            expectedAmountCents: expectedAmountCents,
            state: try wireEnum(state, entity: entity, field: "state"),
            userConfirmedAt: userConfirmedAt,
            acknowledgedAt: acknowledgedAt,
            actualAmountCents: actualAmountCents,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

public struct ExportedCancellationRecord: Codable, Hashable, Sendable {
    public let id: UUID
    public let subscriptionID: UUID
    public var markedCancelledAt: Date
    public var nextChargeDateIfNotCancelled: String?
    public var expectedChargeAmountCents: Int?
    public var verificationState: String
    public var unansweredCheckCount: Int
    public var verifiedAt: Date?
    public var evidenceNote: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(_ domain: CancellationRecord) {
        id = domain.id
        subscriptionID = domain.subscriptionID
        markedCancelledAt = domain.markedCancelledAt
        nextChargeDateIfNotCancelled = domain.nextChargeDateIfNotCancelled?.description
        expectedChargeAmountCents = domain.expectedChargeAmountCents
        verificationState = domain.verificationState.rawValue
        unansweredCheckCount = domain.unansweredCheckCount
        verifiedAt = domain.verifiedAt
        evidenceNote = domain.evidenceNote
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }

    public func domainValue() throws -> CancellationRecord {
        let entity = "cancellationRecord \(id)"
        let state: CancellationRecord.VerificationState = try wireEnum(
            verificationState, entity: entity, field: "verificationState"
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
        return CancellationRecord(
            id: id,
            subscriptionID: subscriptionID,
            markedCancelledAt: markedCancelledAt,
            nextChargeDateIfNotCancelled: checkDate,
            expectedChargeAmountCents: expectedChargeAmountCents,
            verificationState: state,
            unansweredCheckCount: unansweredCheckCount,
            verifiedAt: verifiedAt,
            evidenceNote: evidenceNote,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

public struct ExportedPriceChange: Codable, Hashable, Sendable {
    public let id: UUID
    public let subscriptionID: UUID
    public var effectiveDate: String
    public var oldAmountCents: Int
    public var newAmountCents: Int
    public var source: String
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(_ domain: PriceChange) {
        id = domain.id
        subscriptionID = domain.subscriptionID
        effectiveDate = domain.effectiveDate.description
        oldAmountCents = domain.oldAmountCents
        newAmountCents = domain.newAmountCents
        source = domain.source.rawValue
        note = domain.note
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }

    public func domainValue() throws -> PriceChange {
        let entity = "priceChange \(id)"
        return PriceChange(
            id: id,
            subscriptionID: subscriptionID,
            effectiveDate: try wireDay(effectiveDate, entity: entity, field: "effectiveDate"),
            oldAmountCents: oldAmountCents,
            newAmountCents: newAmountCents,
            source: try wireEnum(source, entity: entity, field: "source"),
            note: note,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

// MARK: - Wire value parsing

/// A "YYYY-MM-DD" wire day, refused loudly when impossible.
func wireDay(_ string: String, entity: String, field: String) throws -> CalendarDay {
    let parts = string.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
          let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]),
          let parsed = CalendarDay(year: year, month: month, day: dayOfMonth)
    else {
        throw ExportFormatError.invalidValue(entity: entity, field: field, value: string)
    }
    return parsed
}

func wireDay(_ string: String?, entity: String, field: String) throws -> CalendarDay? {
    try string.map { try wireDay($0, entity: entity, field: field) }
}

func wireURL(_ string: String?, entity: String, field: String) throws -> URL? {
    guard let string else { return nil }
    guard let url = URL(string: string) else {
        throw ExportFormatError.invalidValue(entity: entity, field: field, value: string)
    }
    return url
}

func wireEnum<Value: RawRepresentable>(
    _ raw: String, entity: String, field: String
) throws -> Value where Value.RawValue == String {
    guard let value = Value(rawValue: raw) else {
        throw ExportFormatError.invalidValue(entity: entity, field: field, value: raw)
    }
    return value
}
