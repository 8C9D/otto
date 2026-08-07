import SwiftUI
import OttoDomain

extension Binding where Value == CalendarDay {
    /// Bridges a `CalendarDay` to `DatePicker`'s `Date` at the display boundary
    /// only - the converted instant never feeds billing arithmetic (spec §4.1).
    func asDate(calendar: Calendar = .current) -> Binding<Date> {
        Binding<Date>(
            get: {
                // A valid CalendarDay always resolves in the Gregorian calendar;
                // the epoch fallback exists so a degenerate calendar cannot crash
                // a picker.
                wrappedValue.displayDate(calendar: calendar) ?? Date(timeIntervalSince1970: 0)
            },
            set: { newDate in
                let components = calendar.dateComponents([.year, .month, .day], from: newDate)
                if let newDay = CalendarDay(dateComponents: components) {
                    wrappedValue = newDay
                }
            }
        )
    }
}
