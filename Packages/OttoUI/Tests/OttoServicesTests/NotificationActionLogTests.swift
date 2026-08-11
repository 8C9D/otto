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
        await #expect(throws: FakeNotificationClient.AddRefused.self) {
            _ = try await fixture.handler.handle(
                actionIdentifier: NotificationAction.remindLater.rawValue,
                notificationIdentifier: identifier,
                now: try fixtureNow(), today: try day(2026, 8, 6), timeZone: torontoZone
            )
        }

        let line = try #require(
            Self.actionLogLines(since: since).last { $0.contains(identifier) },
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
        _ = try await fixture.handler.handle(
            actionIdentifier: NotificationAction.remindLater.rawValue,
            notificationIdentifier: identifier,
            now: try fixtureNow(), today: try day(2026, 8, 6), timeZone: torontoZone
        )

        let line = try #require(
            Self.actionLogLines(since: since).last { $0.contains(identifier) },
            "the handler recorded nothing for an action that succeeded"
        )
        #expect(line.hasPrefix("handled "))
        #expect(!line.contains("FAILED"))
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
