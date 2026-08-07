/// A free trial attached to a subscription (spec §5.2).
///
/// The user enters the two things they actually know - when the trial started and how
/// long it runs - and everything else is derived. The user is never asked to do date
/// arithmetic; that arithmetic failing is the reason this app exists.
public struct TrialTerm: Hashable, Sendable {
    /// The day the trial started, as entered.
    public let startDate: CalendarDay

    /// The trial's length in days, as entered - not the end date.
    public let lengthDays: Int

    /// Days of slack ahead of conversion by which cancellation should happen, because
    /// cancelling on the conversion day is already too late at some vendors, and a
    /// reminder that fires during a lecture needs room to be acted on later.
    public let bufferDays: Int

    /// What the subscription charges after conversion, in integer cents - often the
    /// whole point of tracking the trial.
    public let convertsToAmountCents: Int

    /// Creates a trial term, or nil when the length is under a day, the buffer is
    /// negative, or the converted price is negative.
    public init?(startDate: CalendarDay, lengthDays: Int, bufferDays: Int, convertsToAmountCents: Int) {
        guard lengthDays >= 1, bufferDays >= 0, convertsToAmountCents >= 0 else { return nil }
        self.startDate = startDate
        self.lengthDays = lengthDays
        self.bufferDays = bufferDays
        self.convertsToAmountCents = convertsToAmountCents
    }

    /// The day the trial converts to paid: start + length. Derived, never entered.
    public var conversionDate: CalendarDay {
        startDate.adding(days: lengthDays)
    }

    /// The last safe day to cancel: conversion - buffer, clamped so a buffer longer
    /// than the trial itself can never push the deadline before the trial started.
    public var cancelByDate: CalendarDay {
        max(startDate, conversionDate.adding(days: -bufferDays))
    }
}

// MARK: - Codable

extension TrialTerm: Codable {
    private enum CodingKeys: String, CodingKey {
        case startDate, lengthDays, bufferDays, convertsToAmountCents
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startDate = try container.decode(CalendarDay.self, forKey: .startDate)
        let lengthDays = try container.decode(Int.self, forKey: .lengthDays)
        let bufferDays = try container.decode(Int.self, forKey: .bufferDays)
        let convertsToAmountCents = try container.decode(Int.self, forKey: .convertsToAmountCents)
        guard let validated = TrialTerm(
            startDate: startDate,
            lengthDays: lengthDays,
            bufferDays: bufferDays,
            convertsToAmountCents: convertsToAmountCents
        ) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Impossible trial term: length \(lengthDays), buffer \(bufferDays)"
            ))
        }
        self = validated
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(lengthDays, forKey: .lengthDays)
        try container.encode(bufferDays, forKey: .bufferDays)
        try container.encode(convertsToAmountCents, forKey: .convertsToAmountCents)
    }
}
