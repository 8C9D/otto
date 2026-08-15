import Foundation
import OSLog
import OttoDomain
import Testing
@testable import OttoServices

/// R5-2. Round 1 closed F2 by adding two `OttoLog.actions` lines and evidenced
/// the emission with an artifact quoted in a commit message - which is a real
/// artifact, and not a guard. `reviews/REVIEW-5.md` measured that deleting both
/// statements left the whole suite green, and named the technique that would
/// close it. Round 1 declined it on cost and on the log daemon being readable;
/// the first is real and measured below, and the second is now recorded in
/// CANNOT ASSESS rather than used as a reason to have no guard at all.
///
/// This is the one boundary where a failure is otherwise unobservable: the
/// delegate discards the handler's error, the system has already consumed the
/// notification, and "Remind me later" is terminal - a snooze that threw is the
/// reminder simply ceasing to exist.
@Suite("The notification-action log line exists (R5-2)")
struct NotificationActionLogTests {

    private func seedTrial(
        _ subscriptions: FakeSubscriptionRepository
    ) async throws -> (subscription: Subscription, trial: TrialTerm) {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 27), lengthDays: 14)
        let subscription = try makeSubscription(
            index: 88, status: .trial, cycleStartDay: try day(2026, 7, 27),
            reminderLeadDays: 5, trial: trial,
            cancellationURL: URL(string: "https://example.com/cancel")
        )
        await subscriptions.seed([subscription])
        return (subscription, trial)
    }

    @Test("⛔ a snooze that threw leaves a FAILED line naming the action, the rung and the error type")
    func aFailedActionIsRecorded() async throws {
        let fixture = SchedulerFixture()
        let (subscription, trial) = try await seedTrial(fixture.subscriptions)
        let identifier = NotificationPlanIdentifier.planned(
            PlannedReminder(
                subscriptionID: subscription.id,
                day: trial.cancelByDate.adding(days: -5),
                kind: .trialLead
            )
        )
        await fixture.client.refuseAdds(after: 0)

        let since = Date()
        OttoLogProbe.emitCanary(to: OttoLog.actions)
        await #expect(throws: FakeNotificationClient.AddRefused.self) {
            _ = try await fixture.handler.handle(
                actionIdentifier: NotificationAction.remindLater.rawValue,
                notificationIdentifier: identifier,
                now: try fixtureNow(), today: try day(2026, 8, 6), timeZone: torontoZone
            )
        }

        let lines = try Self.actionLogLines(since: since)
        try OttoLogProbe.requireDelivered(lines)
        let line = try #require(
            lines.last { $0.contains(identifier) },
            "the handler recorded nothing for an action that threw"
        )
        #expect(line.contains("action FAILED"))
        #expect(line.contains("action=\(NotificationAction.remindLater.rawValue)"))
        #expect(line.contains("error=AddRefused"))
        // The identifier is the opaque <uuid>|<day>|<kind> triple and nothing
        // richer: no vendor, no amount, no card.
        #expect(!line.contains("FoodApp"))
        #expect(!line.contains("$"))
    }

    @Test("a successful action is recorded too, so silence in the log means the handler never ran")
    func aHandledActionIsRecorded() async throws {
        let fixture = SchedulerFixture()
        let (subscription, trial) = try await seedTrial(fixture.subscriptions)
        let identifier = NotificationPlanIdentifier.planned(
            PlannedReminder(
                subscriptionID: subscription.id, day: trial.cancelByDate, kind: .trialDayOfMorning
            )
        )

        let since = Date()
        OttoLogProbe.emitCanary(to: OttoLog.actions)
        _ = try await fixture.handler.handle(
            actionIdentifier: NotificationAction.remindLater.rawValue,
            notificationIdentifier: identifier,
            now: try fixtureNow(), today: try day(2026, 8, 6), timeZone: torontoZone
        )

        let lines = try Self.actionLogLines(since: since)
        try OttoLogProbe.requireDelivered(lines)
        let line = try #require(
            lines.last { $0.contains(identifier) },
            "the handler recorded nothing for an action that succeeded"
        )
        #expect(line.hasPrefix("handled "))
        #expect(!line.contains("FAILED"))
        // STRENGTHENED for R5-1. This assertion pair used to end at "the line
        // exists", and that expectation encoded the defect: the same line was
        // emitted by a snooze that scheduled a reminder and by one that
        // scheduled nothing at all. This snooze DID schedule.
        #expect(line.contains("effect=scheduled"))
    }

    /// R5-1. `snooze`'s two non-throwing early returns reached the success
    /// branch, so "Remind me later" logged `handled action=otto.action.remindLater`
    /// identically whether or not a reminder existed afterwards. Only
    /// `snoozesSpared=` in a different category contradicted it, indirectly.
    ///
    /// One query for both halves, because a query costs seconds: the
    /// discriminating assertion is that the two lines DIFFER.
    @Test("⛔ a snooze that scheduled nothing does not log what a snooze that worked logs")
    func aSnoozeThatScheduledNothingSaysSo() async throws {
        let fixture = SchedulerFixture()
        // A subscription of this test's OWN, not `seedTrial`'s shared index 88.
        // `aHandledActionIsRecorded` snoozes the identical rung of the identical
        // fixture, so the "a snooze that worked" line this test looked for was
        // being supplied by a sibling: deleting this test's own working snooze
        // left it passing 3 runs out of 3 (`reviews-3/REVIEW-4.md` finding 4).
        let workingTrial = try makeTrialTerm(index: 501, startDate: try day(2026, 7, 27), lengthDays: 14)
        let working = try makeSubscription(
            index: 8_801, status: .trial, cycleStartDay: try day(2026, 7, 27),
            reminderLeadDays: 5, trial: workingTrial
        )
        _ = try await seedTrial(fixture.subscriptions)
        await fixture.subscriptions.seed([working])
        let trial = workingTrial
        let subscription = working
        let workingIdentifier = NotificationPlanIdentifier.planned(
            PlannedReminder(
                subscriptionID: subscription.id, day: trial.cancelByDate, kind: .trialDayOfMorning
            )
        )
        // A rung whose subscription is gone: `snooze`'s first early return.
        // The identifier still parses, so the action routes and reaches it.
        let orphanIdentifier = NotificationPlanIdentifier.planned(
            PlannedReminder(
                subscriptionID: try fixtureUUID(4_242), day: trial.cancelByDate, kind: .trialDayOfMorning
            )
        )

        let since = Date()
        OttoLogProbe.emitCanary(to: OttoLog.actions)
        for identifier in [workingIdentifier, orphanIdentifier] {
            _ = try await fixture.handler.handle(
                actionIdentifier: NotificationAction.remindLater.rawValue,
                notificationIdentifier: identifier,
                now: try fixtureNow(), today: try day(2026, 8, 6), timeZone: torontoZone
            )
        }

        let lines = try Self.actionLogLines(since: since)
        try OttoLogProbe.requireDelivered(lines)
        let worked = try #require(lines.last { $0.contains(workingIdentifier) })
        let didNothing = try #require(lines.last { $0.contains(orphanIdentifier) })

        // Both are `handled` - neither is a failure, and calling the second one
        // a failure would tell the user their answer was lost when it was not.
        #expect(worked.hasPrefix("handled "))
        #expect(didNothing.hasPrefix("handled "))
        // And they are no longer the same event.
        #expect(worked.contains("effect=scheduled"))
        #expect(didNothing.contains("effect=noSubscription"))
    }

    @Test("an identifier that does not parse is not reported as an action that did nothing applicable")
    func anUnroutableIdentifierSaysSo() async throws {
        let fixture = SchedulerFixture()
        _ = try await seedTrial(fixture.subscriptions)

        let since = Date()
        OttoLogProbe.emitCanary(to: OttoLog.actions)
        _ = try await fixture.handler.handle(
            actionIdentifier: NotificationAction.remindLater.rawValue,
            notificationIdentifier: "not-an-otto-identifier",
            now: try fixtureNow(), today: try day(2026, 8, 6), timeZone: torontoZone
        )

        let lines = try Self.actionLogLines(since: since)
        try OttoLogProbe.requireDelivered(lines)
        let line = try #require(lines.last { $0.contains("not-an-otto-identifier") })
        // Adding `effect=` to this line would have introduced a NEW false claim
        // if this branch reported `notApplicable`: nothing was routed at all.
        #expect(line.contains("effect=unroutable"))
    }

    /// Every `actions` line this process emitted since `since`.
    /// `.currentProcessIdentifier` reads only this process, so the assertion is
    /// about the app rather than about the host - the claim round 1 recorded as
    /// fact and then corrected.
    private static func actionLogLines(since: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        return try store
            .getEntries(
                at: store.position(date: since),
                matching: NSPredicate(
                    format: "subsystem == %@ AND category == %@",
                    "com.arthurzhang.otto", "actions"
                )
            )
            .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
    }
}
