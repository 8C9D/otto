import Foundation
import Testing
@testable import OttoDomain

// Insights (spec §7.2) against HAND-COMPUTED fixtures: every expected number
// below was worked out on paper before the implementation ran, because these
// are figures financial decisions get made on - a test written from the
// implementation's output would only confirm the code does what it does.

/// A fixture with the fields Insights varies; everything else is constant noise.
private func insightsSubscription(
    index: Int,
    name: String,
    category: OttoDomain.Category = .other,
    status: SubscriptionStatus = .active,
    amountCents: Int,
    cycle: BillingCycle,
    cycleStartDay: CalendarDay,
    pauseEndsOn: CalendarDay? = nil,
    pausedOn: CalendarDay? = nil,
    trial: TrialTerm? = nil,
    lastUsedDate: CalendarDay? = nil,
    deletedAt: Date? = nil
) throws -> Subscription {
    let episodes: [PauseEpisode] = (status == .paused || pausedOn != nil || pauseEndsOn != nil)
        ? [PauseEpisode(
            id: try fixtureUUID(index + 700),
            startedOn: pausedOn,
            scheduledResumeOn: pauseEndsOn,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )]
        : []
    return Subscription(
        id: try fixtureUUID(index),
        name: name,
        category: category,
        status: status,
        amountCents: amountCents,
        currencyCode: "CAD",
        cycle: cycle,
        cycleStartDay: cycleStartDay,
        reminderLeadDays: 3,
        pauseEpisodes: episodes,
        trial: trial,
        lastUsedDate: lastUsedDate,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        deletedAt: deletedAt
    )
}

@Suite("Monthly burn and the annualised total (spec §7.2)")
struct MonthlyBurnTests {

    /// Hand computation, today 2026-08-07:
    ///   Netflix   1899¢ monthly            → 1899 (monthly is the unit)
    ///   iCloud   12900¢ annual             → 12900 × 30.4375/365.25 = 12900/12 = 1075 exactly
    ///   Gym       1099¢ weekly             → 1099 × 30.4375/7 = 33450.8125/7 = 4778.6875 → 4779
    ///   Boundary     8¢ every 487 days     → 8 × 30.4375/487 = 243.5/487 = 0.5 → 1 (half away from zero)
    ///   Total 1899 + 1075 + 4779 + 1 = 7754; annualised 7754 × 12 = 93048.
    private func burnWorld() throws -> [Subscription] {
        [
            try insightsSubscription(
                index: 1, name: "Netflix", category: .streamingAndVideo,
                amountCents: 1899, cycle: .monthly, cycleStartDay: try day(2026, 1, 15)
            ),
            try insightsSubscription(
                index: 2, name: "iCloud", category: .cloudAndStorage,
                amountCents: 12900, cycle: .annual, cycleStartDay: try day(2026, 3, 1)
            ),
            try insightsSubscription(
                index: 3, name: "Gym", category: .fitnessAndHealth,
                amountCents: 1099, cycle: .weekly, cycleStartDay: try day(2026, 8, 3)
            ),
            try insightsSubscription(
                index: 4, name: "Boundary",
                amountCents: 8, cycle: try cycle(.day, 487), cycleStartDay: try day(2026, 8, 1)
            )
        ]
    }

    @Test("all four cycle units normalise to the hand-computed monthly burn, rounding boundary included")
    func handComputedBurn() throws {
        let today = try day(2026, 8, 7)
        let world = try burnWorld()
        #expect(monthlyBurnCents(subscriptions: world, asOf: today) == 7754)
        #expect(annualizedTotalCents(subscriptions: world, asOf: today) == 93048)
    }

    @Test("by category: same numbers, grouped, costliest first")
    func handComputedCategories() throws {
        let categories = burnByCategory(subscriptions: try burnWorld(), asOf: try day(2026, 8, 7))
        #expect(categories == [
            CategoryBurn(category: .fitnessAndHealth, monthlyCents: 4779),
            CategoryBurn(category: .streamingAndVideo, monthlyCents: 1899),
            CategoryBurn(category: .cloudAndStorage, monthlyCents: 1075),
            CategoryBurn(category: .other, monthlyCents: 1)
        ])
    }

    @Test("a converted-unacknowledged trial burns at the converted price - it is effectively active")
    func convertedTrialBurnsConverted() throws {
        // Converted Aug 1 to 1100¢/month; stored status still .trial. The
        // trial-era amountCents (0) must play no part.
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 2), lengthDays: 30, convertsToAmountCents: 1100)
        let converted = try insightsSubscription(
            index: 5, name: "FoodApp", status: .trial,
            amountCents: 0, cycle: .monthly, cycleStartDay: try day(2026, 7, 2), trial: trial
        )
        #expect(monthlyBurnCents(subscriptions: [converted], asOf: try day(2026, 8, 7)) == 1100)
    }

    @Test("burn is correct on an empty database and with a single subscription")
    func emptyAndSingle() throws {
        let today = try day(2026, 8, 7)
        #expect(monthlyBurnCents(subscriptions: [], asOf: today) == 0)
        #expect(annualizedTotalCents(subscriptions: [], asOf: today) == 0)
        #expect(burnByCategory(subscriptions: [], asOf: today) == [])

        let single = try insightsSubscription(
            index: 1, name: "Netflix", amountCents: 1899, cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15)
        )
        #expect(monthlyBurnCents(subscriptions: [single], asOf: today) == 1899)
    }

    @Test("paused, cancellation-state, archived, and deleted subscriptions burn nothing")
    func nonBurningStatuses() throws {
        let today = try day(2026, 8, 7)
        let world = [
            try insightsSubscription(
                index: 1, name: "Paused", status: .paused, amountCents: 1399,
                cycle: .monthly, cycleStartDay: try day(2026, 1, 1), pausedOn: try day(2026, 7, 10)
            ),
            try insightsSubscription(
                index: 2, name: "Cancelled", status: .cancelled, amountCents: 999,
                cycle: .monthly, cycleStartDay: try day(2026, 1, 1)
            ),
            try insightsSubscription(
                index: 3, name: "Archived", status: .archived, amountCents: 999,
                cycle: .monthly, cycleStartDay: try day(2026, 1, 1)
            ),
            try insightsSubscription(
                index: 4, name: "Deleted", amountCents: 999,
                cycle: .monthly, cycleStartDay: try day(2026, 1, 1),
                deletedAt: Date(timeIntervalSince1970: 5_000)
            )
        ]
        #expect(monthlyBurnCents(subscriptions: world, asOf: today) == 0)
    }
}

@Suite("Paused spend - the separate line at the frozen price (spec §7.2, §5.1)")
struct PausedSpendTests {

    @Test("a price change during the pause does not move the paused line")
    func frozenPriceIgnoresPauseEraChange() throws {
        // Paused Jul 10 at 1199¢. A pre-pause change (Jun 1: 999 → 1199) is
        // history; a during-pause change (Jul 20: 1199 → 1399) already moved
        // amountCents to 1399 - but the paused line stays at the 1199 freeze.
        let paused = try insightsSubscription(
            index: 1, name: "Duolingo", status: .paused, amountCents: 1399,
            cycle: .monthly, cycleStartDay: try day(2026, 1, 5), pausedOn: try day(2026, 7, 10)
        )
        let changes = [
            PriceChange(
                id: try fixtureUUID(701), subscriptionID: paused.id,
                effectiveDate: try day(2026, 6, 1), oldAmountCents: 999, newAmountCents: 1199,
                source: .userEdit,
                createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000)
            ),
            PriceChange(
                id: try fixtureUUID(702), subscriptionID: paused.id,
                effectiveDate: try day(2026, 7, 20), oldAmountCents: 1199, newAmountCents: 1399,
                source: .userEdit,
                createdAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        ]

        #expect(frozenPausedAmountCents(for: paused, priceChanges: changes) == 1199)

        let lines = pausedSpendLines(subscriptions: [paused], priceChanges: changes, asOf: try day(2026, 8, 7))
        #expect(lines.count == 1)
        #expect(lines.first?.frozenAmountCents == 1199)
        #expect(lines.first?.monthlyEquivalent == 1199)
        // And the paused subscription contributes nothing to burn.
        #expect(monthlyBurnCents(subscriptions: [paused], asOf: try day(2026, 8, 7)) == 0)
    }

    @Test("with no recorded pause start the current price is the honest fallback")
    func unknownFreezePointFallsBack() throws {
        let legacy = try insightsSubscription(
            index: 1, name: "Legacy", status: .paused, amountCents: 1399,
            cycle: .monthly, cycleStartDay: try day(2026, 1, 5)
        )
        #expect(frozenPausedAmountCents(for: legacy, priceChanges: []) == 1399)
    }

    @Test("a pause past its end date has left the paused line and rejoined burn")
    func resumedPauseLeavesPausedLine() throws {
        let resumed = try insightsSubscription(
            index: 1, name: "Resumed", status: .paused, amountCents: 1099,
            cycle: .monthly, cycleStartDay: try day(2026, 1, 5),
            pauseEndsOn: try day(2026, 8, 1), pausedOn: try day(2026, 7, 1)
        )
        let today = try day(2026, 8, 7)
        #expect(pausedSpendLines(subscriptions: [resumed], priceChanges: [], asOf: today) == [])
        #expect(monthlyBurnCents(subscriptions: [resumed], asOf: today) == 1099)
    }
}

@Suite("Converting soon (spec §7.2's pinned trial rule)")
struct ConvertingSoonTests {

    @Test("a trial burns $0 now and appears with the hand-computed after-figure and date")
    func handComputedConversionConsequence() throws {
        // Netflix burns 1899. The trial converts Aug 13 to 950¢ monthly:
        // burn goes from 1899 to 2849 on Aug 13. That sentence is the product.
        let netflix = try insightsSubscription(
            index: 1, name: "Netflix", amountCents: 1899, cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15)
        )
        let term = try makeTrialTerm(
            index: 501, startDate: try day(2026, 7, 30), lengthDays: 14, convertsToAmountCents: 950
        )
        let trial = try insightsSubscription(
            index: 2, name: "Perplexity", status: .trial, amountCents: 0,
            cycle: .monthly, cycleStartDay: try day(2026, 7, 30), trial: term
        )
        let today = try day(2026, 8, 7)

        #expect(monthlyBurnCents(subscriptions: [netflix, trial], asOf: today) == 1899)

        let soon = convertingSoon(subscriptions: [netflix, trial], asOf: today)
        #expect(soon.count == 1)
        let entry = try #require(soon.first)
        #expect(entry.conversionDate == (try day(2026, 8, 13)))
        #expect(entry.convertsToAmountCents == 950)
        #expect(entry.monthlyEquivalent == 950)
        #expect(entry.burnAfterCents == 2849)
    }

    @Test("two trials accumulate: the later conversion states the burn with both included")
    func cumulativeConversions() throws {
        // Base burn 1899. Trial A converts Aug 13 (+950 → 2849); trial B
        // converts Aug 20, annual 12000¢ → 1000/month (+1000 → 3849).
        let netflix = try insightsSubscription(
            index: 1, name: "Netflix", amountCents: 1899, cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15)
        )
        let termA = try makeTrialTerm(
            index: 501, startDate: try day(2026, 7, 30), lengthDays: 14, convertsToAmountCents: 950
        )
        let trialA = try insightsSubscription(
            index: 2, name: "Perplexity", status: .trial, amountCents: 0,
            cycle: .monthly, cycleStartDay: try day(2026, 7, 30), trial: termA
        )
        let termB = try makeTrialTerm(
            index: 502, startDate: try day(2026, 7, 21), lengthDays: 30, convertsToAmountCents: 12000
        )
        let trialB = try insightsSubscription(
            index: 3, name: "Setapp", status: .trial, amountCents: 0,
            cycle: .annual, cycleStartDay: try day(2026, 7, 21), trial: termB
        )

        let soon = convertingSoon(subscriptions: [netflix, trialA, trialB], asOf: try day(2026, 8, 7))
        #expect(soon.map(\.subscription.name) == ["Perplexity", "Setapp"])
        #expect(soon.map(\.burnAfterCents) == [2849, 3849])
        #expect(soon.map(\.conversionDate) == [try day(2026, 8, 13), try day(2026, 8, 20)])
    }
}

@Suite("The next 12 months (spec §7.2)")
struct Next12MonthsTests {

    @Test("hand-computed projection: partial current month, an annual cluster, and a passed charge")
    func handComputedProjection() throws {
        // Today 2026-08-07. Three subscriptions:
        //   Netflix 1899¢ monthly, 15th        → every bucket Aug 26 .. Jul 27
        //   Router   500¢ monthly, 5th         → Aug 5 is already PAST today:
        //                                        first counted charge Sep 5
        //   iCloud 12900¢ annual, Mar 1        → only Mar 2027
        // Buckets: Aug 1899; Sep-Feb 2399 each; Mar 15299; Apr-Jul 2399 each.
        let world = [
            try insightsSubscription(
                index: 1, name: "Netflix", amountCents: 1899, cycle: .monthly,
                cycleStartDay: try day(2026, 1, 15)
            ),
            try insightsSubscription(
                index: 2, name: "Router", amountCents: 500, cycle: .monthly,
                cycleStartDay: try day(2026, 8, 5)
            ),
            try insightsSubscription(
                index: 3, name: "iCloud", amountCents: 12900, cycle: .annual,
                cycleStartDay: try day(2026, 3, 1)
            )
        ]

        let projection = next12Months(subscriptions: world, asOf: try day(2026, 8, 7))

        #expect(projection.map { $0.year * 100 + $0.month } == [
            202608, 202609, 202610, 202611, 202612,
            202701, 202702, 202703, 202704, 202705, 202706, 202707
        ])
        #expect(projection.map(\.totalCents) == [
            1899, 2399, 2399, 2399, 2399, 2399, 2399, 15299, 2399, 2399, 2399, 2399
        ])
    }

    @Test("a trial projects its paid sequence and a dated pause projects from its resume")
    func trialAndPauseProject() throws {
        // Trial converts Aug 13 to 950¢ monthly → 950 in every bucket.
        // Paused sub 1099¢ monthly on the 1st, resuming Oct 1 → 1099 from the
        // October bucket on (10 buckets). An indefinite pause projects nothing.
        let term = try makeTrialTerm(
            index: 501, startDate: try day(2026, 7, 30), lengthDays: 14, convertsToAmountCents: 950
        )
        let world = [
            try insightsSubscription(
                index: 1, name: "Trial", status: .trial, amountCents: 0,
                cycle: .monthly, cycleStartDay: try day(2026, 7, 30), trial: term
            ),
            try insightsSubscription(
                index: 2, name: "DatedPause", status: .paused, amountCents: 1099,
                cycle: .monthly, cycleStartDay: try day(2026, 6, 1),
                pauseEndsOn: try day(2026, 10, 1), pausedOn: try day(2026, 7, 15)
            ),
            try insightsSubscription(
                index: 3, name: "IndefinitePause", status: .paused, amountCents: 5000,
                cycle: .monthly, cycleStartDay: try day(2026, 6, 1), pausedOn: try day(2026, 7, 15)
            )
        ]

        let projection = next12Months(subscriptions: world, asOf: try day(2026, 8, 7))

        #expect(projection.map(\.totalCents) == [
            950, 950, 2049, 2049, 2049, 2049, 2049, 2049, 2049, 2049, 2049, 2049
        ])
    }

    @Test("an empty database projects twelve zero months, not an empty list")
    func emptyProjection() throws {
        let projection = next12Months(subscriptions: [], asOf: try day(2026, 8, 7))
        #expect(projection.count == 12)
        #expect(projection.allSatisfy { $0.totalCents == 0 })
    }
}

@Suite("The price-change log (spec §7.2)")
struct PriceChangeLogTests {

    @Test("changes across subscriptions merge newest-first with names attached")
    func mergedLog() throws {
        let netflix = try insightsSubscription(
            index: 1, name: "Netflix", amountCents: 1899, cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15)
        )
        let gym = try insightsSubscription(
            index: 2, name: "Gym", amountCents: 1099, cycle: .weekly,
            cycleStartDay: try day(2026, 8, 3)
        )
        let changes = [
            PriceChange(
                id: try fixtureUUID(701), subscriptionID: netflix.id,
                effectiveDate: try day(2026, 3, 1), oldAmountCents: 1699, newAmountCents: 1899,
                source: .userEdit,
                createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000)
            ),
            PriceChange(
                id: try fixtureUUID(702), subscriptionID: gym.id,
                effectiveDate: try day(2026, 6, 12), oldAmountCents: 999, newAmountCents: 1099,
                source: .chargeMismatch,
                createdAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        ]

        let log = priceChangeLog(subscriptions: [netflix, gym], priceChanges: changes)

        #expect(log.map(\.subscriptionName) == ["Gym", "Netflix"])
        #expect(log.map(\.change.newAmountCents) == [1099, 1899])
        #expect(priceChangeLog(subscriptions: [], priceChanges: changes) == [])
    }
}
