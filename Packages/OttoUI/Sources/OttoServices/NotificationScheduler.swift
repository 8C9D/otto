import Foundation
import OttoDomain
import OttoRepositories

/// What a scheduling pass produced - the facts Today needs to state honestly:
/// whether anything can be delivered at all, and through which day coverage
/// actually extends (spec §6.1 point 4).
public struct ScheduleOutcome: Hashable, Sendable {
    public let permission: NotificationPermission
    /// Planned requests now pending (snoozes not included).
    public let scheduledCount: Int
    /// The last day with complete coverage when the budget truncated the plan,
    /// nil when nothing was dropped.
    public let truncatedAfter: CalendarDay?
    /// The day through which the UI may claim coverage: the truncation point if
    /// one exists, the horizon end otherwise. Never let the user believe coverage
    /// extends further than it does.
    public let coveredThrough: CalendarDay
    /// Subscriptions whose ledger reconciliation failed this pass - scheduling
    /// continued without them rather than aborting, but the failure is not
    /// swallowed.
    public let ledgerFailures: [UUID]

    public init(
        permission: NotificationPermission,
        scheduledCount: Int,
        truncatedAfter: CalendarDay?,
        coveredThrough: CalendarDay,
        ledgerFailures: [UUID] = []
    ) {
        self.permission = permission
        self.scheduledCount = scheduledCount
        self.truncatedAfter = truncatedAfter
        self.coveredThrough = coveredThrough
        self.ledgerFailures = ledgerFailures
    }
}

/// The store layer talks to the scheduler through this seam so store tests can
/// substitute a spy.
public protocol ReminderScheduling: Sendable {
    @discardableResult
    func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome
}

/// Layer 4 (spec §3.4): translates the domain's pure reminder plan into pending
/// notification requests. It computes NOTHING - which days, which priorities,
/// which identifiers, and where the budget cuts are all domain decisions already
/// made and tested; this actor loads data, calls the plan, and mirrors the result
/// into the notification center. If a new decision is ever needed here, it
/// belongs in the domain instead.
public actor NotificationScheduler: ReminderScheduling {

    /// iOS's hard ceiling on pending local notifications (spec §6.1).
    public static let slotLimit = 64
    /// The rolling scheduling horizon (spec §6.1).
    public static let horizonDays = 90

    private let subscriptions: any SubscriptionRepository
    private let cancellations: any CancellationRepository
    private let billingEvents: any BillingEventRepository
    private let client: any NotificationClient
    private let fireTimes: FireTimePolicy

    public init(
        subscriptions: any SubscriptionRepository,
        cancellations: any CancellationRepository,
        billingEvents: any BillingEventRepository,
        client: any NotificationClient,
        fireTimes: FireTimePolicy = .standard
    ) {
        self.subscriptions = subscriptions
        self.cancellations = cancellations
        self.billingEvents = billingEvents
        self.client = client
        self.fireTimes = fireTimes
    }

    /// The idempotent full pass (spec §6.2): remove every planned request,
    /// recompute the plan, schedule it again. Deterministic identifiers and
    /// deterministic budgeting make a double run produce byte-identical pending
    /// requests. Snoozes are user-created state living only in the notification
    /// center, so the pass spares them and shrinks the budget beneath them.
    @discardableResult
    public func reschedule(
        now: Date,
        today: CalendarDay,
        timeZone: TimeZone
    ) async throws -> ScheduleOutcome {
        let permission = await client.permission()
        let horizonEnd = today.adding(days: Self.horizonDays)

        guard permission == .authorized || permission == .provisional else {
            // Nothing can be delivered. Clear the planned requests so a later
            // grant starts clean, and surface the state - Today renders it loudly
            // (constraint 3); pretending to schedule would be the silent failure
            // this app exists to prevent.
            let planned = await client.pendingRequests()
                .map(\.identifier)
                .filter { !NotificationPlanIdentifier.isSnooze($0) }
            await client.removePendingRequests(withIdentifiers: planned)
            return ScheduleOutcome(
                permission: permission, scheduledCount: 0,
                truncatedAfter: nil, coveredThrough: horizonEnd
            )
        }

        let live = try await subscriptions.subscriptions()
        let ledgerFailures = await reconcileLedger(for: live, today: today, now: now)

        // The pure plan, budgeted beneath whatever snoozes already occupy.
        var records: [UUID: CancellationRecord] = [:]
        for subscription in live
        where subscription.status == .cancellationPending || subscription.status == .cancelled {
            records[subscription.id] = try await cancellations.record(forSubscription: subscription.id)
        }
        let plan = live.flatMap {
            reminderSchedule(
                for: $0, cancellation: records[$0.id], from: today, horizonDays: Self.horizonDays
            )
        }
        let pending = await client.pendingRequests()
        let snoozeCount = pending.filter { NotificationPlanIdentifier.isSnooze($0.identifier) }.count
        let (scheduled, truncatedAfter) = budgeted(plan, limit: max(0, Self.slotLimit - snoozeCount))
        let specs = requestSpecs(for: scheduled, subscriptions: live, now: now, timeZone: timeZone)

        // Replace: every planned identifier goes, snoozes stay, the fresh plan
        // lands. Identifiers are deterministic, so this is idempotent.
        let plannedIdentifiers = pending.map(\.identifier)
            .filter { !NotificationPlanIdentifier.isSnooze($0) }
        await client.removePendingRequests(withIdentifiers: plannedIdentifiers)
        for spec in specs {
            try await client.add(spec)
        }

        return ScheduleOutcome(
            permission: permission,
            scheduledCount: specs.count,
            truncatedAfter: truncatedAfter,
            coveredThrough: min(truncatedAfter ?? horizonEnd, horizonEnd),
            ledgerFailures: ledgerFailures
        )
    }

    /// Ledger upkeep happens at reminder-scheduling time and nowhere else
    /// (spec §5.3): first drop the .upcoming rows a schedule change orphaned,
    /// then materialize the current sequence. A single subscription's failure is
    /// recorded and skipped - one broken record must not silence the other 199
    /// subscriptions' reminders.
    private func reconcileLedger(
        for live: [Subscription],
        today: CalendarDay,
        now: Date
    ) async -> [UUID] {
        let maxLead = live.map(\.reminderLeadDays).max() ?? 0
        var failures: [UUID] = []
        for subscription in live {
            do {
                _ = try await billingEvents.invalidateOutdatedUpcomingEvents(
                    for: subscription, asOf: today, at: now
                )
                _ = try await billingEvents.materializeEvents(
                    for: subscription, from: today, horizonDays: Self.horizonDays,
                    maxReminderLeadDays: maxLead, at: now
                )
            } catch {
                failures.append(subscription.id)
            }
        }
        return failures
    }

    /// Translates budgeted reminders into request specs. A reminder dated today
    /// whose fire time has already passed is left for the next scheduler run, per
    /// §6.2's catch-up rule - a calendar trigger in the past would not fire anyway.
    private func requestSpecs(
        for scheduled: [PlannedReminder],
        subscriptions live: [Subscription],
        now: Date,
        timeZone: TimeZone
    ) -> [NotificationRequestSpec] {
        let subscriptionsByID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        var specs: [NotificationRequestSpec] = []
        for reminder in scheduled {
            guard let subscription = subscriptionsByID[reminder.subscriptionID],
                  let fireDate = fireTimes.fireDate(for: reminder, in: timeZone),
                  fireDate > now
            else { continue }
            let time = fireTimes.fireTime(for: reminder.kind)
            specs.append(NotificationRequestSpec(
                identifier: NotificationPlanIdentifier.planned(reminder),
                title: NotificationContent.title(for: reminder, subscription: subscription),
                body: NotificationContent.body(for: reminder, subscription: subscription),
                year: reminder.day.year,
                month: reminder.day.month,
                day: reminder.day.day,
                hour: time.hour,
                minute: time.minute,
                isTimeSensitive: reminder.kind.isTimeSensitive,
                categoryIdentifier: NotificationCategory.identifier(for: reminder.kind)
            ))
        }
        return specs
    }
}

/// The notification categories and their action buttons (spec §6.4).
public enum NotificationCategory {
    /// Renewal and trial reminders carry the three actions.
    public static let actionable = "otto.category.reminder"
    /// Everything else is informational in Wave 4; verification answers and
    /// usage responses are Wave 5 and Wave 7 flows.
    public static let plain = ""

    public static func identifier(for kind: PlannedReminder.Kind) -> String {
        switch kind {
        case .renewal, .renewalDayOf, .trialLead, .trialDayOfMorning,
             .trialDayOfEvening, .trialDaily:
            actionable
        case .conversionAnnouncement, .verification, .usageCheckIn, .pauseEnding:
            plain
        }
    }
}

/// The three action buttons (spec §6.4), by stable identifier.
public enum NotificationAction: String, CaseIterable, Sendable {
    case keepingIt = "otto.action.keepingIt"
    case cancelling = "otto.action.cancelling"
    case remindLater = "otto.action.remindLater"
}
