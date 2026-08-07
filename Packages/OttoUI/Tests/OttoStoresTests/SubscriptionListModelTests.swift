import Foundation
import Testing
import OttoDomain
@testable import OttoStores

@MainActor
@Suite("Subscription list sorting and filtering (spec §7.1)")
struct SubscriptionListModelTests {

    private func fixtures() throws -> (subscriptions: [Subscription], today: CalendarDay) {
        // Next charges from Aug 6: cheap bills Aug 10, pricey bills Aug 20 but
        // costs more monthly; annual bills Oct 1.
        let cheap = try makeSubscription(
            index: 1, name: "Cheap", amountCents: 500, cycleStartDay: try day(2026, 1, 10)
        )
        let pricey = try makeSubscription(
            index: 2, name: "Pricey", amountCents: 2500, cycleStartDay: try day(2026, 1, 20)
        )
        let annual = try makeSubscription(
            index: 3, name: "Annual", status: .paused, amountCents: 12000, cycle: .annual,
            cycleStartDay: try day(2025, 10, 1)
        )
        return ([cheap, pricey, annual], try day(2026, 8, 6))
    }

    @Test("every row carries the monthly equivalent, so cycles compare at a glance")
    func monthlyEquivalents() throws {
        let (subscriptions, today) = try fixtures()
        let model = SubscriptionListModel()
        let rows = model.rows(subscriptions: subscriptions, cancellations: [:], today: today)

        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.subscription.name, $0) })
        #expect(byName["Cheap"]?.monthlyEquivalentCents == 500)
        #expect(byName["Annual"]?.monthlyEquivalentCents == 1000)
    }

    @Test("sort by next date puts the soonest first and dateless rows last")
    func sortByNextDate() throws {
        let (subscriptions, today) = try fixtures()
        let model = SubscriptionListModel()
        model.sortOrder = .nextDate

        let rows = model.rows(subscriptions: subscriptions, cancellations: [:], today: today)

        // The paused annual has no pauseEndsOn, so it has no next date and sinks.
        #expect(rows.map(\.subscription.name) == ["Cheap", "Pricey", "Annual"])
        #expect(rows.first?.nextDate == (try day(2026, 8, 10)))
        #expect(rows.last?.nextDate == nil)
    }

    @Test("sort by cost puts the highest monthly equivalent first")
    func sortByCost() throws {
        let (subscriptions, today) = try fixtures()
        let model = SubscriptionListModel()
        model.sortOrder = .cost

        let rows = model.rows(subscriptions: subscriptions, cancellations: [:], today: today)

        #expect(rows.map(\.subscription.name) == ["Pricey", "Annual", "Cheap"])
    }

    @Test("sort by name is case-insensitive and alphabetical")
    func sortByName() throws {
        let (subscriptions, today) = try fixtures()
        let model = SubscriptionListModel()
        model.sortOrder = .name

        let rows = model.rows(subscriptions: subscriptions, cancellations: [:], today: today)

        #expect(rows.map(\.subscription.name) == ["Annual", "Cheap", "Pricey"])
    }

    @Test("the status filter keeps only matching subscriptions; nil keeps everything")
    func statusFilter() throws {
        let (subscriptions, today) = try fixtures()
        let model = SubscriptionListModel()

        model.statusFilter = .paused
        let paused = model.rows(subscriptions: subscriptions, cancellations: [:], today: today)
        #expect(paused.map(\.subscription.name) == ["Annual"])

        model.statusFilter = nil
        let all = model.rows(subscriptions: subscriptions, cancellations: [:], today: today)
        #expect(all.count == 3)
    }

    @Test("the filter and the badge use effective status - a converted trial rows as Active (spec §5.2a, v1.7)")
    func filterUsesEffectiveStatus() throws {
        let today = try day(2026, 8, 6)
        let converted = try makeSubscription(
            index: 10,
            status: .trial,
            cycleStartDay: try day(2026, 7, 1),
            trial: try makeTrialTerm(startDate: try day(2026, 7, 1), lengthDays: 14)
        )
        let model = SubscriptionListModel()

        model.statusFilter = .active
        let active = model.rows(subscriptions: [converted], cancellations: [:], today: today)
        #expect(active.map(\.id) == [converted.id])
        #expect(active.first?.effectiveStatus == .active)

        model.statusFilter = .trial
        #expect(model.rows(subscriptions: [converted], cancellations: [:], today: today).isEmpty)
    }
}
