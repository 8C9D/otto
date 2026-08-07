import Foundation
import Testing
import OttoDomain

@Suite("Reminder schedule (spec §6.3)")
struct ReminderScheduleTests {

    @Test("an active subscription gets a lead-time reminder per billing date plus usage check-ins")
    func activeMonthly() throws {
        let sub = try makeSubscription(status: .active, cycle: .monthly, cycleStartDay: try day(2026, 7, 15))
        let today = try day(2026, 8, 6)

        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)

        // Billing dates Aug 15, Sep 15, Oct 15 with a 3-day lead; Nov 15's reminder
        // (Nov 12) falls past the horizon end of Nov 4. The usage check-in lands
        // 90 days after the Jul 15 anchor because no use was ever recorded.
        let expected = [
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 8, 12), kind: .renewal),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 9, 12), kind: .renewal),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 10, 12), kind: .renewal),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 10, 13), kind: .usageCheckIn)
        ]
        #expect(planned == expected)
    }

    @Test("a trial gets the full five-rung ladder ending in the conversion announcement, all at P1")
    func trialLadder() throws {
        let start = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: start, lengthDays: 7)
        let sub = try makeSubscription(
            status: .trial, cycle: .monthly, cycleStartDay: start, reminderLeadDays: 5, trial: trial
        )

        let planned = reminderSchedule(for: sub, from: start, horizonDays: 90)

        // Cancel-by is Aug 11, conversion Aug 13; the lead reminder lands on today
        // itself and is kept - whether today's fire time has passed is the
        // scheduler's problem, not the planner's. The default 2-day buffer yields
        // exactly the cap: lead, morning, evening, one daily, announcement.
        let aug11 = try day(2026, 8, 11)
        let expected = Set([
            PlannedReminder(subscriptionID: sub.id, day: start, kind: .trialLead),
            PlannedReminder(subscriptionID: sub.id, day: aug11, kind: .trialDayOfMorning),
            PlannedReminder(subscriptionID: sub.id, day: aug11, kind: .trialDayOfEvening),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 8, 12), kind: .trialDaily),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 8, 13), kind: .conversionAnnouncement)
        ])
        #expect(Set(planned) == expected)
        #expect(planned.count == trialLadderCap)
        #expect(planned.allSatisfy { $0.priority == .trial })
    }

    @Test("a long buffer keeps the dailies nearest conversion and never exceeds the cap of 5")
    func trialLadderCapped() throws {
        let start = try day(2026, 8, 6)
        // 30-day trial with a 10-day buffer: cancel-by Aug 26, conversion Sep 5,
        // nine candidate dailies Aug 27 - Sep 4.
        let trial = try makeTrialTerm(startDate: start, lengthDays: 30, bufferDays: 10)
        let sub = try makeSubscription(
            status: .trial, cycle: .monthly, cycleStartDay: start, reminderLeadDays: 5, trial: trial
        )

        let planned = reminderSchedule(for: sub, from: start, horizonDays: 90)

        #expect(planned.count == trialLadderCap)
        // The named rungs always survive; the one surviving daily is the last call
        // before conversion, because proximity to the deadline is what escalation
        // is for.
        let dailies = planned.filter { $0.kind == .trialDaily }
        #expect(dailies.map(\.day) == [try day(2026, 9, 4)])
        let conversionDay = try day(2026, 9, 5)
        #expect(planned.contains { $0.kind == .conversionAnnouncement && $0.day == conversionDay })
    }

    @Test("on the conversion day itself the announcement survives a reschedule (spec §5.2a)")
    func conversionDayAnnouncementSurvivesReschedule() throws {
        let start = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: start, lengthDays: 7)
        let sub = try makeSubscription(
            status: .trial, cycle: .monthly, cycleStartDay: start, reminderLeadDays: 5, trial: trial
        )

        // A scheduler run on the conversion morning cancels every pending request;
        // if the plan for that day omitted the announcement, it would be cancelled
        // hours before its fire time and never replaced.
        let conversionDay = try day(2026, 8, 13)
        let planned = reminderSchedule(for: sub, from: conversionDay, horizonDays: 90)

        #expect(planned.contains(
            PlannedReminder(subscriptionID: sub.id, day: conversionDay, kind: .conversionAnnouncement)
        ))
        // And the paid sequence is already planned alongside it.
        #expect(planned.contains { $0.kind == .renewal })
    }

    @Test("the day after conversion there is no announcement - only the paid sequence")
    func noLateAnnouncement() throws {
        let start = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: start, lengthDays: 7)
        let sub = try makeSubscription(
            status: .trial, cycle: .monthly, cycleStartDay: start, reminderLeadDays: 5, trial: trial
        )

        let planned = reminderSchedule(for: sub, from: try day(2026, 8, 14), horizonDays: 90)

        #expect(!planned.contains { $0.kind == .conversionAnnouncement })
    }

    @Test("the catch-up rule: a charge still ahead whose lead day passed gets a reminder today (spec §6.2)")
    func catchUpReminder() throws {
        // The Mode B onboarding case: added two days before the charge, 3-day lead.
        let sub = try makeSubscription(status: .active, cycle: .monthly, cycleStartDay: try day(2026, 8, 8))
        let today = try day(2026, 8, 6)

        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)

        #expect(planned.contains(PlannedReminder(subscriptionID: sub.id, day: today, kind: .renewal)))
    }

    @Test("the same-day reminder fires on each billing date when enabled, and only then")
    func sameDayReminders() throws {
        var sub = try makeSubscription(status: .active, cycle: .monthly, cycleStartDay: try day(2026, 7, 15))
        let today = try day(2026, 8, 6)

        #expect(!reminderSchedule(for: sub, from: today, horizonDays: 90)
            .contains { $0.kind == .renewalDayOf })

        sub.sameDayReminder = true
        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)
        let sameDay = planned.filter { $0.kind == .renewalDayOf }.map(\.day)
        // Nov 15 falls past the Nov 4 horizon end, so its same-day reminder does too.
        #expect(sameDay == [try day(2026, 8, 15), try day(2026, 9, 15), try day(2026, 10, 15)])
    }

    @Test("a pause ending inside the lead window still warns - today, not silently never")
    func pauseEndingCatchUp() throws {
        let sub = try makeSubscription(
            status: .paused,
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 5,
            pauseEndsOn: try day(2026, 8, 8)
        )
        let today = try day(2026, 8, 6)

        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)

        #expect(planned == [PlannedReminder(subscriptionID: sub.id, day: today, kind: .pauseEnding)])
    }

    @Test("a converted trial plans like the active subscription it now is, anchored at conversion (spec §5.2a)")
    func convertedTrialPlansAsActive() throws {
        let start = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: start, lengthDays: 7)
        let sub = try makeSubscription(
            status: .trial, cycle: .monthly, cycleStartDay: start, reminderLeadDays: 5, trial: trial
        )

        // Conversion was Aug 13; today is a week later and nothing ever persisted a
        // status flip. The paid sequence runs from the conversion date regardless:
        // renewals on the 13th, warned 5 days ahead, plus the 90-day usage check-in
        // counted from conversion.
        let today = try day(2026, 8, 20)
        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)

        let expected = Set([
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 9, 8), kind: .renewal),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 10, 8), kind: .renewal),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 11, 8), kind: .renewal),
            PlannedReminder(subscriptionID: sub.id, day: try day(2026, 11, 11), kind: .usageCheckIn)
        ])
        #expect(Set(planned) == expected)
        #expect(planned.contains { $0.priority == .trial } == false)
    }

    @Test("a paused subscription gets only a resume warning ahead of pauseEndsOn")
    func pausedWithResumeDate() throws {
        let sub = try makeSubscription(
            status: .paused,
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            pauseEndsOn: try day(2026, 9, 1)
        )
        let today = try day(2026, 8, 6)

        let planned = reminderSchedule(for: sub, from: today, horizonDays: 90)

        let aug29 = try day(2026, 8, 29)
        #expect(planned.map(\.day) == [aug29])
        #expect(planned.map(\.kind) == [.pauseEnding])
        #expect(planned.first?.priority == .renewal)
    }

    @Test("a paused subscription with no resume date generates nothing")
    func pausedWithoutResumeDate() throws {
        let sub = try makeSubscription(status: .paused, cycle: .monthly, cycleStartDay: try day(2026, 1, 15))
        let today = try day(2026, 8, 6)
        #expect(reminderSchedule(for: sub, from: today, horizonDays: 90).isEmpty)
    }

    @Test("a pending cancellation schedules its verification check on the stored date")
    func pendingVerification() throws {
        let sub = try makeSubscription(status: .cancellationPending, cycle: .monthly, cycleStartDay: try day(2026, 5, 20))
        // The check date was computed once, at cancellation time, from the anchor
        // and the cycle (spec §5.4) - the planner fires on it as stored.
        let record = CancellationEpisode(
            id: try fixtureUUID(600),
            subscriptionID: sub.id,
            markedCancelledAt: Date(timeIntervalSince1970: 0),
            nextChargeDateIfNotCancelled: try day(2026, 8, 20),
            verificationState: .pending,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let today = try day(2026, 8, 6)

        let planned = reminderSchedule(for: sub, cancellation: record, from: today, horizonDays: 90)

        let aug20 = try day(2026, 8, 20)
        #expect(planned.map(\.day) == [aug20])
        #expect(planned.map(\.kind) == [.verification])
        #expect(planned.first?.priority == .verification)
    }

    @Test("a pending cancellation whose check date has passed keeps watching the next would-be charge")
    func staleVerification() throws {
        let sub = try makeSubscription(status: .cancelled, cycle: .monthly, cycleStartDay: try day(2026, 5, 20))
        let record = CancellationEpisode(
            id: try fixtureUUID(600),
            subscriptionID: sub.id,
            markedCancelledAt: Date(timeIntervalSince1970: 0),
            nextChargeDateIfNotCancelled: try day(2026, 8, 20),
            verificationState: .pending,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        // The Aug 20 check came and went unanswered; verification is still the point,
        // so the plan moves to the first would-be charge date on or after today.
        let today = try day(2026, 9, 6)

        let planned = reminderSchedule(for: sub, cancellation: record, from: today, horizonDays: 90)

        let sep20 = try day(2026, 9, 20)
        #expect(planned.map(\.day) == [sep20])
        #expect(planned.map(\.kind) == [.verification])
    }

    @Test("a verified (closed) cancellation generates nothing")
    func verifiedCancellation() throws {
        let sub = try makeSubscription(status: .cancelled, cycle: .monthly, cycleStartDay: try day(2026, 5, 20))
        let record = CancellationEpisode(
            id: try fixtureUUID(600),
            subscriptionID: sub.id,
            markedCancelledAt: Date(timeIntervalSince1970: 0),
            nextChargeDateIfNotCancelled: try day(2026, 8, 20),
            verificationState: .pending,
            verifiedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 100),
            outcome: .verifiedStopped,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let today = try day(2026, 8, 6)
        #expect(reminderSchedule(for: sub, cancellation: record, from: today, horizonDays: 90).isEmpty)
    }

    @Test("three unanswered checks stop verification notifications - the Today card escalates instead (spec §5.4)")
    func threeStrikesStopsNotifications() throws {
        let sub = try makeSubscription(status: .cancelled, cycle: .monthly, cycleStartDay: try day(2026, 5, 20))
        let record = CancellationEpisode(
            id: try fixtureUUID(600),
            subscriptionID: sub.id,
            markedCancelledAt: Date(timeIntervalSince1970: 0),
            nextChargeDateIfNotCancelled: try day(2026, 8, 20),
            verificationState: .pending,
            unansweredCheckCount: 3,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let today = try day(2026, 9, 6)
        #expect(reminderSchedule(for: sub, cancellation: record, from: today, horizonDays: 90).isEmpty)
    }

    @Test("a needs-manual-review record generates nothing either")
    func needsManualReviewGeneratesNothing() throws {
        let sub = try makeSubscription(status: .cancelled, cycle: .monthly, cycleStartDay: try day(2026, 5, 20))
        let record = CancellationEpisode(
            id: try fixtureUUID(600),
            subscriptionID: sub.id,
            markedCancelledAt: Date(timeIntervalSince1970: 0),
            nextChargeDateIfNotCancelled: try day(2026, 8, 20),
            verificationState: .needsManualReview,
            unansweredCheckCount: 3,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let today = try day(2026, 9, 6)
        #expect(reminderSchedule(for: sub, cancellation: record, from: today, horizonDays: 90).isEmpty)
    }

    @Test("an archived subscription generates nothing")
    func archived() throws {
        let sub = try makeSubscription(status: .archived, cycle: .monthly, cycleStartDay: try day(2026, 1, 15))
        let today = try day(2026, 8, 6)
        #expect(reminderSchedule(for: sub, from: today, horizonDays: 90).isEmpty)
    }

    @Test("kinds map to the documented priorities", arguments: PlannedReminder.Kind.allCases)
    func priorityMapping(kind: PlannedReminder.Kind) throws {
        let expected: PlannedReminder.Priority = switch kind {
        case .trialLead, .trialDayOfMorning, .trialDayOfEvening, .trialDaily, .conversionAnnouncement: .trial
        case .verification: .verification
        case .renewal, .renewalDayOf, .pauseEnding: .renewal
        case .usageCheckIn: .usageCheckIn
        }
        let reminder = PlannedReminder(subscriptionID: try fixtureUUID(0), day: try day(2026, 8, 6), kind: kind)
        #expect(reminder.priority == expected)
    }

    @Test("exactly the cancel-by warnings and the conversion announcement are time-sensitive")
    func timeSensitivity() {
        let sensitive = Set(PlannedReminder.Kind.allCases.filter(\.isTimeSensitive))
        #expect(sensitive == [.trialDayOfMorning, .trialDayOfEvening, .conversionAnnouncement])
    }
}

@Suite("Notification planning decisions (spec §6.2, §6.4)")
struct NotificationPlanningTests {

    @Test("fire times: evening last-call at the evening hour, everything else at the preferred hour")
    func fireTimes() throws {
        let policy = FireTimePolicy.standard
        for kind in PlannedReminder.Kind.allCases {
            let time = policy.fireTime(for: kind)
            if kind == .trialDayOfEvening {
                #expect(time == (19, 0))
            } else {
                #expect(time == (9, 0))
            }
        }
    }

    @Test("a fire date combines the day, the policy hour, and the CURRENT timezone")
    func fireDateUsesTimezone() throws {
        let reminder = PlannedReminder(
            subscriptionID: try fixtureUUID(1), day: try day(2026, 8, 11), kind: .trialDayOfMorning
        )
        let toronto = try #require(TimeZone(identifier: "America/Toronto"))
        let vancouver = try #require(TimeZone(identifier: "America/Vancouver"))
        let inToronto = try #require(FireTimePolicy.standard.fireDate(for: reminder, in: toronto))
        let inVancouver = try #require(FireTimePolicy.standard.fireDate(for: reminder, in: vancouver))
        // Same wall-clock day and hour, three hours apart as instants: the day
        // never moves, the instant does (spec §4.1).
        #expect(inVancouver.timeIntervalSince(inToronto) == 3 * 3600)
    }

    @Test("planned identifiers are '<id>|<ISO date>|<kind>' and parse back to their subscription")
    func plannedIdentifiers() throws {
        let id = try fixtureUUID(7)
        let reminder = PlannedReminder(subscriptionID: id, day: try day(2026, 11, 4), kind: .renewal)
        let identifier = NotificationPlanIdentifier.planned(reminder)
        #expect(identifier == "\(id.uuidString)|2026-11-04|renewal")
        #expect(NotificationPlanIdentifier.subscriptionID(of: identifier) == id)
        #expect(!NotificationPlanIdentifier.isSnooze(identifier))
    }

    @Test("snooze identifiers live in their own namespace so reschedules can spare them")
    func snoozeIdentifiers() throws {
        let id = try fixtureUUID(7)
        let identifier = NotificationPlanIdentifier.snooze(
            subscriptionID: id, day: try day(2026, 8, 12), of: .trialDaily
        )
        #expect(NotificationPlanIdentifier.isSnooze(identifier))
        #expect(NotificationPlanIdentifier.subscriptionID(of: identifier) == id)
        // The snooze carries its origin kind, so a snoozed snooze still knows
        // which deadline caps it.
        #expect(NotificationPlanIdentifier.kind(of: identifier) == .trialDaily)
    }

    @Test("a snooze moves one day and is hard-capped at the deadline, under any number of invocations")
    func snoozeCap() throws {
        let cancelBy = try day(2026, 8, 11)
        var current = try day(2026, 8, 9)
        // Snooze five times in a row: 10, 11, then pinned at 11 forever.
        var landed: [CalendarDay] = []
        for _ in 0..<5 {
            current = snoozedReminderDay(from: current, deadline: cancelBy)
            landed.append(current)
        }
        #expect(landed == [
            try day(2026, 8, 10), cancelBy, cancelBy, cancelBy, cancelBy
        ])
    }

    @Test("a snooze with no deadline simply moves to tomorrow")
    func snoozeWithoutDeadline() throws {
        #expect(snoozedReminderDay(from: try day(2026, 8, 31), deadline: nil) == (try day(2026, 9, 1)))
    }
}
