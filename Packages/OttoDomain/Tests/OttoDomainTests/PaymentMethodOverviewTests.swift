import Foundation
import Testing
@testable import OttoDomain

private func card(index: Int, expiryMonth: Int, expiryYear: Int) throws -> PaymentMethod {
    PaymentMethod(
        id: try fixtureUUID(index),
        label: "Bank Mastercard ..4821",
        last4: "4821",
        issuer: "Bank",
        expiryMonth: expiryMonth,
        expiryYear: expiryYear,
        isDefault: true,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

@Suite("Card expiry warnings (spec §5.5)")
struct CardExpiryTests {

    @Test("a card is valid through the END of its printed month")
    func validThroughMonthEnd() throws {
        let september = try card(index: 900, expiryMonth: 9, expiryYear: 2026)
        #expect(september.lastValidDay == (try day(2026, 9, 30)))
        // On its last valid day it warns; the day after, it is expired.
        #expect(september.expiryStatus(asOf: try day(2026, 9, 30))
            == .expiringSoon(lastValidDay: try day(2026, 9, 30)))
        #expect(september.expiryStatus(asOf: try day(2026, 10, 1))
            == .expired(lastValidDay: try day(2026, 9, 30)))
    }

    @Test("the warning opens exactly 60 days out: 61 is quiet, 60 warns")
    func warningBoundary() throws {
        // Sep 2026 card: last valid day Sep 30. Aug 1 is 60 days before
        // (30 remaining in Aug + 30 in Sep); Jul 31 is 61.
        let september = try card(index: 900, expiryMonth: 9, expiryYear: 2026)
        #expect(september.expiryStatus(asOf: try day(2026, 7, 31)) == .valid)
        #expect(september.expiryStatus(asOf: try day(2026, 8, 1))
            == .expiringSoon(lastValidDay: try day(2026, 9, 30)))
    }

    @Test("a December card rolls the year for its month end")
    func decemberRollsYear() throws {
        let december = try card(index: 900, expiryMonth: 12, expiryYear: 2026)
        #expect(december.lastValidDay == (try day(2026, 12, 31)))
    }
}

@Suite("Per-card totals (spec §5.5)")
struct PaymentMethodLoadTests {

    @Test("hand-computed per-card monthly totals, burn rules applied")
    func handComputedLoads() throws {
        // Card A: Netflix 1899¢ monthly (→1899) + iCloud 12900¢ annual (→1075)
        //   = 2 subscriptions, 2974¢/month.
        // Card B: Gym 1099¢ weekly → 4779.
        // A paused subscription on card A and a cardless one count nowhere.
        let cardA = try fixtureUUID(901)
        let cardB = try fixtureUUID(902)
        func sub(
            _ index: Int, amount: Int, cycle: BillingCycle,
            method: UUID?, status: SubscriptionStatus = .active
        ) throws -> Subscription {
            Subscription(
                id: try fixtureUUID(index),
                name: "S\(index)",
                category: .other,
                status: status,
                amountCents: amount,
                currencyCode: "CAD",
                cycle: cycle,
                cycleStartDay: try day(2026, 1, 15),
                reminderLeadDays: 3,
                paymentMethodID: method,
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0)
            )
        }
        let world = [
            try sub(1, amount: 1899, cycle: .monthly, method: cardA),
            try sub(2, amount: 12900, cycle: .annual, method: cardA),
            try sub(3, amount: 1099, cycle: .weekly, method: cardB),
            try sub(4, amount: 5000, cycle: .monthly, method: cardA, status: .paused),
            try sub(5, amount: 700, cycle: .monthly, method: nil)
        ]

        let loads = paymentMethodLoads(subscriptions: world, asOf: try day(2026, 8, 7))

        #expect(loads[cardA] == PaymentMethodLoad(subscriptionCount: 2, monthlyCents: 2974))
        #expect(loads[cardB] == PaymentMethodLoad(subscriptionCount: 1, monthlyCents: 4779))
        #expect(loads.count == 2)
    }
}
