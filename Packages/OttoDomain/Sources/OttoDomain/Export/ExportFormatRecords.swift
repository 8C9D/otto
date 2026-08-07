import Foundation

// The remaining wire records - see ExportFormat.swift for the format's
// conventions and the reason these are their own types.

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

// MARK: - Nested wire records (subscription children)

/// The id a v1 subscription's synthesized pause episode gets - DERIVED from the
/// subscription's id rather than minted, so importing the same v1 file twice
/// produces the same episode instead of a duplicate, and identical files
/// upgrade to identical values. The mask is arbitrary but FROZEN ("PauseEpi" in
/// ASCII); a derived id can never equal the subscription's own.
func legacyPauseEpisodeID(for subscriptionID: UUID) -> UUID {
    var bytes = subscriptionID.uuid
    bytes.0 ^= 0x50; bytes.1 ^= 0x61; bytes.2 ^= 0x75; bytes.3 ^= 0x73
    bytes.4 ^= 0x65; bytes.5 ^= 0x45; bytes.6 ^= 0x70; bytes.7 ^= 0x69
    return UUID(uuid: bytes)
}

public struct ExportedPauseEpisode: Codable, Hashable, Sendable {
    public let id: UUID
    public var startedOn: String?
    public var scheduledResumeOn: String?
    public var endedOn: String?
    public var outcome: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(_ domain: PauseEpisode) {
        id = domain.id
        startedOn = domain.startedOn?.description
        scheduledResumeOn = domain.scheduledResumeOn?.description
        endedOn = domain.endedOn?.description
        outcome = domain.outcome?.rawValue
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }

    init(
        id: UUID, startedOn: String?, scheduledResumeOn: String?, endedOn: String?,
        outcome: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?
    ) {
        self.id = id
        self.startedOn = startedOn
        self.scheduledResumeOn = scheduledResumeOn
        self.endedOn = endedOn
        self.outcome = outcome
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public func domainValue() throws -> PauseEpisode {
        let entity = "pauseEpisode \(id)"
        let endedOn = try wireDay(self.endedOn, entity: entity, field: "endedOn")
        let outcome: PauseEpisode.Outcome? = try self.outcome.map {
            try wireEnum($0, entity: entity, field: "outcome")
        }
        // The §5.3a pairing, thrown instead of the domain's precondition.
        guard (endedOn == nil) == (outcome == nil) else {
            throw ExportFormatError.invalidValue(
                entity: entity,
                field: "endedOn/outcome",
                value: "\(self.endedOn ?? "absent")/\(self.outcome ?? "absent")"
            )
        }
        return PauseEpisode(
            id: id,
            startedOn: try wireDay(startedOn, entity: entity, field: "startedOn"),
            scheduledResumeOn: try wireDay(scheduledResumeOn, entity: entity, field: "scheduledResumeOn"),
            endedOn: endedOn,
            outcome: outcome,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

public struct ExportedTrialTerm: Codable, Hashable, Sendable {
    public let id: UUID
    public var startDate: String
    public var lengthDays: Int
    public var bufferDays: Int
    public var convertsToAmountCents: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(_ domain: TrialTerm) {
        id = domain.id
        startDate = domain.startDate.description
        lengthDays = domain.lengthDays
        bufferDays = domain.bufferDays
        convertsToAmountCents = domain.convertsToAmountCents
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }

    public func domainValue() throws -> TrialTerm {
        let entity = "trial \(id)"
        guard let term = TrialTerm(
            id: id,
            startDate: try wireDay(startDate, entity: entity, field: "startDate"),
            lengthDays: lengthDays,
            bufferDays: bufferDays,
            convertsToAmountCents: convertsToAmountCents,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        ) else {
            throw ExportFormatError.invalidValue(
                entity: entity,
                field: "lengthDays/bufferDays/convertsToAmountCents",
                value: "\(lengthDays)/\(bufferDays)/\(convertsToAmountCents)"
            )
        }
        return term
    }
}
