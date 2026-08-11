import Foundation
import OttoDomain
import Testing
@testable import OttoServices

@Suite("Notification actions (spec §6.4)")
struct NotificationActionTests {

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

    @Test("'Keeping it' cancels the remaining escalation but never the conversion announcement")
    func keepingItCancelsRemainder() async throws {
        let fixture = SchedulerFixture()
        let handler = fixture.handler
        let scheduler = fixture.scheduler
        let client = fixture.client
        let subscriptions = fixture.subscriptions
        let (subscription, trial) = try await seedTrial(subscriptions)
        let today = try day(2026, 8, 6)
        let now = try fixtureNow()
        _ = try await scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        let laddered = await client.pendingRequests()
        // All five rungs: the past lead rung (Aug 3) is a §6.2 catch-up since
        // Wave 10 - its instant passed but the cancel-by deadline has not.
        #expect(laddered.count == trialLadderCap)

        let morningIdentifier = NotificationPlanIdentifier.planned(
            PlannedReminder(subscriptionID: subscription.id, day: trial.cancelByDate, kind: .trialDayOfMorning)
        )
        let followUp = try await handler.handle(
            actionIdentifier: NotificationAction.keepingIt.rawValue,
            notificationIdentifier: morningIdentifier,
            now: now, today: today, timeZone: torontoZone
        )

        #expect(followUp == .none)
        let remaining = await client.pendingRequests()
        #expect(remaining.count == 1)
        #expect(NotificationPlanIdentifier.kind(of: remaining[0].identifier) == .conversionAnnouncement)

        // Redelivery: running it again changes nothing.
        _ = try await handler.handle(
            actionIdentifier: NotificationAction.keepingIt.rawValue,
            notificationIdentifier: morningIdentifier,
            now: now, today: today, timeZone: torontoZone
        )
        #expect(await client.pendingRequests() == remaining)
    }

    @Test("'I'm cancelling' flips the status, creates the watching record, and schedules the check - once, under redelivery")
    func cancellingIsIdempotent() async throws {
        let fixture = SchedulerFixture()
        let handler = fixture.handler
        let scheduler = fixture.scheduler
        let client = fixture.client
        let subscriptions = fixture.subscriptions
        let cancellations = fixture.cancellations
        let (subscription, trial) = try await seedTrial(subscriptions)
        let today = try day(2026, 8, 6)
        let now = try fixtureNow()
        _ = try await scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        let identifier = NotificationPlanIdentifier.planned(
            PlannedReminder(subscriptionID: subscription.id, day: trial.cancelByDate, kind: .trialDayOfMorning)
        )
        let followUp = try await handler.handle(
            actionIdentifier: NotificationAction.cancelling.rawValue,
            notificationIdentifier: identifier,
            now: now, today: today, timeZone: torontoZone
        )

        #expect(followUp == .openCancellation(
            subscriptionID: subscription.id, url: URL(string: "https://example.com/cancel")
        ))
        let updated = try #require(try await subscriptions.subscription(withID: subscription.id))
        #expect(updated.storedStatus == .cancellationPending)
        let record = try #require(try await cancellations.openEpisode(forSubscription: subscription.id))
        #expect(record.verificationState == .pending)
        // The check date was computed once, now, from the effective anchor: the
        // trial's would-be conversion charge on Aug 10.
        #expect(record.nextChargeDateIfNotCancelled == trial.conversionDate)

        // The reschedule replaced the trial ladder with the verification check.
        let pending = await client.pendingRequests()
        #expect(pending.map { NotificationPlanIdentifier.kind(of: $0.identifier) } == [.verification])

        // Redelivery: same end state, no second record, no duplicate save.
        let again = try await handler.handle(
            actionIdentifier: NotificationAction.cancelling.rawValue,
            notificationIdentifier: identifier,
            now: now, today: today, timeZone: torontoZone
        )
        #expect(again == followUp)
        #expect(try await cancellations.openEpisode(forSubscription: subscription.id)?.id == record.id)
        #expect(await subscriptions.savedValues.filter { $0.id == subscription.id }.count == 1)
    }

    /// A snooze must keep the interruption level of the rung it repeats. The
    /// cancel-by day's warnings are time-sensitive so they break through Focus
    /// (spec §6.3), and "remind me later" is the user asking to be told again
    /// about that exact deadline - a repeat that a Focus mode can hold is not
    /// the reminder they asked for, and the money is unrecoverable.
    @Test("a snoozed deadline warning keeps its time-sensitive level; a snoozed ordinary rung does not gain one")
    func snoozeKeepsTheKindsInterruptionLevel() async throws {
        let fixture = SchedulerFixture()
        let (subscription, trial) = try await seedTrial(fixture.subscriptions)
        let today = try day(2026, 8, 6)
        let now = try fixtureNow()

        // The cancel-by morning rung: time-sensitive in the plan.
        #expect(PlannedReminder.Kind.trialDayOfMorning.isTimeSensitive)
        _ = try await fixture.handler.handle(
            actionIdentifier: NotificationAction.remindLater.rawValue,
            notificationIdentifier: NotificationPlanIdentifier.planned(
                PlannedReminder(
                    subscriptionID: subscription.id, day: trial.cancelByDate, kind: .trialDayOfMorning
                )
            ),
            now: now, today: today, timeZone: torontoZone
        )
        let deadlineSnooze = try #require(
            await fixture.client.pendingRequests()
                .first { NotificationPlanIdentifier.isSnooze($0.identifier) }
        )
        #expect(deadlineSnooze.isTimeSensitive)

        // And the level is derived, not blanket-applied: the lead rung is not
        // time-sensitive, so its snooze must not be either.
        #expect(!PlannedReminder.Kind.trialLead.isTimeSensitive)
        _ = try await fixture.handler.handle(
            actionIdentifier: NotificationAction.remindLater.rawValue,
            notificationIdentifier: NotificationPlanIdentifier.planned(
                PlannedReminder(
                    subscriptionID: subscription.id,
                    day: trial.cancelByDate.adding(days: -5),
                    kind: .trialLead
                )
            ),
            now: now, today: today, timeZone: torontoZone
        )
        let leadSnooze = try #require(
            await fixture.client.pendingRequests()
                .first {
                    NotificationPlanIdentifier.isSnooze($0.identifier)
                        && NotificationPlanIdentifier.kind(of: $0.identifier) == .trialLead
                }
        )
        #expect(!leadSnooze.isTimeSensitive)
    }

    @Test("'Remind me later' can never move past the cancel-by date, however often it is invoked")
    func snoozeNeverPassesCancelBy() async throws {
        let fixture = SchedulerFixture()
        let handler = fixture.handler
        let client = fixture.client
        let subscriptions = fixture.subscriptions
        let (subscription, trial) = try await seedTrial(subscriptions)
        let identifier = NotificationPlanIdentifier.planned(
            PlannedReminder(subscriptionID: subscription.id, day: trial.cancelByDate.adding(days: -5), kind: .trialLead)
        )

        // Day one: snoozing lands tomorrow (Aug 7).
        var today = try day(2026, 8, 6)
        var now = try fixtureNow()
        _ = try await handler.handle(
            actionIdentifier: NotificationAction.remindLater.rawValue,
            notificationIdentifier: identifier,
            now: now, today: today, timeZone: torontoZone
        )
        var snoozes = await client.pendingRequests().filter { NotificationPlanIdentifier.isSnooze($0.identifier) }
        #expect(snoozes.map { CalendarDay(year: $0.year, month: $0.month, day: $0.day) } == [try day(2026, 8, 7)])

        // From Aug 7, and again from Aug 8 (the deadline), and once more: the
        // snooze pins to Aug 8 and never crosses it. Aug 8's own snooze falls to
        // the evening slot because 09:00 is already the snoozing user's past.
        for dayOffset in 1...3 {
            today = try day(2026, 8, 6).adding(days: min(dayOffset, 2))
            now = try #require(Calendar.gregorianDate(
                year: today.year, month: today.month, day: today.day, hour: 10, in: torontoZone
            ))
            _ = try await handler.handle(
                actionIdentifier: NotificationAction.remindLater.rawValue,
                notificationIdentifier: identifier,
                now: now, today: today, timeZone: torontoZone
            )
            snoozes = await client.pendingRequests().filter { NotificationPlanIdentifier.isSnooze($0.identifier) }
            let latest = try #require(snoozes.compactMap {
                CalendarDay(year: $0.year, month: $0.month, day: $0.day)
            }.max())
            #expect(latest <= trial.cancelByDate)
        }
    }

    @Test("snoozing a snooze still knows its deadline - the kind rides in the identifier")
    func snoozedSnoozeKeepsItsCap() async throws {
        let fixture = SchedulerFixture()
        let handler = fixture.handler
        let client = fixture.client
        let subscriptions = fixture.subscriptions
        let (subscription, trial) = try await seedTrial(subscriptions)

        // Snooze the original reminder on the deadline day at 08:00: the target
        // is the deadline itself, still ahead of the preferred hour.
        let deadline = trial.cancelByDate
        let dayBefore = deadline.adding(days: -1)
        let originalIdentifier = NotificationPlanIdentifier.planned(
            PlannedReminder(subscriptionID: subscription.id, day: dayBefore, kind: .trialDayOfMorning)
        )
        var now = try #require(Calendar.gregorianDate(
            year: dayBefore.year, month: dayBefore.month, day: dayBefore.day, hour: 10, in: torontoZone
        ))
        _ = try await handler.handle(
            actionIdentifier: NotificationAction.remindLater.rawValue,
            notificationIdentifier: originalIdentifier,
            now: now, today: dayBefore, timeZone: torontoZone
        )
        let snooze = try #require(await client.pendingRequests().first {
            NotificationPlanIdentifier.isSnooze($0.identifier)
        })
        #expect(CalendarDay(year: snooze.year, month: snooze.month, day: snooze.day) == deadline)

        // Now snooze the SNOOZE on the deadline day: it must pin, not escape.
        now = try #require(Calendar.gregorianDate(
            year: deadline.year, month: deadline.month, day: deadline.day, hour: 8, in: torontoZone
        ))
        _ = try await handler.handle(
            actionIdentifier: NotificationAction.remindLater.rawValue,
            notificationIdentifier: snooze.identifier,
            now: now, today: deadline, timeZone: torontoZone
        )
        let daysAfter = await client.pendingRequests()
            .filter { NotificationPlanIdentifier.isSnooze($0.identifier) }
            .compactMap { CalendarDay(year: $0.year, month: $0.month, day: $0.day) }
        #expect(daysAfter.allSatisfy { $0 <= deadline })
    }

    @Test("a plain tap routes to the subscription's detail")
    func tapOpensDetail() async throws {
        let fixture = SchedulerFixture()
        let handler = fixture.handler
        let subscriptions = fixture.subscriptions
        let (subscription, trial) = try await seedTrial(subscriptions)
        let identifier = NotificationPlanIdentifier.planned(
            PlannedReminder(subscriptionID: subscription.id, day: trial.cancelByDate, kind: .trialDayOfMorning)
        )
        let followUp = try await handler.handle(
            actionIdentifier: "",
            notificationIdentifier: identifier,
            now: try fixtureNow(), today: try day(2026, 8, 6), timeZone: torontoZone
        )
        #expect(followUp == .openDetail(subscriptionID: subscription.id))
    }
}

// The §7.3 usage check-in responses (Wave 7): "still using it" is a background
// fact-record; "not really" opens the facts and performs nothing - what to do
// about an unused subscription is the user's decision, never Otto's.
@Suite("Usage check-in actions (spec §7.3)")
struct UsageCheckInActionTests {

    @Test("'Yes - still using it' records today as the last use, idempotently")
    func stillUsingRecordsUse() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await fixture.subscriptions.seed([subscription])
        let today = try day(2026, 8, 6)
        let identifier = NotificationPlanIdentifier.planned(
            PlannedReminder(subscriptionID: subscription.id, day: today, kind: .usageCheckIn)
        )

        let followUp = try await fixture.handler.handle(
            actionIdentifier: NotificationAction.stillUsing.rawValue,
            notificationIdentifier: identifier,
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )

        #expect(followUp == .none)
        let stored = try #require(try await fixture.subscriptions.subscription(withID: subscription.id))
        #expect(stored.lastUsedDate == today)

        // Redelivery: same day, same fact, one write's worth of state.
        _ = try await fixture.handler.handle(
            actionIdentifier: NotificationAction.stillUsing.rawValue,
            notificationIdentifier: identifier,
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )
        #expect(try await fixture.subscriptions.subscription(withID: subscription.id)?.lastUsedDate == today)
    }

    @Test("'Not really' opens the subscription and changes nothing")
    func notUsingOpensDetail() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        await fixture.subscriptions.seed([subscription])
        let identifier = NotificationPlanIdentifier.planned(
            PlannedReminder(subscriptionID: subscription.id, day: try day(2026, 8, 6), kind: .usageCheckIn)
        )

        let followUp = try await fixture.handler.handle(
            actionIdentifier: NotificationAction.notUsing.rawValue,
            notificationIdentifier: identifier,
            now: try fixtureNow(), today: try day(2026, 8, 6), timeZone: torontoZone
        )

        #expect(followUp == .openDetail(subscriptionID: subscription.id))
        let stored = try #require(try await fixture.subscriptions.subscription(withID: subscription.id))
        #expect(stored.lastUsedDate == nil)
    }

    @Test("usage check-ins carry the usage category so the buttons actually appear")
    func usageCategoryAssigned() async throws {
        #expect(NotificationCategory.identifier(for: .usageCheckIn) == NotificationCategory.usage)
    }
}
