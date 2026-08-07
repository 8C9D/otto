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

    public init(now: @escaping @Sendable () -> Date, today: @escaping @Sendable () -> CalendarDay) {
        self.now = now
        self.today = today
    }

    /// Reads the system clock and the device's current calendar.
    public static let live = DateProvider(
        now: { Date() },
        today: {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            guard let day = CalendarDay(dateComponents: components) else {
                // The system calendar cannot produce an impossible date; if it ever
                // does, stopping beats running billing arithmetic on garbage.
                preconditionFailure("The current date is unrepresentable: \(components)")
            }
            return day
        }
    )

    /// A provider pinned to one instant and one day, for tests and previews.
    public static func fixed(today: CalendarDay, now: Date = Date(timeIntervalSince1970: 0)) -> DateProvider {
        DateProvider(now: { now }, today: { today })
    }
}
