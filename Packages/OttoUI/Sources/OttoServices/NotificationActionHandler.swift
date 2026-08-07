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

/// Handles notification action responses (spec §6.4). Every path is safe to run
/// twice - the system can redeliver - and none of them requires the UI: state
/// changes happen against the repositories, and the follow-up tells a foregrounded
/// app what to show if it happens to be there.
public actor NotificationActionHandler {

    private let subscriptions: any SubscriptionRepository
    private let flows: SubscriptionFlowService
    private let client: any NotificationClient
    private let scheduler: any ReminderScheduling
    private let fireTimes: FireTimePolicy

    public init(
        subscriptions: any SubscriptionRepository,
        flows: SubscriptionFlowService,
        client: any NotificationClient,
        scheduler: any ReminderScheduling,
        fireTimes: FireTimePolicy = .standard
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
        guard let subscriptionID = NotificationPlanIdentifier.subscriptionID(of: notificationIdentifier) else {
            return .none
        }
        switch NotificationAction(rawValue: actionIdentifier) {
        case .keepingIt:
            try await flows.acknowledgeCurrentCharge(subscriptionID: subscriptionID, now: now, today: today)
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: timeZone)
            return .none
        case .cancelling:
            guard let start = try await flows.startCancellation(
                subscriptionID: subscriptionID, now: now, today: today
            ) else { return .none }
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: timeZone)
            return .openCancellation(subscriptionID: subscriptionID, url: start.cancellationURL)
        case .chargesStopped:
            // The verification yes-path (spec §5.4): verify and archive, all
            // background-safe - answering must succeed with the phone in a pocket.
            _ = try await flows.answerVerification(
                subscriptionID: subscriptionID, chargesStopped: true, now: now, today: today
            )
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: timeZone)
            return .none
        case .stillCharging:
            // The no-path: the state work is background-safe, and the action is
            // foreground-registered so the dispute summary is on screen the
            // moment the user needs it.
            _ = try await flows.answerVerification(
                subscriptionID: subscriptionID, chargesStopped: false, now: now, today: today
            )
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: timeZone)
            return .openDetail(subscriptionID: subscriptionID)
        case .stillUsing:
            // The §7.3 yes-path: record the use, background-safe, and let the
            // reschedule move the next check-in a cadence out.
            try await flows.recordUsage(subscriptionID: subscriptionID, on: today, now: now)
            _ = try await scheduler.reschedule(now: now, today: today, timeZone: timeZone)
            return .none
        case .notUsing:
            // The other path opens the facts; deciding what to do with an
            // unused subscription is the user's call, never Otto's.
            return .openDetail(subscriptionID: subscriptionID)
        case .remindLater:
            try await snooze(
                subscriptionID: subscriptionID,
                notificationIdentifier: notificationIdentifier,
                now: now,
                today: today,
                timeZone: timeZone
            )
            return .none
        case nil:
            // The plain tap: open the subscription. A delivery or interaction is
            // also a reschedule trigger (spec §6.2), which the caller performs.
            return .openDetail(subscriptionID: subscriptionID)
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
    ) async throws {
        guard let subscription = try await subscriptions.subscription(withID: subscriptionID) else {
            return
        }
        let deadline = snoozeDeadline(
            for: notificationIdentifier, subscription: subscription, today: today
        )
        let target = snoozedReminderDay(from: today, deadline: deadline)

        var hour = fireTimes.preferredHour
        var minute = fireTimes.preferredMinute
        if let atPreferred = target.fireDate(hour: hour, minute: minute, in: timeZone),
           atPreferred <= now {
            // Snoozed on the deadline day itself, after the preferred hour: fall
            // to the evening slot. If even that has passed, the remaining ladder
            // is the coverage - a snooze must never re-fire behind the deadline.
            hour = fireTimes.eveningHour
            minute = fireTimes.eveningMinute
            guard let atEvening = target.fireDate(hour: hour, minute: minute, in: timeZone),
                  atEvening > now
            else { return }
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
            isTimeSensitive: false,
            categoryIdentifier: NotificationCategory.actionable
        ))
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
