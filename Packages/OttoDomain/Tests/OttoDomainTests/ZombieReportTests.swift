import Foundation
import Testing
@testable import OttoDomain

// Zombie detection (spec §7.3) against hand-computed fixtures. Day counts from
// 2026-08-07 backwards, worked out on paper:
//   May 10 → Aug 7 = 21 (rest of May) + 30 (Jun) + 31 (Jul) + 7 = 89 days
//   May  9 → Aug 7 = 90 days
//   May  8 → Aug 7 = 91 days

private func zombieSubscription(
    index: Int,
    name: String,
    status: SubscriptionStatus = .active,
    amountCents: Int = 1100,
    cycleStartDay: CalendarDay,
    trial: TrialTerm? = nil,
    lastUsedDate: CalendarDay? = nil
) throws -> Subscription {
    Subscription(
        id: try fixtureUUID(index),
        name: name,
        category: .foodAndDelivery,
        status: status,
        amountCents: amountCents,
        currencyCode: "CAD",
        cycle: .monthly,
        cycleStartDay: cycleStartDay,
        reminderLeadDays: 3,
        trial: trial,
        lastUsedDate: lastUsedDate,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

@Suite("Zombie detection (spec §7.3)")
struct ZombieReportTests {

    private var today: CalendarDay { get throws { try day(2026, 8, 7) } }

    @Test("the 90-day threshold: 89 days is not a zombie, 90 and 91 are")
    func thresholdBoundary() throws {
        let world = [
            try zombieSubscription(
                index: 1, name: "At89", cycleStartDay: try day(2026, 1, 15),
                lastUsedDate: try day(2026, 5, 10)
            ),
            try zombieSubscription(
                index: 2, name: "At90", cycleStartDay: try day(2026, 1, 15),
                lastUsedDate: try day(2026, 5, 9)
            ),
            try zombieSubscription(
                index: 3, name: "At91", cycleStartDay: try day(2026, 1, 15),
                lastUsedDate: try day(2026, 5, 8)
            )
        ]

        let report = zombieReport(subscriptions: world, asOf: try today)

        #expect(Set(report.map(\.subscription.name)) == ["At90", "At91"])
        #expect(report.first { $0.subscription.name == "At90" }?.daysSinceUse == 90)
        #expect(report.first { $0.subscription.name == "At91" }?.daysSinceUse == 91)
    }

    @Test("the cost since last use is the hand-computed charge sequence, with the annual number attached")
    func handComputedCost() throws {
        // Last used May 9; monthly on the 15th at 1899¢. Charges after May 9
        // through Aug 7: May 15, Jun 15, Jul 15 = 3 × 1899 = 5697.
        // Annual: monthly-equivalent 1899 × 12 = 22788.
        let fantuan = try zombieSubscription(
            index: 1, name: "FoodApp", amountCents: 1899,
            cycleStartDay: try day(2026, 1, 15), lastUsedDate: try day(2026, 5, 9)
        )

        let report = zombieReport(subscriptions: [fantuan], asOf: try today)

        let entry = try #require(report.first)
        #expect(entry.lastUsedDate == (try day(2026, 5, 9)))
        #expect(entry.daysSinceUse == 90)
        #expect(entry.costSinceCents == 5697)
        #expect(entry.annualCostCents == 22788)
    }

    @Test("a subscription never used counts from its anchor, anchor charge included")
    func neverUsed() throws {
        // No recorded use; anchor Jan 15 is 204 days back. Charges Jan 15
        // through Aug 7: Jan, Feb, Mar, Apr, May, Jun, Jul 15 = 7 × 1899 = 13293.
        let never = try zombieSubscription(
            index: 1, name: "NeverUsed", amountCents: 1899, cycleStartDay: try day(2026, 1, 15)
        )

        let report = zombieReport(subscriptions: [never], asOf: try today)

        let entry = try #require(report.first)
        #expect(entry.lastUsedDate == nil)
        #expect(entry.daysSinceUse == 204)
        #expect(entry.costSinceCents == 13293)
    }

    @Test("a converted-and-noticed-late trial appears, costed from its conversion")
    func convertedLateTrialAppears() throws {
        // Trial started Mar 1, 31 days: converted Apr 1 to 1100¢/month, status
        // never flipped, never used. Reference = conversion anchor, 128 days
        // back. Charges Apr 1 through Aug 7: Apr, May, Jun, Jul, Aug 1
        // = 5 × 1100 = 5500. This record is the reason the report exists.
        let term = try makeTrialTerm(startDate: try day(2026, 3, 1), lengthDays: 31, convertsToAmountCents: 1100)
        let convertedLate = try zombieSubscription(
            index: 1, name: "FoodApp", status: .trial, amountCents: 0,
            cycleStartDay: try day(2026, 3, 1), trial: term
        )

        let report = zombieReport(subscriptions: [convertedLate], asOf: try today)

        let entry = try #require(report.first)
        #expect(entry.daysSinceUse == 128)
        #expect(entry.costSinceCents == 5500)
        #expect(entry.annualCostCents == 1100 * 12)
    }

    @Test("an unconverted trial and a paused subscription are not zombies - nothing is billing")
    func nonBillingStatesExcluded() throws {
        let term = try makeTrialTerm(startDate: try day(2026, 8, 1), lengthDays: 30)
        let world = [
            try zombieSubscription(
                index: 1, name: "FreshTrial", status: .trial,
                cycleStartDay: try day(2026, 8, 1), trial: term
            ),
            Subscription(
                id: try fixtureUUID(2),
                name: "Paused",
                category: .other,
                status: .paused,
                amountCents: 1100,
                currencyCode: "CAD",
                cycle: .monthly,
                cycleStartDay: try day(2026, 1, 15),
                reminderLeadDays: 3,
                lastUsedDate: try day(2026, 1, 20),
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0)
            )
        ]
        #expect(zombieReport(subscriptions: world, asOf: try today) == [])
    }

    @Test("the report sorts costliest first and is empty on an empty database")
    func sortingAndEmpty() throws {
        #expect(zombieReport(subscriptions: [], asOf: try today) == [])

        let cheap = try zombieSubscription(
            index: 1, name: "Cheap", amountCents: 100,
            cycleStartDay: try day(2026, 1, 15), lastUsedDate: try day(2026, 4, 1)
        )
        let dear = try zombieSubscription(
            index: 2, name: "Dear", amountCents: 9900,
            cycleStartDay: try day(2026, 1, 15), lastUsedDate: try day(2026, 4, 1)
        )
        let report = zombieReport(subscriptions: [cheap, dear], asOf: try today)
        #expect(report.map(\.subscription.name) == ["Dear", "Cheap"])
    }
}
