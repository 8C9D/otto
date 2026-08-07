import Foundation
import OttoDomain

// The scalar storage shapes (decision record, Wave 2). Both exist so stored values
// stay queryable and legible - in a predicate, a debugger, or the CloudKit
// dashboard - instead of opaque Codable blobs.

extension CalendarDay {
    /// The day as a single sortable Int in yyyymmdd form, e.g. 2026-08-06 → 20260806.
    /// Timezone-free by construction, like the type itself.
    var yyyymmdd: Int {
        year * 10_000 + month * 100 + day
    }

    /// Rebuilds a day from its yyyymmdd form, or nil for an impossible date -
    /// validation is `CalendarDay`'s own, so storage cannot bypass the invariants.
    init?(yyyymmdd value: Int) {
        self.init(year: value / 10_000, month: value / 100 % 100, day: value % 100)
    }
}

extension CalendarDay {
    /// Maps a required stored yyyymmdd field, throwing on nil or an impossible date.
    static func stored(_ value: Int?, entity: String, field: String) throws -> CalendarDay {
        let value = try require(value, entity: entity, field: field)
        guard let day = CalendarDay(yyyymmdd: value) else {
            throw MappingError.invalidValue(entity: entity, field: field, value: String(value))
        }
        return day
    }

    /// Maps an optional stored yyyymmdd field: nil stays nil, an impossible date throws.
    static func storedOptional(_ value: Int?, entity: String, field: String) throws -> CalendarDay? {
        guard let value else { return nil }
        return try stored(value, entity: entity, field: field)
    }
}

extension BillingCycle {
    /// Rebuilds a cycle from its two scalar columns, throwing on a missing column,
    /// an unknown unit, or an interval below 1.
    static func stored(unitRaw: String?, interval: Int?, entity: String) throws -> BillingCycle {
        let unit: Unit = try decodeRaw(unitRaw, entity: entity, field: "cycleUnit")
        let interval = try require(interval, entity: entity, field: "cycleInterval")
        guard let cycle = BillingCycle(unit: unit, interval: interval) else {
            throw MappingError.invalidValue(entity: entity, field: "cycleInterval", value: String(interval))
        }
        return cycle
    }
}

extension URL {
    /// Maps an optional stored URL string: nil stays nil, an unparseable string throws.
    static func storedOptional(_ value: String?, entity: String, field: String) throws -> URL? {
        guard let value else { return nil }
        guard let url = URL(string: value) else {
            throw MappingError.invalidValue(entity: entity, field: field, value: value)
        }
        return url
    }
}
