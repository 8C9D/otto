/// How often a subscription bills: a count of a unit, e.g. every 3 months.
///
/// One shape covers every cadence (spec §4.3): quarterly is `(.month, 3)`, biweekly is
/// `(.week, 2)`. The UI gives cadences friendly names; the domain deliberately does
/// not, because a separate `quarterly` case would need its own month-end clamping path
/// instead of inheriting it from `month`.
public struct BillingCycle: Hashable, Sendable {
    public enum Unit: String, Codable, Hashable, Sendable, CaseIterable {
        case day
        case week
        case month
        case year
    }

    public let unit: Unit

    /// How many units make one cycle. Always at least 1.
    public let interval: Int

    /// Creates a cycle, or nil when `interval` is less than 1.
    public init?(unit: Unit, interval: Int) {
        guard interval >= 1 else { return nil }
        self.unit = unit
        self.interval = interval
    }

    /// Trusted path for the named cadences below, which are valid by inspection.
    private init(validUnit: Unit, validInterval: Int) {
        self.unit = validUnit
        self.interval = validInterval
    }
}

// MARK: - Named cadences

extension BillingCycle {
    public static let weekly = BillingCycle(validUnit: .week, validInterval: 1)
    public static let biweekly = BillingCycle(validUnit: .week, validInterval: 2)
    public static let monthly = BillingCycle(validUnit: .month, validInterval: 1)
    public static let quarterly = BillingCycle(validUnit: .month, validInterval: 3)
    public static let semiannual = BillingCycle(validUnit: .month, validInterval: 6)
    public static let annual = BillingCycle(validUnit: .year, validInterval: 1)
}

// MARK: - Codable

extension BillingCycle: Codable {
    private enum CodingKeys: String, CodingKey {
        case unit, interval
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let unit = try container.decode(Unit.self, forKey: .unit)
        let interval = try container.decode(Int.self, forKey: .interval)
        guard let validated = BillingCycle(unit: unit, interval: interval) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Billing cycle interval must be at least 1, got \(interval)"
            ))
        }
        self = validated
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(unit, forKey: .unit)
        try container.encode(interval, forKey: .interval)
    }
}

// MARK: - Normalisation support

extension BillingCycle {
    /// The average length of one cycle in days: a month averages 30.4375 days
    /// (365.25 / 12) and a year 365.25. For price normalisation ONLY - billing dates
    /// come from the date engine's calendar rules, never from averages.
    public var averageLengthInDays: Double {
        switch unit {
        case .day: Double(interval)
        case .week: Double(interval) * 7
        case .month: Double(interval) * 30.4375
        case .year: Double(interval) * 365.25
        }
    }
}
