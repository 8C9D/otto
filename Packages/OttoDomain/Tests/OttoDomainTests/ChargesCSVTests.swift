import Foundation
import Testing
@testable import OttoDomain

@Suite("Charges CSV (Wave 8: human-readable, lossy, one-way)")
struct ChargesCSVTests {

    private let created = Date(timeIntervalSinceReferenceDate: 100)

    private func subscription(_ index: Int, name: String, deletedAt: Date? = nil) throws -> Subscription {
        Subscription(
            id: try fixtureUUID(index),
            name: name,
            category: .other,
            status: .active,
            amountCents: 1099,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 3,
            createdAt: created,
            updatedAt: created,
            deletedAt: deletedAt
        )
    }

    private func event(
        _ index: Int, subscription: Int, date: CalendarDay, cents: Int,
        state: BillingEvent.State = .confirmedCharged, actualCents: Int? = nil,
        deletedAt: Date? = nil
    ) throws -> BillingEvent {
        BillingEvent(
            id: try fixtureUUID(index),
            subscriptionID: try fixtureUUID(subscription),
            expectedDate: date,
            expectedAmountCents: cents,
            state: state,
            actualAmountCents: actualCents,
            createdAt: created,
            updatedAt: created,
            deletedAt: deletedAt
        )
    }

    @Test("the hand-checked fixture: exact bytes, dates ordered, amounts exact decimals")
    func handCheckedFixture() throws {
        let snapshot = OttoDataSnapshot(
            subscriptions: [
                try subscription(1, name: "Netflix"),
                try subscription(2, name: "FoodApp, \"delivery\"")
            ],
            billingEvents: [
                try event(101, subscription: 1, date: try day(2026, 2, 15), cents: 2099),
                try event(102, subscription: 2, date: try day(2026, 1, 3), cents: 1100,
                          state: .unexpectedCharge, actualCents: 1150),
                try event(103, subscription: 1, date: try day(2026, 1, 15), cents: 2099,
                          state: .upcoming)
            ]
        )

        // Hand-computed, not derived: 1100 is "11.00", 1150 "11.50", 2099 "20.99";
        // the quoted name is RFC 4180-escaped; rows sort by date.
        let expected = [
            "date,subscription,state,expected amount,actual amount,currency",
            "2026-01-03,\"FoodApp, \"\"delivery\"\"\",unexpected charge,11.00,11.50,CAD",
            "2026-01-15,Netflix,expected,20.99,,CAD",
            "2026-02-15,Netflix,charged,20.99,,CAD",
            ""
        ].joined(separator: "\r\n")
        #expect(chargesCSV(from: snapshot) == expected)
    }

    @Test("tombstoned rows and deleted subscriptions stay out - the CSV is the readable view, not the backup")
    func lossyByDesign() throws {
        let deleted = Date(timeIntervalSinceReferenceDate: 999)
        let snapshot = OttoDataSnapshot(
            subscriptions: [
                try subscription(1, name: "Live"),
                try subscription(2, name: "Gone", deletedAt: deleted)
            ],
            billingEvents: [
                try event(101, subscription: 1, date: try day(2026, 1, 15), cents: 1099),
                try event(102, subscription: 1, date: try day(2026, 2, 15), cents: 1099, deletedAt: deleted),
                try event(103, subscription: 2, date: try day(2026, 1, 20), cents: 500)
            ]
        )

        let csv = chargesCSV(from: snapshot)

        #expect(csv.contains("2026-01-15"))
        #expect(!csv.contains("2026-02-15"))
        #expect(!csv.contains("Gone"))
    }

    @Test("cents render as exact decimal strings, including edge amounts")
    func decimalAmounts() {
        #expect(decimalAmount(cents: 0) == "0.00")
        #expect(decimalAmount(cents: 5) == "0.05")
        #expect(decimalAmount(cents: 50) == "0.50")
        #expect(decimalAmount(cents: 1099) == "10.99")
        #expect(decimalAmount(cents: 100_000) == "1000.00")
        #expect(decimalAmount(cents: -50) == "-0.50")
        #expect(decimalAmount(cents: -1099) == "-10.99")
    }

    @Test("an empty database produces just the header")
    func emptyDatabase() {
        #expect(chargesCSV(from: OttoDataSnapshot()) == "date,subscription,state,expected amount,actual amount,currency\r\n")
    }

    /// ⛔ F9. A subscription name is user text and this file is meant to be
    /// opened in a spreadsheet, so a name beginning with a formula trigger is a
    /// formula unless something stops it. Measured at `2d8913c`, before the
    /// fix: every one of these came back byte-for-byte, including the DDE shape
    /// `-2+3+cmd|' /C calc'!A0`, which asks the spreadsheet to run a program.
    ///
    /// The row is asserted whole, not just the name cell: the neutralizer must
    /// not disturb the columns beside it, and the amount column in particular
    /// must keep its leading minus, which is a number and not a formula.
    @Test("⛔ a name a spreadsheet would run as a formula is neutralized, and only the name is")
    func formulaInjectionIsNeutralized() throws {
        let hostile = [
            "=1+1": "'=1+1",
            "+1234567890": "'+1234567890",
            "-2+3+cmd|' /C calc'!A0": "'-2+3+cmd|' /C calc'!A0",
            "@SUM(1+1)*cmd|' /C calc'!A0": "'@SUM(1+1)*cmd|' /C calc'!A0",
            "\t=1+1": "'\t=1+1",
            "\r=1+1": "\"'\r=1+1\"",
            "Netflix": "Netflix",
            "FoodApp (5% off)": "FoodApp (5% off)"
        ]
        for (index, entry) in hostile.sorted(by: { $0.key < $1.key }).enumerated() {
            let subscription = try subscription(index + 1, name: entry.key)
            let snapshot = OttoDataSnapshot(
                subscriptions: [subscription],
                billingEvents: [
                    try event(
                        100 + index, subscription: index + 1, date: try day(2026, 1, 15),
                        cents: -1099, actualCents: -1150
                    )
                ]
            )
            let rows = chargesCSV(from: snapshot).components(separatedBy: "\r\n")
            #expect(
                rows.count > 1 && rows[1] == "2026-01-15,\(entry.value),charged,-10.99,-11.50,CAD",
                "name \(entry.key.debugDescription) produced row \((rows.count > 1 ? rows[1] : "").debugDescription)"
            )
        }
    }

    /// The neutralizer runs BEFORE the quoting, so a hostile name that also
    /// needs RFC 4180 quoting gets the apostrophe inside the quotes rather than
    /// a stray one outside them.
    @Test("⛔ a hostile name that also needs quoting is quoted around the neutralized text")
    func neutralizingComposesWithQuoting() throws {
        let snapshot = OttoDataSnapshot(
            subscriptions: [try subscription(1, name: "=SUM(A1,B1) \"quoted\"")],
            billingEvents: [
                try event(101, subscription: 1, date: try day(2026, 1, 15), cents: 1099)
            ]
        )
        let rows = chargesCSV(from: snapshot).components(separatedBy: "\r\n")
        #expect(rows.count > 1)
        #expect(rows[1] == "2026-01-15,\"'=SUM(A1,B1) \"\"quoted\"\"\",charged,10.99,,CAD")
    }
}
