import Foundation

/// A calendar date - year, month, day - with no time of day and no timezone.
///
/// Billing dates must be calendar days rather than `Date` instants (spec §4.1): an
/// instant stored for "renews Feb 28" resolves to Feb 27 or Mar 1 when the device's
/// timezone changes, and the reminder silently fires on the wrong day. All billing
/// arithmetic happens on `CalendarDay`; the one and only conversion to a real instant
/// is `fireDate(hour:minute:in:)`, at notification-scheduling time.
public struct CalendarDay: Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a calendar day, or nil for an impossible date such as February 30
    /// or a year outside 1-9999.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year),
              (1...12).contains(month),
              day >= 1,
              day <= CalendarDay.daysIn(month: month, year: year)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Trusted path for dates the caller has proven valid by construction, such as a
    /// day already clamped to its month. Asserts in debug builds instead of validating.
    init(validYear: Int, validMonth: Int, validDay: Int) {
        assert(
            CalendarDay(year: validYear, month: validMonth, day: validDay) != nil,
            "invalid trusted date \(validYear)-\(validMonth)-\(validDay)"
        )
        self.year = validYear
        self.month = validMonth
        self.day = validDay
    }
}

// MARK: - Gregorian calendar facts

extension CalendarDay {
    public static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    /// The number of days in a month, or 0 for month numbers outside 1-12 so that
    /// any range built on the result is empty rather than wrong.
    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        case 2: isLeapYear(year) ? 29 : 28
        default: 0
        }
    }
}

// MARK: - Day arithmetic

extension CalendarDay {
    /// This day's position in a continuous count of days, with 0001-01-01 as day 1
    /// (a proleptic Gregorian day number). All day arithmetic runs through this one
    /// integer, which is what makes it immune to timezones and DST by construction.
    var ordinalDay: Int {
        let priorYears = year - 1
        var days = priorYears * 365 + priorYears / 4 - priorYears / 100 + priorYears / 400
        for priorMonth in 1..<month {
            days += CalendarDay.daysIn(month: priorMonth, year: year)
        }
        return days + day
    }

    /// The inverse of `ordinalDay`. Expects a value `ordinalDay` produced, i.e. >= 1.
    init(ordinalDay: Int) {
        precondition(ordinalDay >= 1, "ordinal day \(ordinalDay) is before 0001-01-01")

        func daysBefore(year: Int) -> Int {
            let priorYears = year - 1
            return priorYears * 365 + priorYears / 4 - priorYears / 100 + priorYears / 400
        }

        // No year has more than 366 days, so this estimate can only be low; walk
        // forward the few years it is off by.
        var year = max(1, ordinalDay / 366)
        while daysBefore(year: year + 1) < ordinalDay {
            year += 1
        }

        var remainingDays = ordinalDay - daysBefore(year: year)
        var month = 1
        while remainingDays > CalendarDay.daysIn(month: month, year: year) {
            remainingDays -= CalendarDay.daysIn(month: month, year: year)
            month += 1
        }

        self.year = year
        self.month = month
        self.day = remainingDays
    }

    /// The day `days` after this one, or before it for negative values.
    public func adding(days: Int) -> CalendarDay {
        CalendarDay(ordinalDay: ordinalDay + days)
    }

    /// The number of whole days from this day to `other`; negative when `other` is earlier.
    public func days(until other: CalendarDay) -> Int {
        other.ordinalDay - ordinalDay
    }
}

// MARK: - Comparable

extension CalendarDay: Comparable {
    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

// MARK: - Codable

extension CalendarDay: Codable {
    private enum CodingKeys: String, CodingKey {
        case year, month, day
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)
        guard let validated = CalendarDay(year: year, month: month, day: day) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Impossible calendar date \(year)-\(month)-\(day)"
            ))
        }
        self = validated
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(day, forKey: .day)
    }
}

// MARK: - Foundation boundary

extension CalendarDay {
    /// The day as `DateComponents`, carrying only year, month, and day.
    public var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// Creates a day from components, or nil when year, month, or day is missing
    /// or the combination is impossible.
    public init?(dateComponents: DateComponents) {
        guard let year = dateComponents.year,
              let month = dateComponents.month,
              let day = dateComponents.day
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The instant a reminder for this day should fire, at the given wall-clock time
    /// in the given timezone.
    ///
    /// This is the only place the domain touches timezones, and it is a pure function
    /// of its inputs: the calendar is always Gregorian and the timezone is a parameter,
    /// so nothing reads device state. A timezone change means recomputing fire dates -
    /// the calendar day itself never moves (spec §4.1). Returns nil only when Foundation
    /// cannot resolve the combination at all.
    public func fireDate(hour: Int, minute: Int, in timeZone: TimeZone) -> Date? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return gregorian.date(from: components)
    }
}

// MARK: - Description

extension CalendarDay: CustomStringConvertible {
    /// ISO-8601 style, e.g. "2026-08-06".
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
