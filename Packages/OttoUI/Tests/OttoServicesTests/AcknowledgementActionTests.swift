import Foundation
import OttoDomain
import Testing
@testable import OttoServices

// Spec §5.3 (v1.4) + §6.4: "Keeping it" persists an acknowledgement on the
// charge's ledger row, and the planner honours it - so the silencing survives
// the cancel-all-then-replan reschedule that used to replant it (the Wave 4 gap).
@Suite("'Keeping it' persists and survives reschedules (spec §5.3, v1.4)")
struct AcknowledgementActionTests {

    /// A trial two days into its window: cancel-by Aug 8, conversion Aug 10.
    private func seedTrial(
        _ subscriptions: FakeSubscriptionRepository
    ) async throws -> (subscription: Subscription, trial: TrialTerm) {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 27), lengthDays: 14)
        let subscription = try makeSubscription(
            index: 1, status: .trial, cycleStartDay: try day(2026, 7, 27),
            reminderLeadDays: 5, trial: trial,
            cancellationURL: URL(string: "https://example.com/cancel")
        )
        await subscriptions.seed([subscription])
        return (subscription, trial)
    }

    @Test("REGRESSION (the Wave 4 gap): 'Keeping it' on a trial holds through a full reschedule in the same cycle")
    func keepingItSurvivesFullReschedule() async throws {
        let fixture = SchedulerFixture()
        let handler = fixture.handler
        let scheduler = fixture.scheduler
        let client = fixture.client
        let (subscription, trial) = try await seedTrial(fixture.subscriptions)
        let today = try day(2026, 8, 6)
        let now = try fixtureNow()
        _ = try await scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        _ = try await handler.handle(
            actionIdentifier: NotificationAction.keepingIt.rawValue,
            notificationIdentifier: NotificationPlanIdentifier.planned(
                PlannedReminder(subscriptionID: subscription.id, day: trial.cancelByDate, kind: .trialDayOfMorning)
            ),
            now: now, today: today, timeZone: torontoZone
        )
        let silenced = await client.pendingRequests()
        #expect(silenced.map { NotificationPlanIdentifier.kind(of: $0.identifier) } == [.conversionAnnouncement])

        // The Wave 4 failure mode: rescheduling is cancel-all-then-replan, and
        // without a persisted acknowledgement this very pass replans the silenced
        // escalation right back. The acknowledgement lives in the ledger now, so
        // any number of full passes must reproduce the silenced plan exactly.
        for _ in 0..<3 {
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        }
        let afterReplan = await client.pendingRequests()
        #expect(afterReplan == silenced)

        // What made it hold: the conversion charge's ledger row is acknowledged.
        let events = try await fixture.billingEvents.events(forSubscription: subscription.id)
        let conversionEvent = try #require(events.first { $0.expectedDate == trial.conversionDate })
        #expect(conversionEvent.acknowledgedAt == now)
    }

    @Test("'Keeping it' on a renewal silences that charge through a reschedule; the next cycle still reminds")
    func keepingItSilencesOneRenewalCycle() async throws {
        let fixture = SchedulerFixture()
        let handler = fixture.handler
        let scheduler = fixture.scheduler
        let client = fixture.client
        // Monthly on the 15th with a same-day reminder: the Aug 15 charge carries
        // an Aug 12 lead and an Aug 15 day-of request.
        let subscription = try makeSubscription(
            index: 2, cycleStartDay: try day(2026, 1, 15), sameDayReminder: true
        )
        await fixture.subscriptions.seed([subscription])
        let today = try day(2026, 8, 6)
        let now = try fixtureNow()
        _ = try await scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        let leadIdentifier = NotificationPlanIdentifier.planned(
            PlannedReminder(subscriptionID: subscription.id, day: try day(2026, 8, 12), kind: .renewal)
        )
        _ = try await handler.handle(
            actionIdentifier: NotificationAction.keepingIt.rawValue,
            notificationIdentifier: leadIdentifier,
            now: now, today: today, timeZone: torontoZone
        )
        _ = try await scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        let pendingDays = await client.pendingRequests()
            .filter { NotificationPlanIdentifier.subscriptionID(of: $0.identifier) == subscription.id }
            .compactMap { CalendarDay(year: $0.year, month: $0.month, day: $0.day) }
        // Nothing about Aug 15 - and September's reminders stand untouched.
        #expect(!pendingDays.contains(try day(2026, 8, 12)))
        #expect(!pendingDays.contains(try day(2026, 8, 15)))
        #expect(pendingDays.contains(try day(2026, 9, 12)))
        #expect(pendingDays.contains(try day(2026, 9, 15)))
    }

    @Test("'Keeping it' redelivered keeps the FIRST acknowledgement instant")
    func keepingItKeepsFirstAcknowledgement() async throws {
        let fixture = SchedulerFixture()
        let handler = fixture.handler
        let scheduler = fixture.scheduler
        let (subscription, trial) = try await seedTrial(fixture.subscriptions)
        let today = try day(2026, 8, 6)
        let now = try fixtureNow()
        _ = try await scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        let identifier = NotificationPlanIdentifier.planned(
            PlannedReminder(subscriptionID: subscription.id, day: trial.cancelByDate, kind: .trialDayOfMorning)
        )
        _ = try await handler.handle(
            actionIdentifier: NotificationAction.keepingIt.rawValue,
            notificationIdentifier: identifier,
            now: now, today: today, timeZone: torontoZone
        )
        _ = try await handler.handle(
            actionIdentifier: NotificationAction.keepingIt.rawValue,
            notificationIdentifier: identifier,
            now: now.addingTimeInterval(600), today: today, timeZone: torontoZone
        )

        let events = try await fixture.billingEvents.events(forSubscription: subscription.id)
        let conversionEvent = try #require(events.first { $0.expectedDate == trial.conversionDate })
        #expect(conversionEvent.acknowledgedAt == now)
    }
}
