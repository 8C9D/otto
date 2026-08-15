import Foundation
import OttoDomain

/// The store layer's single source of "now". Nothing below this layer reads a
/// clock - the domain takes days and instants as parameters, and the persistence
/// store takes every instant as an argument - so this is the one boundary where
/// the current moment enters, injected so tests can pin it.
public struct DateProvider: Sendable {
    /// The current UTC instant, for audit fields.
    public var now: @Sendable () -> Date

    /// The current calendar day in the device's timezone, for billing arithmetic.
    public var today: @Sendable () -> CalendarDay

    /// The device's current timezone - what turns a reminder's calendar day into
    /// a fire instant (spec §4.1). A function, not a value, because it changes
    /// under the app and every read must see the current one.
    public var timeZone: @Sendable () -> TimeZone

    public init(
        now: @escaping @Sendable () -> Date,
        today: @escaping @Sendable () -> CalendarDay,
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.now = now
        self.today = today
        self.timeZone = timeZone
    }

    /// Reads the system clock and the device's current timezone. The calendar is
    /// deliberately NOT the device's: `CalendarDay` is Gregorian by construction,
    /// so the day is read through `CalendarDay.conversionCalendar` and a device
    /// set to another calendar cannot inject an era-numbered year into billing
    /// arithmetic.
    public static let live = DateProvider(
        now: { Date() },
        today: {
            let components = CalendarDay.conversionCalendar
                .dateComponents([.year, .month, .day], from: Date())
            guard let day = CalendarDay(dateComponents: components) else {
                // The system calendar cannot produce an impossible date; if it ever
                // does, stopping beats running billing arithmetic on garbage.
                preconditionFailure("The current date is unrepresentable: \(components)")
            }
            return day
        },
        timeZone: { .current }
    )

    /// A provider pinned to one instant and one day, for tests and previews.
    public static func fixed(
        today: CalendarDay,
        now: Date = Date(timeIntervalSince1970: 0),
        timeZone: TimeZone = TimeZone(identifier: "America/Toronto") ?? .current
    ) -> DateProvider {
        DateProvider(now: { now }, today: { today }, timeZone: { timeZone })
    }
}
