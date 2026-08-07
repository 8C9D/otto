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
}
