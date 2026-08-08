import Foundation
import OttoDomain
import Testing
@testable import OttoServices

@Suite("Notification scheduler (spec §6.1, §6.2)")
struct NotificationSchedulerTests {

    @Test("scheduling twice produces byte-identical pending requests - no duplicates, no drift")
    func idempotency() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: today, lengthDays: 14)
        try await subscriptions.seed([
            makeSubscription(index: 1, status: .trial, cycleStartDay: today, trial: trial),
            makeSubscription(index: 2, cycleStartDay: try day(2026, 7, 15)),
            makeSubscription(index: 3, status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEndsOn: try day(2026, 9, 1))
        ])
        let now = try fixtureNow()

        _ = try await scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        let first = await client.pendingRequests()
        _ = try await scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        let second = await client.pendingRequests()

        #expect(first == second)
        #expect(!first.isEmpty)
        #expect(Set(first.map(\.identifier)).count == first.count)
    }

    @Test("the 200-subscription fixture ends at exactly 64 pending with every P1 present and truncation surfaced")
    func slotBudgetEndToEnd() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 6)
        var seeded: [Subscription] = []
        for index in 0..<10 {
            let start = today.adding(days: -(index % 3))
            let trial = try makeTrialTerm(index: 400 + index, startDate: start, lengthDays: 14)
            seeded.append(try makeSubscription(
                index: index, status: .trial, cycleStartDay: start, reminderLeadDays: 5, trial: trial
            ))
        }
        for index in 10..<200 {
            seeded.append(try makeSubscription(
                index: index,
                cycleStartDay: today.adding(days: -(320 + index)),
                lastUsedDate: today.adding(days: -1)
            ))
        }
        try await subscriptions.seed(seeded)

        let outcome = try await scheduler.reschedule(
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )
        let pending = await client.pendingRequests()

        #expect(pending.count == 64)
        #expect(outcome.scheduledCount == 64)

        // Every trial rung of all ten trials survived the cut.
        let trialKinds: Set<PlannedReminder.Kind> = [
            .trialLead, .trialDayOfMorning, .trialDayOfEvening, .trialDaily, .conversionAnnouncement
        ]
        let pendingTrialCount = pending.filter {
            NotificationPlanIdentifier.kind(of: $0.identifier).map(trialKinds.contains) ?? false
        }.count
        #expect(pendingTrialCount == 10 * trialLadderCap)

        // The cut exists, is surfaced, and coverage claims stop at it.
        let truncatedAfter = try #require(outcome.truncatedAfter)
        #expect(outcome.coveredThrough == truncatedAfter)
        #expect(truncatedAfter < today.adding(days: 90))

        // Renewals dropped furthest-first: every pending renewal day is at or
        // before the truncation boundary's next day.
        let pendingRenewalDays = pending
            .filter { NotificationPlanIdentifier.kind(of: $0.identifier) == .renewal }
            .compactMap { CalendarDay(year: $0.year, month: $0.month, day: $0.day) }
        let furthestKept = try #require(pendingRenewalDays.max())
        #expect(furthestKept <= truncatedAfter.adding(days: 1))
    }

    @Test("the catch-up case: added two days before the charge with a 3-day lead fires now, not never")
    func catchUp() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 6)
        // Mode B: next charge Aug 8, entered today. The lead day (Aug 5) is gone.
        try await subscriptions.seed([
            makeSubscription(index: 1, cycleStartDay: try day(2026, 8, 8), reminderLeadDays: 3)
        ])

        _ = try await scheduler.reschedule(now: try fixtureNow(), today: today, timeZone: torontoZone)
        let pending = await client.pendingRequests()

        // The rung keeps its original day (Aug 5) so its identifier is stable;
        // delivery is immediate because that instant has passed (Wave 10, §6.2).
        let catchUp = try #require(pending.first {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .renewal
                && CalendarDay(year: $0.year, month: $0.month, day: $0.day) == (try? day(2026, 8, 5))
        })
        #expect(catchUp.catchUpIntervalSeconds == NotificationScheduler.catchUpIntervalSeconds)
    }

    @Test("a reminder for today whose hour already passed becomes a §6.2 catch-up, not silence (Wave 10)")
    func passedHourBecomesCatchUp() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 6)
        try await subscriptions.seed([
            makeSubscription(index: 1, cycleStartDay: try day(2026, 8, 8), reminderLeadDays: 3)
        ])

        // 10:00 - an hour past the preferred fire time. The charge is still
        // two days ahead: the warning fires now, by interval trigger, because
        // a calendar trigger in the past never fires and the old code dropped
        // the rung entirely - §6.2's motivating case, unimplemented since v1.1.
        let lateNow = try #require(Calendar.gregorianDate(
            year: 2026, month: 8, day: 6, hour: 10, in: torontoZone
        ))
        _ = try await scheduler.reschedule(now: lateNow, today: today, timeZone: torontoZone)
        let pending = await client.pendingRequests()

        let catchUp = try #require(pending.first {
            $0.catchUpIntervalSeconds != nil
        })
        #expect(catchUp.catchUpIntervalSeconds == NotificationScheduler.catchUpIntervalSeconds)
        #expect(NotificationPlanIdentifier.kind(of: catchUp.identifier) == .renewal)
    }

    @Test("⭐ the conversion announcement is pending, correctly dated, with the app never opened again")
    func conversionAnnouncementPreScheduled() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 6)
        // The FoodApp case: a 14-day trial added today, converting Aug 20 to
        // $11.00/month.
        let trial = try makeTrialTerm(startDate: today, lengthDays: 14, convertsToAmountCents: 1100)
        try await subscriptions.seed([
            makeSubscription(index: 1, status: .trial, cycleStartDay: today, reminderLeadDays: 5, trial: trial)
        ])

        // The ONLY scheduler run happens at creation. The app is then never
        // foregrounded again; nothing else may need to run.
        _ = try await scheduler.reschedule(now: try fixtureNow(), today: today, timeZone: torontoZone)
        let pending = await client.pendingRequests()

        let announcement = try #require(pending.first {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .conversionAnnouncement
        })
        #expect(CalendarDay(year: announcement.year, month: announcement.month, day: announcement.day)
            == trial.conversionDate)
        #expect(announcement.isTimeSensitive)
        #expect(announcement.body == "Your FoodApp trial converted today. You're now being charged $11.00/month.")
    }

    @Test("⭐ the HARD case: trial entered ON the cancel-by day at 10:03 - the whole remaining ladder lands in one run")
    func gateHardCaseCreatedOnCancelByDayAfterFireHour() async throws {
        // The field scenario the gate fixture never modeled (Wave 10, defect
        // D): cancel-by IS today and the first scheduler pass runs AFTER the
        // fire hour. The easy fixture (cancel-by 12 days out, 08:00) shipped
        // defect A through a green gate; this fixture is why it cannot again.
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 25), lengthDays: 14, bufferDays: 2)
        #expect(trial.cancelByDate == today)
        try await subscriptions.seed([
            makeSubscription(index: 1, status: .trial, cycleStartDay: try day(2026, 7, 25), trial: trial)
        ])

        // The ONLY scheduler run happens at entry, 10:03 - an hour past the
        // morning rung. The app is then never foregrounded again.
        let entry = try #require(Calendar.gregorianDate(
            year: 2026, month: 8, day: 6, hour: 10, in: torontoZone
        ))
        _ = try await scheduler.reschedule(now: entry, today: today, timeZone: torontoZone)
        let pending = await client.pendingRequests()

        // The morning warning fires NOW - its hour is gone but the deadline is
        // tonight - and it breaks through Focus.
        let morning = try #require(pending.first {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .trialDayOfMorning
        })
        #expect(morning.catchUpIntervalSeconds == NotificationScheduler.catchUpIntervalSeconds)
        #expect(morning.isTimeSensitive)
        // The evening last-call is still ahead as an ordinary calendar rung.
        let evening = try #require(pending.first {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .trialDayOfEvening
        })
        #expect(evening.catchUpIntervalSeconds == nil)
        #expect((evening.hour, evening.minute) == (19, 0))
        // The daily escalation and the announcement are pre-scheduled; money
        // moves Aug 8 and the statement of that fact needs no further run.
        #expect(pending.contains { NotificationPlanIdentifier.kind(of: $0.identifier) == .trialDaily })
        let announcement = try #require(pending.first {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .conversionAnnouncement
        })
        #expect(CalendarDay(year: announcement.year, month: announcement.month, day: announcement.day)
            == trial.conversionDate)
        #expect(announcement.catchUpIntervalSeconds == nil)
        #expect(announcement.isTimeSensitive)
    }

    @Test("⭐ the announcement survives a conversion-morning reschedule with the status flip never persisted")
    func conversionAnnouncementSurvivesDerivedPath() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let start = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: start, lengthDays: 14, convertsToAmountCents: 1100)
        // The stored status still says .trial - no flow ever persisted a flip.
        try await subscriptions.seed([
            makeSubscription(index: 1, status: .trial, cycleStartDay: start, reminderLeadDays: 5, trial: trial)
        ])

        // The app happens to run at 08:00 on the conversion morning - a full
        // cancel-and-replan pass, exercising §5.2a's derivation: the plan must
        // come out of the ACTIVE branch (stored status untouched) and still
        // carry today's announcement.
        let conversionDay = trial.conversionDate
        let conversionMorning = try #require(Calendar.gregorianDate(
            year: conversionDay.year, month: conversionDay.month, day: conversionDay.day,
            hour: 8, in: torontoZone
        ))
        _ = try await scheduler.reschedule(now: conversionMorning, today: conversionDay, timeZone: torontoZone)
        let pending = await client.pendingRequests()

        let announcement = try #require(pending.first {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .conversionAnnouncement
        })
        #expect(CalendarDay(year: announcement.year, month: announcement.month, day: announcement.day)
            == conversionDay)
        // And the paid sequence's renewal reminders are pending alongside it,
        // anchored at the conversion date - all derived, nothing persisted.
        let renewalDays = pending
            .filter { NotificationPlanIdentifier.kind(of: $0.identifier) == .renewal }
            .compactMap { CalendarDay(year: $0.year, month: $0.month, day: $0.day) }
        let firstPaidRenewalWarning = nextBillingDate(
            after: conversionDay, anchor: conversionDay, cycle: .monthly
        ).adding(days: -5)
        #expect(renewalDays.contains(firstPaidRenewalWarning))
    }

    @Test("a timezone change reschedules to identical calendar days and wall-clock hours")
    func timezoneChangeKeepsDays() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: today, lengthDays: 14)
        try await subscriptions.seed([
            makeSubscription(index: 1, status: .trial, cycleStartDay: today, trial: trial),
            makeSubscription(index: 2, cycleStartDay: try day(2026, 7, 15))
        ])
        let now = try fixtureNow()

        _ = try await scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        let beforeFlight = await client.pendingRequests()

        let vancouver = try #require(TimeZone(identifier: "America/Vancouver"))
        _ = try await scheduler.reschedule(now: now, today: today, timeZone: vancouver)
        let afterFlight = await client.pendingRequests()

        // The trigger components are wall-clock values, so the entire spec is
        // identical - the day never moved (spec §4.1); only the instant those
        // components resolve to changed, and that resolution happens at delivery.
        #expect(beforeFlight == afterFlight)
    }

    @Test("denied permission is a distinct, surfaced state - and nothing pretends to schedule")
    func deniedPermission() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 6)
        try await subscriptions.seed([
            makeSubscription(index: 1, cycleStartDay: try day(2026, 7, 15))
        ])
        await client.setPermission(.denied)

        let outcome = try await scheduler.reschedule(
            now: try fixtureNow(), today: today, timeZone: torontoZone
        )

        #expect(outcome.permission == .denied)
        #expect(outcome.scheduledCount == 0)
        #expect(await client.pendingRequests().isEmpty)
    }

    @Test("ledger upkeep runs per subscription at scheduling time: invalidate, then materialize")
    func ledgerUpkeep() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, subscriptions, billingEvents) = (fixture.scheduler, fixture.subscriptions, fixture.billingEvents)
        let today = try day(2026, 8, 6)
        try await subscriptions.seed([
            makeSubscription(index: 1, cycleStartDay: try day(2026, 7, 15)),
            makeSubscription(index: 2, cycleStartDay: try day(2026, 7, 20))
        ])

        _ = try await scheduler.reschedule(now: try fixtureNow(), today: today, timeZone: torontoZone)

        #expect(await billingEvents.invalidateCalls.count == 2)
        #expect(await billingEvents.materializeCalls.count == 2)
    }

    @Test("an existing snooze survives the full reschedule and shrinks the budget beneath it")
    func snoozeSurvivesReschedule() async throws {
        let fixture = SchedulerFixture()
        let (scheduler, client, subscriptions) = (fixture.scheduler, fixture.client, fixture.subscriptions)
        let today = try day(2026, 8, 6)
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 7, 15))
        try await subscriptions.seed([subscription])

        let snoozeIdentifier = NotificationPlanIdentifier.snooze(
            subscriptionID: subscription.id, day: try day(2026, 8, 7), of: .renewal
        )
        try await client.add(NotificationRequestSpec(
            identifier: snoozeIdentifier, title: "t", body: "b",
            year: 2026, month: 8, day: 7, hour: 9, minute: 0,
            isTimeSensitive: false, categoryIdentifier: ""
        ))

        _ = try await scheduler.reschedule(now: try fixtureNow(), today: today, timeZone: torontoZone)
        let pending = await client.pendingRequests()

        #expect(pending.contains { $0.identifier == snoozeIdentifier })
    }
}

extension Calendar {
    /// A specific local wall-clock instant, for tests that care about hours.
    static func gregorianDate(year: Int, month: Int, day: Int, hour: Int, in timeZone: TimeZone) -> Date? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        return gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }
}
