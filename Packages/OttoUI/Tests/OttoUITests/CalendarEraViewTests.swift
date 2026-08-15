import Foundation
import SwiftUI
import Testing
import OttoDomain
@testable import OttoUI

/// The two F1 sites that live in the `OttoUI` target rather than `OttoStores`.
/// `reviews-2/REVIEW-1.md` finding 1 measured that both could be reverted to
/// their pre-F1 shape with every test green on every host, including the
/// Buddhist one the stage exists for - so the fix was correct and unguarded.
///
/// `asDate` is the one that matters. It is not a display seam: its `set` branch
/// is how `DatePicker` writes the next-charge date, the trial start date and the
/// pause-resume date back into the domain (`AddEditSubscriptionView`,
/// `PauseFlowView`). On a non-Gregorian device a regression there writes
/// era-numbered years straight into billing arithmetic.
///
/// Like `CalendarEraTests`, these are **trivially true on a Gregorian host** and
/// fail only under the non-Gregorian harness that file documents. This suite
/// carries no UIKit dependency, so it runs under `swift test` on the host and
/// `verify.sh` counts it.
@Suite("Calendar era in the view layer (F1)")
struct CalendarEraViewTests {

    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    @Test("the date picker reads a day out as its Gregorian instant")
    func asDateReadsGregorian() throws {
        let day = try #require(CalendarDay(year: 2026, month: 8, day: 15))
        var stored = day
        let binding = Binding(get: { stored }, set: { stored = $0 })

        #expect(binding.asDate().wrappedValue == gregorian.date(from: day.dateComponents))
    }

    @Test("⛔ the date picker writes the day back in the domain's era, not the device's")
    func asDateWritesGregorian() throws {
        let day = try #require(CalendarDay(year: 2026, month: 8, day: 15))
        var stored = try #require(CalendarDay(year: 2000, month: 1, day: 1))
        let binding = Binding(get: { stored }, set: { stored = $0 })
        let picked = try #require(gregorian.date(from: day.dateComponents))

        binding.asDate().wrappedValue = picked

        // The round trip is the whole point: whatever era the device numbers
        // years in, what lands in the domain must be 2026-08-15.
        #expect(stored == day)
    }

    @Test("the twelve-month projection labels resolve in the domain's era")
    func monthTextResolvesGregorian() throws {
        let projection = MonthlyProjection(year: 2026, month: 8, totalCents: 1100)
        let expected = try #require(gregorian.date(from: DateComponents(year: 2026, month: 8, day: 1)))

        #expect(InsightsView.monthText(projection) == expected.formatted(.dateTime.month(.wide).year()))
    }
}
