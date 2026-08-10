import SwiftUI
import OttoDomain
import OttoStores

extension Binding where Value == CalendarDay {
    /// Bridges a `CalendarDay` to `DatePicker`'s `Date` at the display boundary
    /// only - the converted instant never feeds billing arithmetic (spec §4.1).
    /// Both directions resolve in `ottoDayCalendar`, never the device calendar:
    /// the picker RENDERS in the user's calendar either way, but the numbers
    /// that come back out and get stored have to mean what the domain means by
    /// them. Reading them back through a Buddhist device calendar stores year
    /// 2569 as a Gregorian year, and every billing date computed from it is 543
    /// years out - silently, because it is a perfectly valid `CalendarDay`.
    func asDate() -> Binding<Date> {
        Binding<Date>(
            get: {
                // A valid CalendarDay always resolves in the Gregorian calendar;
                // the epoch fallback exists so a degenerate calendar cannot crash
                // a picker.
                wrappedValue.displayDate() ?? Date(timeIntervalSince1970: 0)
            },
            set: { newDate in
                var calendar = ottoDayCalendar
                calendar.timeZone = .current
                let components = calendar.dateComponents([.year, .month, .day], from: newDate)
                if let newDay = CalendarDay(dateComponents: components) {
                    wrappedValue = newDay
                }
            }
        )
    }
}
