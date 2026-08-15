import Foundation
import OttoDomain
import OttoRepositories

/// What the app should do after an action was handled - the state work is already
/// done by then; this is only about what, if anything, to put on screen.
public enum NotificationActionFollowUp: Hashable, Sendable {
    /// Nothing to show; the action completed in the background.
    case none
    /// Open the subscription's detail screen (the default tap).
    case openDetail(subscriptionID: UUID)
    /// Open the detail AND the stored cancellation URL - "I'm cancelling" brings
    /// the app forward, because a URL cannot be opened from a background handler.
    case openCancellation(subscriptionID: UUID, url: URL?)
}

/// What the routed action actually DID, for the `handled` line (R5-1).
///
/// `snooze` has two non-throwing early returns - the subscription is gone, and
/// every remaining slot on the deadline day is already behind `now` - and both
/// reached the success branch, so a "Remind me later" that produced no reminder
/// logged `handled action=otto.action.remindLater` exactly like one that
/// worked. Neither is a failure: the remaining ladder is the coverage, and
/// throwing would tell the user their answer was lost when it was not. But they
/// are not the same event, and the log said they were.
///
/// Control-flow outcomes only, which is what this category already permits.
enum NotificationActionEffect: String {
    /// A snooze reminder was added to the notification centre.
    case scheduled
    /// The subscription no longer exists, so there was nothing to snooze.
    case noSubscription
    /// Every remaining slot before the deadline has passed; the ladder already
    /// standing is the coverage.
    case deadlinePassed
    /// The notification identifier did not parse, so nothing was routed.
    case unroutable
    /// The action does not schedule anything - every non-snooze branch.
    case notApplicable
}

/// Handles notification action responses (spec §6.4). Every path is safe to run
/// twice - the system can redeliver - and none of them requires the UI: state
/// changes happen against the repositories, and the follow-up tells a foregrounded
/// app what to show if it happens to be there.
public actor NotificationActionHandler {

    private let subscriptions: any SubscriptionRepository
    private let flows: SubscriptionFlowService
    private let client: any NotificationClient
    private let scheduler: any ReminderScheduling
    /// Read fresh per snooze, like the scheduler's - see there (Wave 8).
    private let fireTimes: @Sendable () -> FireTimePolicy

    public init(
        subscriptions: any SubscriptionRepository,
        flows: SubscriptionFlowService,
        client: any NotificationClient,
        scheduler: any ReminderScheduling,
        fireTimes: @escaping @Sendable () -> FireTimePolicy = { .standard }
    ) {
        self.subscriptions = subscriptions
        self.flows = flows
        self.client = client
        self.scheduler = scheduler
        self.fireTimes = fireTimes
    }

    /// Routes one action response. `actionIdentifier` is the button's identifier,
    /// or the system default-action identifier for a plain tap;
    /// `notificationIdentifier` is the deterministic identifier of the
    /// notification acted on.
    public func handle(
        actionIdentifier: String,
        notificationIdentifier: String,
        now: Date,
        today: CalendarDay,
        timeZone: TimeZone
    ) async throws -> NotificationActionFollowUp {
        // The delegate that calls this discards the error (a notification
        // response has nowhere to report one), so if it is not written down
        // here it is written down nowhere: the user's answer disappears, the
        // system has already consumed the notification, and no surface anywhere
        // records that an answer was ever given. The error is rethrown
        // unchanged - this observes, it does not handle.
        let action = actionIdentifier.isEmpty ? "default" : actionIdentifier
        do {
            let routed = try await route(
                actionIdentifier: actionIdentifier,
                notificationIdentifier: notificationIdentifier,
                now: now, today: today, timeZone: timeZone
            )
            // `effect=` is R5-1. Without it this line said only that the
            // handler ran, so a snooze that scheduled nothing and one that
            // scheduled a reminder were the same entry in the log - and the
            // only thing that contradicted it was `snoozesSpared=` in a
            // different category, indirectly.
            OttoLog.actions.notice("""
                handled action=\(action, privacy: .public) \
                id=\(notificationIdentifier, privacy: .public) \
                effect=\(routed.effect.rawValue, privacy: .public)
                """)
            return routed.followUp
        } catch {
            OttoLog.actions.error("""
                action FAILED - the user's answer was not recorded \
                action=\(action, privacy: .public) \
                id=\(notificationIdentifier, privacy: .public) \
                error=\(String(describing: type(of: error)), privacy: .public)
                """)
            throw error
        }
    }

    private func route(
        actionIdentifier: String,
        notificationIdentifier: String,
        now: Date,
        today: CalendarDay,
        timeZone: TimeZone
    ) async throws -> (followUp: NotificationActionFollowUp, effect: NotificationActionEffect) {
        guard let subscriptionID = NotificationPlanIdentifier.subscriptionID(of: notificationIdentifier) else {
            // An identifier the app could not parse routed nothing at all, and
            // reporting that as `notApplicable` would be a new false claim
            // introduced by the field that exists to remove one.
            return (.none, .unroutable)
        }
        switch NotificationAction(rawValue: actionIdentifier) {
        case .keepingIt:
            try await flows.acknowledgeCurrentCharge(subscriptionID: subscriptionID, now: now, today: today)
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: timeZone, trigger: .notificationAction)
            return (.none, .notApplicable)
        case .cancelling:
            guard let start = try await flows.startCancellation(
                subscriptionID: subscriptionID, now: now, today: today
            ) else { return (.none, .notApplicable) }
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: timeZone, trigger: .notificationAction)
            return (.openCancellation(subscriptionID: subscriptionID, url: start.cancellationURL), .notApplicable)
        case .chargesStopped:
            // The verification yes-path (spec §5.4): verify and archive, all
            // background-safe - answering must succeed with the phone in a pocket.
            _ = try await flows.answerVerification(
                subscriptionID: subscriptionID, chargesStopped: true, now: now, today: today
            )
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: timeZone, trigger: .notificationAction)
            return (.none, .notApplicable)
        case .stillCharging:
            // The no-path: the state work is background-safe, and the action is
            // foreground-registered so the dispute summary is on screen the
            // moment the user needs it.
            _ = try await flows.answerVerification(
                subscriptionID: subscriptionID, chargesStopped: false, now: now, today: today
            )
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: timeZone, trigger: .notificationAction)
            return (.openDetail(subscriptionID: subscriptionID), .notApplicable)
        case .stillUsing:
            // The §7.3 yes-path: record the use, background-safe, and let the
            // reschedule move the next check-in a cadence out.
            try await flows.recordUsage(subscriptionID: subscriptionID, on: today, now: now)
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: timeZone, trigger: .notificationAction)
            return (.none, .notApplicable)
        case .notUsing:
            // The other path opens the facts; deciding what to do with an
            // unused subscription is the user's call, never Otto's.
            return (.openDetail(subscriptionID: subscriptionID), .notApplicable)
        case .remindLater:
            let effect = try await snooze(
                subscriptionID: subscriptionID,
                notificationIdentifier: notificationIdentifier,
                now: now,
                today: today,
                timeZone: timeZone
            )
            return (.none, effect)
        case nil:
            // The plain tap: open the subscription. A delivery or interaction is
            // also a reschedule trigger (spec §6.2), which the caller performs.
            return (.openDetail(subscriptionID: subscriptionID), .notApplicable)
        }
    }

    /// "Remind me later" (spec §6.4): tomorrow at the preferred hour, hard-capped
    /// at the deadline - a trial's cancel-by date, a renewal's billing date. A
    /// snooze that skips the deadline is a bug that costs money, so the cap holds
    /// under any number of invocations. The snooze lives in its own identifier
    /// namespace, so full reschedules leave it standing, and its deterministic
    /// identifier makes redelivery idempotent.
    private func snooze(
        subscriptionID: UUID,
        notificationIdentifier: String,
        now: Date,
        today: CalendarDay,
        timeZone: TimeZone
    ) async throws -> NotificationActionEffect {
        guard let subscription = try await subscriptions.subscription(withID: subscriptionID) else {
            return .noSubscription
        }
        let deadline = snoozeDeadline(
            for: notificationIdentifier, subscription: subscription, today: today
        )
        let target = snoozedReminderDay(from: today, deadline: deadline)

        let policy = fireTimes()
        var hour = policy.preferredHour
        var minute = policy.preferredMinute
        if let atPreferred = target.fireDate(hour: hour, minute: minute, in: timeZone),
           atPreferred <= now {
            // Snoozed on the deadline day itself, after the preferred hour: fall
            // to the evening slot. If even that has passed, the remaining ladder
            // is the coverage - a snooze must never re-fire behind the deadline.
            hour = policy.eveningHour
            minute = policy.eveningMinute
            guard let atEvening = target.fireDate(hour: hour, minute: minute, in: timeZone),
                  atEvening > now
            else { return .deadlinePassed }
        }

        let kind = snoozedKind(of: notificationIdentifier)
        let reminder = PlannedReminder(subscriptionID: subscriptionID, day: target, kind: kind)
        try await client.add(NotificationRequestSpec(
            identifier: NotificationPlanIdentifier.snooze(subscriptionID: subscriptionID, day: target, of: kind),
            title: NotificationContent.title(for: reminder, subscription: subscription),
            body: NotificationContent.body(for: reminder, subscription: subscription),
            year: target.year,
            month: target.month,
            day: target.day,
            hour: hour,
            minute: minute,
            // From the KIND, exactly as the scheduler derives it. Hard-coding
            // false silently demoted the one rung where it matters most: the
            // cancel-by day's morning and evening warnings are time-sensitive
            // so they break through Focus (spec §6.3), and "remind me later" is
            // the user asking to be told again about that same deadline. The
            // repeat arrived without the breakthrough the original had, so a
            // Focus mode or Scheduled Summary could hold the last warning
            // before unrecoverable money moves.
            isTimeSensitive: kind.isTimeSensitive,
            categoryIdentifier: NotificationCategory.actionable
        ))
        return .scheduled
    }

    /// The date a snooze must never pass: the cancel-by date for trial reminders,
    /// the billing date for renewal ones, nothing for the rest.
    private func snoozeDeadline(
        for identifier: String,
        subscription: Subscription,
        today: CalendarDay
    ) -> CalendarDay? {
        switch snoozedKind(of: identifier) {
        case .trialLead, .trialDayOfMorning, .trialDayOfEvening, .trialDaily:
            subscription.trial?.cancelByDate
        case .renewal, .renewalDayOf:
            nextBillingDate(
                after: today.adding(days: -1),
                anchor: subscription.billingAnchor(asOf: today),
                cycle: subscription.cycle
            )
        case .conversionAnnouncement, .verification, .usageCheckIn, .pauseEnding:
            nil
        }
    }

    /// The kind encoded in the acted-on notification's identifier - carried
    /// through the snooze namespace, so a snoozed snooze still knows which
    /// deadline caps it. An unparseable identifier falls back to the strictest
    /// cap, the trial's.
    private func snoozedKind(of identifier: String) -> PlannedReminder.Kind {
        NotificationPlanIdentifier.kind(of: identifier) ?? .trialDaily
    }
}
