import Foundation
import Testing
import OttoDomain
@testable import OttoStores

@Suite("Display formatting: locale-aware, rounded only at display")
struct DisplayFormattingTests {

    private let enCA = Locale(identifier: "en_CA")

    @Test("cents format as localized currency")
    func currency() {
        #expect(currencyText(cents: 1099, currencyCode: "CAD", locale: enCA) == "$10.99")
        #expect(currencyText(cents: 0, currencyCode: "CAD", locale: enCA) == "$0.00")
        #expect(currencyText(cents: 12000, currencyCode: "CAD", locale: enCA) == "$120.00")
    }

    @Test("monthly equivalents for all four cycle units match the §7.2 formula")
    func monthlyEquivalents() throws {
        // amount x (30.4375 / cycle days), rounded at display only.
        #expect(monthlyEquivalentText(
            amountCents: 1099, cycle: .monthly, currencyCode: "CAD", locale: enCA
        ) == "$10.99")
        // 12000 / 12 exactly - a $120 annual is $10 a month.
        #expect(monthlyEquivalentText(
            amountCents: 12000, cycle: .annual, currencyCode: "CAD", locale: enCA
        ) == "$10.00")
        // 700 x 30.4375 / 7 = 3043.75 -> 3044.
        #expect(monthlyEquivalentText(
            amountCents: 700, cycle: .weekly, currencyCode: "CAD", locale: enCA
        ) == "$30.44")
        // 4500 x 30.4375 / 45 = 3043.75 -> 3044.
        let every45 = try #require(BillingCycle(unit: .day, interval: 45))
        #expect(monthlyEquivalentText(
            amountCents: 4500, cycle: every45, currencyCode: "CAD", locale: enCA
        ) == "$30.44")
    }

    @Test("a $120/yr and a $10/mo compare as equals - the reason the column exists")
    func annualVersusMonthly() {
        let annual = monthlyEquivalentText(amountCents: 12000, cycle: .annual, currencyCode: "CAD", locale: enCA)
        let monthly = monthlyEquivalentText(amountCents: 1000, cycle: .monthly, currencyCode: "CAD", locale: enCA)
        #expect(annual == monthly)
    }

    @Test("calendar days render through the locale, never by interpolation")
    func dayText() throws {
        let day = try #require(CalendarDay(year: 2026, month: 8, day: 15))
        #expect(day.displayText(calendar: Calendar(identifier: .gregorian), locale: enCA) == "Aug 15, 2026")
    }

    @Test("cycles get their friendly names")
    func cycleNames() throws {
        #expect(cycleText(.monthly) == "Monthly")
        #expect(cycleText(.quarterly) == "Quarterly")
        #expect(cycleText(.annual) == "Annual")
        #expect(cycleText(.biweekly) == "Biweekly")
        let every45 = try #require(BillingCycle(unit: .day, interval: 45))
        #expect(cycleText(every45) == "Every 45 days")
    }

    @Test("⛔ the count phrase RESOLVES its inflection - no morphology markup reaches the screen (Wave 10)")
    func subscriptionCountResolvesInflection() {
        // Payment methods rendered the literal string
        // "^[3 subscription](inflect: true) bill to this card" because
        // Text(String(localized:)) performs no inflection; nothing in the
        // suite read a RENDERED string, so it shipped. These are rendered.
        #expect(subscriptionCountText(1) == "1 subscription")
        #expect(subscriptionCountText(3) == "3 subscriptions")
        for count in 0...4 {
            let rendered = subscriptionCountText(count)
            #expect(!rendered.contains("^["))
            #expect(!rendered.contains("inflect"))
        }
    }
}
