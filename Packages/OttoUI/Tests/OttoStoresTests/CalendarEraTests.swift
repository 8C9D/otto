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
/// **That command does not exit 0, and did not before F1 either.** The
/// non-Gregorian host has its own baseline of PRE-EXISTING failures, measured
/// at `7a3cf54` and unchanged by F1: 1 issue under `th_TH@calendar=buddhist`
/// and under `ja_JP@calendar=japanese`, 5 under `ar_SA@calendar=islamic-umalqura`
/// - `DisplayFormattingTests.swift:49,59,68,69` and
/// `NotificationReconciliationTests.swift:170`, all of which pin rendered
/// strings that a non-Gregorian `Calendar.autoupdatingCurrent` legitimately
/// writes differently. Read the named tests, not the exit code.
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

        // NOT `== "Aug 15, 2026"`. `Date.FormatStyle` renders through
        // `Calendar.autoupdatingCurrent`, which a `.locale()` call does not
        // override, so on a Buddhist device this correctly reads "Aug 15, 2569
        // BE" - the right instant, written the way the rest of that phone
        // writes it. What must hold on every device is that the instant being
        // rendered is the one the stored day denotes.
        #expect(
            day.displayText(locale: enCA)
                == instant.formatted(Date.FormatStyle(date: .abbreviated).locale(enCA))
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
        let rendered = instant.formatted(Date.FormatStyle(date: .abbreviated).locale(enCA))

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
