import Foundation
import Testing
import OttoDomain
@testable import OttoStores

/// F1: `CalendarDay` is proleptic Gregorian by construction, so every conversion
/// between it and Foundation has to name that calendar at both ends. Reading a
/// day through `Calendar.current` on a device set to another calendar produces
/// an era-numbered year - 2569 rather than 2026 on a Buddhist device - which the
/// domain's own arithmetic then treats as Gregorian.
///
/// **These assertions are trivially true on a Gregorian host and cannot fail
/// there.** They fail on a non-Gregorian one, which this project can produce:
///
///     swift build --build-tests --package-path Packages/OttoUI
///     HELPER="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
///     BUNDLE="Packages/OttoUI/.build/arm64-apple-macosx/debug/OttoUIPackageTests.xctest/Contents/MacOS/OttoUIPackageTests"
///     export DYLD_FRAMEWORK_PATH="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
///     "$HELPER" --test-bundle-path "$BUNDLE" "$BUNDLE" --testing-library swift-testing \
///       -AppleLocale th_TH@calendar=buddhist
///
/// Recorded here so that nobody reads a green CI run as evidence about F1: CI
/// runners are Gregorian, and on a Gregorian host this file guards nothing.
///
/// **That command exits 0 under all three harness locales as of round 5,
/// item 8 (N2-1).** From `7a3cf54` to round 5's stage 3 it did not: the
/// non-Gregorian hosts carried five PRE-EXISTING failures
/// (`DisplayFormattingTests.swift` :49/:59/:68/:69 and
/// `NotificationReconciliationTests.swift:170` - 1 issue under Buddhist and
/// Japanese, 5 under ar_SA), because `Date.FormatStyle` rendered through the
/// process calendar (a `.locale()` call does not override it, so an explicit
/// en_CA read "Aug 15, 2569 BE" on a Buddhist host) and interpolated counts
/// took the process numbering system ("Every ٤٥ days", "١ subscription"
/// through `String(localized:)`/`AttributedString(localized:)`). The
/// formatters now honor the REQUESTED locale completely - calendar and
/// numbering included - while the `.current` default keeps device rendering
/// unchanged. The explicit-locale half is guarded on every host by
/// `DisplayFormattingTests.requestedLocaleIsHonoredCompletely`; the
/// day-CONVERSION assertions in this file still cannot fail on a Gregorian
/// host, which is what the paragraph above records.
@Suite("Calendar era: day conversions never resolve in the device calendar (F1)")
struct CalendarEraTests {

    /// The Gregorian reading of an instant, computed without touching the code
    /// under test, in the same timezone that code uses.
    private func gregorianDay(at instant: Date) -> DateComponents {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        return gregorian.dateComponents([.year, .month, .day], from: instant)
    }

    @Test("DateProvider.live reads today in the Gregorian era, not the device's")
    func liveTodayIsGregorian() {
        // `today()` reads its own `Date()`, so a run that straddles midnight
        // legitimately sees either day; bracketing it keeps the assertion about
        // the era rather than about the second it ran in.
        let before = gregorianDay(at: Date())
        let today = DateProvider.live.today()
        let after = gregorianDay(at: Date())

        let observed = DateComponents(year: today.year, month: today.month, day: today.day)
        #expect(observed == before || observed == after)
    }

    @Test("a calendar day resolves to its Gregorian instant, not the device calendar's")
    func displayDateIsGregorian() throws {
        let day = try #require(CalendarDay(year: 2026, month: 8, day: 15))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        #expect(day.displayDate() == gregorian.date(from: day.dateComponents))
    }

    @Test("the rendered text is the rendering of the day's Gregorian instant")
    func displayTextRendersTheGregorianInstant() throws {
        let day = try #require(CalendarDay(year: 2026, month: 8, day: 15))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let instant = try #require(gregorian.date(from: day.dateComponents))
        let enCA = Locale(identifier: "en_CA")

        // Since round 5, item 8 the style adopts the REQUESTED locale's
        // calendar, so `displayText(locale: enCA)` reads "Aug 15, 2026" on a
        // Buddhist device too (a Buddhist device still renders Buddhist years
        // through the `.current` default). The assertion stays in
        // instant-comparison form because what this file pins is the
        // CONVERSION: the instant being rendered is the one the stored day
        // denotes, whatever the rendering calendar.
        #expect(
            day.displayText(locale: enCA)
                == instant.formatted(
                    Date.FormatStyle(date: .abbreviated, locale: enCA, calendar: enCA.calendar)
                )
        )
    }

    @Test("the dispute summary names the charge day in the Gregorian era")
    func spokenTextIsGregorian() throws {
        // `spokenText` is what the user reads aloud to a bank. Its default
        // calendar is the fifth F1 site and had no guard: reverting it alone
        // left every test green on every host.
        let chargeDay = try #require(CalendarDay(year: 2026, month: 8, day: 15))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let instant = try #require(gregorian.date(from: chargeDay.dateComponents))
        let enCA = Locale(identifier: "en_CA")
        // The requested locale's calendar, matching the round-5 item-8 rule
        // `spokenText` itself now follows.
        let rendered = instant.formatted(
            Date.FormatStyle(date: .abbreviated, locale: enCA, calendar: enCA.calendar)
        )

        let summary = DisputeSummary(
            subscriptionName: "Gate Test",
            markedCancelledAt: Date(timeIntervalSince1970: 0),
            evidenceNotes: [],
            chargeDate: chargeDay,
            chargeAmountCents: 1100,
            currencyCode: "CAD"
        )
        #expect(summary.spokenText(locale: enCA).contains(rendered))
    }
}
