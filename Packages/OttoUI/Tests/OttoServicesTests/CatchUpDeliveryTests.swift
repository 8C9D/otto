import Foundation
import OttoDomain
import Testing
@testable import OttoServices

// Wave 10, defect A: §6.2's "schedule it immediately" had never been
// implemented for any kind - the codebase contained zero interval triggers,
// the planner's window filter silently discarded past trial rungs, and the
// scheduler dropped passed-hour rungs with a comment claiming §6.2 would
// recover them. These tests pin the catch-up's behavior AND its boundaries:
// fire when the instant passed but the protected deadline is ahead, never
// when the deadline is behind, and never twice.

@Suite("§6.2 immediate delivery (Wave 10, defect A)")
struct CatchUpDeliveryTests {

    private func at(
        _ target: CalendarDay, hour: Int, minute: Int = 0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = torontoZone
        return try #require(gregorian.date(from: DateComponents(
            year: target.year, month: target.month, day: target.day, hour: hour, minute: minute
        )), sourceLocation: sourceLocation)
    }

    private func catchUps(_ fixture: SchedulerFixture) async -> [NotificationRequestSpec] {
        await fixture.client.pendingRequests().filter { $0.catchUpIntervalSeconds != nil }
    }

    @Test("⛔ §6.2's motivating case: added at 10:03 with the lead rung due 09:00 today - fires immediately")
    func modeBEntryAtTenOhThree() async throws {
        let fixture = SchedulerFixture()
        let today = try day(2026, 8, 6)
        // Mode B: next charge Aug 9, 3-day lead - the warning day is today and
        // its hour is an hour gone.
        await fixture.subscriptions.seed([
            try makeSubscription(index: 1, cycleStartDay: try day(2026, 8, 9), reminderLeadDays: 3)
        ])

        _ = try await fixture.scheduler.reschedule(
            now: try at(today, hour: 10, minute: 3), today: today, timeZone: torontoZone
        )

        let catchUp = try #require(await catchUps(fixture).first)
        #expect(NotificationPlanIdentifier.kind(of: catchUp.identifier) == .renewal)
        #expect(catchUp.catchUpIntervalSeconds == NotificationScheduler.catchUpIntervalSeconds)
        #expect(CalendarDay(year: catchUp.year, month: catchUp.month, day: catchUp.day) == today)
    }

    @Test("a catch-up keeps its identifier across passes and days - no fresh warning minted daily")
    func catchUpIdentifierIsStable() async throws {
        let fixture = SchedulerFixture()
        // Charge Aug 9, 5-day lead: the rung's own day is Aug 4, already past
        // when the subscription is entered Aug 6.
        await fixture.subscriptions.seed([
            try makeSubscription(index: 1, cycleStartDay: try day(2026, 8, 9), reminderLeadDays: 5)
        ])
        let entryDay = try day(2026, 8, 6)
        _ = try await fixture.scheduler.reschedule(
            now: try at(entryDay, hour: 10, minute: 3), today: entryDay, timeZone: torontoZone
        )
        let first = try #require(await catchUps(fixture).first)
        #expect(CalendarDay(year: first.year, month: first.month, day: first.day) == (try day(2026, 8, 4)))

        // The next day's pass computes the SAME rung - same identifier, byte
        // identical - so once it is in the delivery record it never re-fires.
        let nextDay = try day(2026, 8, 7)
        _ = try await fixture.scheduler.reschedule(
            now: try at(nextDay, hour: 8), today: nextDay, timeZone: torontoZone
        )
        let second = try #require(await catchUps(fixture).first)
        #expect(second == first)
        #expect(await catchUps(fixture).count == 1)
    }

    @Test("⛔ a trial-lead rung in the past with the deadline ahead fires immediately")
    func pastTrialLeadWithDeadlineAheadFiresNow() async throws {
        let fixture = SchedulerFixture()
        // Trial entered late: cancel-by tomorrow, conversion in 3 days. The
        // 3-day lead rung was due two days ago - before the planner's window -
        // and was silently discarded by the window filter since v1.4.
        let today = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 26), lengthDays: 14, bufferDays: 2)
        #expect(trial.cancelByDate == (try day(2026, 8, 7)))
        await fixture.subscriptions.seed([
            try makeSubscription(
                index: 1, status: .trial, cycleStartDay: try day(2026, 7, 26), trial: trial
            )
        ])

        _ = try await fixture.scheduler.reschedule(
            now: try at(today, hour: 10, minute: 3), today: today, timeZone: torontoZone
        )

        // The rung keeps its original day (Aug 4) for the stable identifier;
        // delivery is immediate regardless.
        let lead = try #require(await catchUps(fixture).first {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .trialLead
        })
        #expect(CalendarDay(year: lead.year, month: lead.month, day: lead.day) == (try day(2026, 8, 4)))
    }

    @Test("⛔ a trial-lead rung in the past with conversion BEHIND stays dropped - no dead-deadline nag")
    func pastTrialLeadWithConversionBehindStaysDropped() async throws {
        let fixture = SchedulerFixture()
        // Conversion was Aug 3; today is Aug 6. The announcement owned Aug 3
        // (§6.3), and a notification saying "cancel by <July date>" now would
        // be the dishonesty v1.4 legislated against. The planner's effective
        // status makes this structural: a converted trial plans NO trial rungs.
        let today = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 20), lengthDays: 14, bufferDays: 2)
        #expect(trial.conversionDate == (try day(2026, 8, 3)))
        await fixture.subscriptions.seed([
            try makeSubscription(
                index: 1, status: .trial, cycleStartDay: try day(2026, 7, 20), trial: trial
            )
        ])

        _ = try await fixture.scheduler.reschedule(
            now: try at(today, hour: 10, minute: 3), today: today, timeZone: torontoZone
        )

        let trialKinds: Set<PlannedReminder.Kind> = [
            .trialLead, .trialDayOfMorning, .trialDayOfEvening, .trialDaily, .conversionAnnouncement
        ]
        let pendingTrialRungs = await fixture.client.pendingRequests().filter {
            NotificationPlanIdentifier.kind(of: $0.identifier).map(trialKinds.contains) ?? false
        }
        #expect(pendingTrialRungs.isEmpty)
    }

    @Test("⛔ the D case: trial created ON the cancel-by day after the fire hour - the ladder fires today")
    func createdOnCancelByDayAfterFireHour() async throws {
        let fixture = SchedulerFixture()
        // The field scenario the gate fixture never modeled: cancel-by IS
        // today and the first scheduler pass runs at 10:03. The morning rung's
        // hour is gone - it fires immediately; the evening rung is still ahead
        // as a normal calendar trigger.
        let today = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 25), lengthDays: 14, bufferDays: 2)
        #expect(trial.cancelByDate == today)
        await fixture.subscriptions.seed([
            try makeSubscription(
                index: 1, status: .trial, cycleStartDay: try day(2026, 7, 25), trial: trial
            )
        ])

        _ = try await fixture.scheduler.reschedule(
            now: try at(today, hour: 10, minute: 3), today: today, timeZone: torontoZone
        )

        let pending = await fixture.client.pendingRequests()
        let morning = try #require(pending.first {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .trialDayOfMorning
        })
        #expect(morning.catchUpIntervalSeconds == NotificationScheduler.catchUpIntervalSeconds)
        #expect(morning.isTimeSensitive)
        let evening = try #require(pending.first {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .trialDayOfEvening
        })
        #expect(evening.catchUpIntervalSeconds == nil)
        #expect(evening.hour == 19)
    }

    @Test("⛔ conversion day, first pass at 09:01: the announcement fires immediately")
    func conversionDayAfterNineAnnouncesNow() async throws {
        let fixture = SchedulerFixture()
        let today = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 23), lengthDays: 14)
        #expect(trial.conversionDate == today)
        await fixture.subscriptions.seed([
            try makeSubscription(
                index: 1, status: .trial, cycleStartDay: try day(2026, 7, 23), trial: trial
            )
        ])

        _ = try await fixture.scheduler.reschedule(
            now: try at(today, hour: 9, minute: 1), today: today, timeZone: torontoZone
        )

        let announcement = try #require(await catchUps(fixture).first {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .conversionAnnouncement
        })
        #expect(announcement.isTimeSensitive)
    }

    @Test("⛔ an already-delivered identifier is never re-scheduled - the system's record, not a flag")
    func deliveredCatchUpIsNotRescheduled() async throws {
        let fixture = SchedulerFixture()
        let today = try day(2026, 8, 6)
        let subscription = try makeSubscription(
            index: 1, cycleStartDay: try day(2026, 8, 9), reminderLeadDays: 3
        )
        await fixture.subscriptions.seed([subscription])
        let now = try at(today, hour: 10, minute: 3)

        // First pass schedules the catch-up; iOS delivers it seconds later,
        // which moves it from pending to delivered.
        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        let identifier = try #require(await catchUps(fixture).first?.identifier)
        await fixture.client.removePendingRequests(withIdentifiers: [identifier])
        await fixture.client.seedDelivered([identifier])

        // A later pass the same day - a foreground, an action, a timezone
        // change - must not fire the same warning twice.
        _ = try await fixture.scheduler.reschedule(
            now: try at(today, hour: 14), today: today, timeZone: torontoZone
        )

        #expect(await !fixture.client.pendingRequests().map(\.identifier).contains(identifier))
    }

    @Test("catch-ups occupy real budget slots and P1 catch-ups survive the cut")
    func catchUpsAreBudgeted() async throws {
        let fixture = SchedulerFixture()
        let today = try day(2026, 8, 6)
        var seeded: [Subscription] = []
        // One late-entered trial whose lead rung is a P1 catch-up...
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 26), lengthDays: 14, bufferDays: 2)
        seeded.append(try makeSubscription(
            index: 0, status: .trial, cycleStartDay: try day(2026, 7, 26), trial: trial
        ))
        // ...plus enough renewals, each with a catch-up due today, to overflow
        // the 64-slot budget several times over.
        for index in 1..<100 {
            seeded.append(try makeSubscription(
                index: index, cycleStartDay: today.adding(days: 2 - 31 * (index % 2)),
                reminderLeadDays: 3
            ))
        }
        await fixture.subscriptions.seed(seeded)

        let outcome = try await fixture.scheduler.reschedule(
            now: try at(today, hour: 10, minute: 3), today: today, timeZone: torontoZone
        )

        let pending = await fixture.client.pendingRequests()
        #expect(pending.count <= 64)
        #expect(outcome.truncatedAfter != nil)
        // The P1 trial catch-up outranked renewal rungs for its slot.
        #expect(await catchUps(fixture).contains {
            NotificationPlanIdentifier.kind(of: $0.identifier) == .trialLead
        })
    }
}
