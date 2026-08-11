import Foundation
import OttoDomain
import OttoRepositories

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
    /// How far out a §6.2 catch-up fires (Wave 10, defect A). Not instant,
    /// because `UNTimeIntervalNotificationTrigger` requires a positive
    /// interval and a beat of slack lets the reconciliation pass finish before
    /// anything fires; not longer, because the whole point is that the user
    /// who just opened the app at 10:03 sees the 09:00 warning NOW, while the
    /// subscription that prompted them is still on their mind.
    public static let catchUpIntervalSeconds = 5

    private let subscriptions: any SubscriptionRepository
    private let cancellations: any CancellationRepository
    private let billingEvents: any BillingEventRepository
    private let client: any NotificationClient
    /// Read fresh on every pass (Wave 8): the notification-time setting must
    /// reach background passes too, and a provider does that without the
    /// scheduler knowing where settings live.
    private let fireTimes: @Sendable () -> FireTimePolicy
    /// Same shape as `fireTimes`, same reason: this pass writes money into
    /// notification copy, money renders per locale, and a test that cannot pin
    /// the locale asserts about its host rather than about the app.
    private let locale: @Sendable () -> Locale

    public init(
        subscriptions: any SubscriptionRepository,
        cancellations: any CancellationRepository,
        billingEvents: any BillingEventRepository,
        client: any NotificationClient,
        fireTimes: @escaping @Sendable () -> FireTimePolicy = { .standard },
        locale: @escaping @Sendable () -> Locale = { .autoupdatingCurrent }
    ) {
        self.subscriptions = subscriptions
        self.cancellations = cancellations
        self.billingEvents = billingEvents
        self.client = client
        self.fireTimes = fireTimes
        self.locale = locale
    }

    /// The idempotent full pass (spec §6.2): recompute the plan, then RECONCILE
    /// it against the device's pending requests - remove only what the plan no
    /// longer wants, add only what the device does not hold, and add over the
    /// top where content differs (same identifier replaces). Deterministic
    /// identifiers and deterministic budgeting make a double run a no-op.
    ///
    /// Reconciliation, never remove-all-then-re-add (Wave 10, defect B): the
    /// old shape held a window between the removes and the re-adds in which a
    /// suspension left the device with NOTHING pending - observed on device at
    /// 5 ms from losing all three trial rungs, on a product built around a
    /// phone that sits untouched in a drawer. With a diff there is no instant
    /// at which a rung that should exist does not exist; a suspension
    /// mid-reconciliation leaves a superset or the correct set, never an empty
    /// one. Snoozes are user-created state living only in the notification
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

        // Cancellation checkpoints (Gate 2, Aug 2026). A `BGAppRefreshTask`
        // expiration cancels this task, and before these existed the pass ran
        // on regardless - completing the task twice and writing after the OS
        // had reclaimed it. Aborting here is safe by construction, which is
        // the only reason it is allowed to abort at all:
        //   - the ledger advances a subscription's watermark only AFTER
        //     saving its rows, and per subscription, so a half-finished loop
        //     leaves finished subscriptions consistent and untouched ones
        //     merely behind - never a watermark vouching for absent rows;
        //   - materialization is idempotent, so the next pass re-does the
        //     remainder rather than duplicating the part already done;
        //   - the reconcile below is a diff that never removes a desired
        //     rung, so stopping partway leaves a superset or a subset of the
        //     plan, never the empty set Wave 10's defect B produced;
        //   - and the next wake-up is submitted BEFORE this work starts (see
        //     `handleBackgroundRefresh`), so a cancelled pass is already
        //     re-armed and loses nothing but this cycle.
        try Task.checkCancellation()

        // The pure plan, budgeted beneath whatever snoozes already occupy.
        let records = try await caughtUpCancellationEpisodes(for: live, today: today, now: now)
        let acknowledged = try await acknowledgedChargeDays(for: live)
        let plan = live.flatMap {
            reminderSchedule(
                for: $0,
                cancellation: records[$0.id],
                acknowledgedChargeDays: acknowledged[$0.id] ?? [],
                from: today,
                horizonDays: Self.horizonDays
            )
        }
        let pending = await client.pendingRequests()
        let snoozeCount = pending.filter { NotificationPlanIdentifier.isSnooze($0.identifier) }.count
        let (scheduled, truncatedAfter) = budgeted(plan, limit: max(0, Self.slotLimit - snoozeCount))
        let delivered = Set(await client.deliveredIdentifiers())
        let specs = requestSpecs(for: scheduled, translating: SpecInputs(
            subscriptions: live, cancellations: records,
            delivered: delivered, now: now, timeZone: timeZone, locale: locale()
        ))

        try Task.checkCancellation()
        try await reconcile(desired: specs, pending: pending, today: today)

        return ScheduleOutcome(
            permission: permission,
            scheduledCount: specs.count,
            truncatedAfter: truncatedAfter,
            coveredThrough: min(truncatedAfter ?? horizonEnd, horizonEnd),
            ledgerFailures: ledgerFailures
        )
    }

    /// The diff (Wave 10, defect B): removes only identifiers the plan no
    /// longer wants, adds only identifiers the device does not already hold
    /// with identical content - `UNUserNotificationCenter` replaces on same
    /// identifier, so a changed spec is one idempotent add, and an unchanged
    /// one is no call at all. Removes go first only because they free budget
    /// slots; no desired rung is ever among them.
    ///
    /// The conversion announcement is never cancelled by a reschedule (Wave
    /// 10, defect C; spec §6.3): the escalation is a request and can be
    /// waived, the announcement is a fact and cannot. A pending announcement
    /// dated TODAY is structurally exempt from removal - if the desired plan
    /// would drop it (as the passed-hour filter did at 09:01 on conversion
    /// day, permanently cancelling the one notification that says money
    /// started moving), the device keeps it anyway. Past-dated announcements
    /// are removable: a day-late "converted today" is the dishonesty v1.4
    /// legislated against, and future-dated ones must go when a trial is
    /// cancelled before converting.
    private func reconcile(
        desired specs: [NotificationRequestSpec],
        pending: [NotificationRequestSpec],
        today: CalendarDay
    ) async throws {
        let desiredByID = Dictionary(uniqueKeysWithValues: specs.map { ($0.identifier, $0) })
        let planned = pending.filter { !NotificationPlanIdentifier.isSnooze($0.identifier) }
        let stale = planned.filter { existing in
            desiredByID[existing.identifier] == nil && !isTodaysAnnouncement(existing, today: today)
        }
        if !stale.isEmpty {
            await client.removePendingRequests(withIdentifiers: stale.map(\.identifier))
        }
        let pendingByID = Dictionary(uniqueKeysWithValues: planned.map { ($0.identifier, $0) })
        // Every rung is ATTEMPTED before the pass gives up. Throwing from
        // inside the loop abandoned every spec ordered behind the first
        // refusal, deterministically, so the same rungs lost their slot on
        // every pass. The pass still reports failure afterwards - so Today
        // stops claiming coverage - but the device holds all it could take.
        var added: [String] = []
        var failures: [(id: String, error: any Error)] = []
        for spec in specs where pendingByID[spec.identifier] != spec {
            do { try await client.add(spec); added.append(spec.identifier) } catch {
                failures.append((spec.identifier, error))
            }
        }
        // The evidence that this is a diff and not the old remove-all: over an
        // unchanged plan both lists are empty while `pending` is not.
        // Identifiers, never counts - a count cannot tell a correct three-rung
        // replacement from a wipe.
        OttoLog.scheduling.notice("""
            reconcile pending=\(planned.count, privacy: .public) desired=\(specs.count, privacy: .public) \
            snoozesSpared=\(pending.count - planned.count, privacy: .public) \
            removed=[\(OttoLog.list(stale.map(\.identifier)), privacy: .public)] \
            added=[\(OttoLog.list(added), privacy: .public)] \
            failed=[\(OttoLog.failures(failures), privacy: .public)]
            """)
        // After the log line, so an investigation sees which rungs landed.
        //
        // Only the FIRST failure can be rethrown - the caller takes one error -
        // so the log is the only place the others can be recorded, and until it
        // carried `id=ErrorType` pairs they were collected and dropped.
        if let first = failures.first { throw first.error }
    }

    private func isTodaysAnnouncement(_ spec: NotificationRequestSpec, today: CalendarDay) -> Bool {
        NotificationPlanIdentifier.kind(of: spec.identifier) == .conversionAnnouncement
            && CalendarDay(year: spec.year, month: spec.month, day: spec.day) == today
    }

    /// The cancellation records the plan needs - and loading them doubles as the
    /// §5.4 roll-forward: every scheduling pass catches unanswered checks up to
    /// today, so the three-strike escalation depends on stored state and the
    /// current date, never on the app having been opened at the right time.
    private func caughtUpCancellationEpisodes(
        for live: [Subscription],
        today: CalendarDay,
        now: Date
    ) async throws -> [UUID: CancellationEpisode] {
        var records: [UUID: CancellationEpisode] = [:]
        // Effective, not stored (spec §5.2a, v1.7): equivalent today - nothing
        // derives into or out of a cancellation state - and immune to a future
        // derived state slipping past a stored filter, which is the Wave 4 bug's
        // shape.
        for subscription in live
        where subscription.effectiveStatus(asOf: today) == .cancellationPending
            || subscription.effectiveStatus(asOf: today) == .cancelled {
            guard let record = try await cancellations.openEpisode(forSubscription: subscription.id) else {
                continue
            }
            let caughtUp = record.catchingUpOnUnansweredChecks(for: subscription, asOf: today, at: now)
            if caughtUp != record {
                try await cancellations.save(caughtUp)
            }
            records[subscription.id] = caughtUp
        }
        return records
    }

    /// Acknowledged charges by subscription (spec §5.3, v1.4): the planner skips
    /// their reminders, which is what makes "Keeping it" survive this very
    /// cancel-all-then-replan pass.
    private func acknowledgedChargeDays(
        for live: [Subscription]
    ) async throws -> [UUID: Set<CalendarDay>] {
        var acknowledged: [UUID: Set<CalendarDay>] = [:]
        for subscription in live {
            let days = try await billingEvents.events(forSubscription: subscription.id)
                .filter { $0.acknowledgedAt != nil }
                .map(\.expectedDate)
            if !days.isEmpty { acknowledged[subscription.id] = Set(days) }
        }
        return acknowledged
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
            // Per subscription, not mid-subscription: each iteration saves its
            // rows before advancing its watermark, so a boundary here is the
            // one place the loop is consistent by construction.
            if Task.isCancelled {
                OttoLog.scheduling.notice("ledger pass cancelled, \(failures.count, privacy: .public) failures so far")
                break
            }
            // Before AND after, not only on change: "correctly did not
            // advance" is as much an observation as an advance, and omitting
            // the no-op cannot be told from never reaching this subscription.
            let before = try? await billingEvents.materializationWatermark(forSubscription: subscription.id)
            var created = 0
            do {
                _ = try await billingEvents.invalidateOutdatedUpcomingEvents(
                    for: subscription, asOf: today, at: now
                )
                created = try await billingEvents.materializeEvents(
                    for: subscription, from: today, horizonDays: Self.horizonDays,
                    maxReminderLeadDays: maxLead, at: now
                ).count
            } catch {
                failures.append(subscription.id)
            }
            let after = try? await billingEvents.materializationWatermark(forSubscription: subscription.id)
            OttoLog.scheduling.notice("""
                ledger \(subscription.id.uuidString, privacy: .public) \
                watermark=\(OttoLog.dayText(before), privacy: .public)->\(OttoLog.dayText(after), privacy: .public) \
                created=\(created, privacy: .public) \
                failed=\(failures.last == subscription.id, privacy: .public)
                """)
        }
        return failures
    }

    /// Translates budgeted reminders into request specs. A rung whose fire
    /// instant is still ahead gets a calendar trigger; a rung whose fire
    /// instant has PASSED gets a §6.2 catch-up - a short interval trigger,
    /// because a calendar trigger in the past never fires (Wave 10, defect A:
    /// the old code dropped these with a comment wrongly claiming §6.2 would
    /// recover them, and "schedule it immediately" was implemented for no
    /// kind at all).
    ///
    /// The catch-up's boundaries: the PLANNER emits a passed-instant rung
    /// only while the deadline it protects is not behind - a trial whose
    /// conversion passed plans no trial rungs at all - so a dead deadline can
    /// never reach here; and the delivered check is the never-fire-twice
    /// guarantee, read from the system's own delivery record (which the
    /// stable, content-derived identifier makes meaningful across passes)
    /// rather than from a stored flag a restore could desynchronize.
    /// What one translation pass reads besides the budgeted plan itself.
    private struct SpecInputs {
        let subscriptions: [Subscription]
        let cancellations: [UUID: CancellationEpisode]
        let delivered: Set<String>
        let now: Date
        let timeZone: TimeZone
        let locale: Locale
    }

    private func requestSpecs(
        for scheduled: [PlannedReminder],
        translating inputs: SpecInputs
    ) -> [NotificationRequestSpec] {
        let (delivered, now, timeZone) = (inputs.delivered, inputs.now, inputs.timeZone)
        let subscriptionsByID = Dictionary(
            uniqueKeysWithValues: inputs.subscriptions.map { ($0.id, $0) }
        )
        let policy = fireTimes()
        var specs: [NotificationRequestSpec] = []
        for reminder in scheduled {
            guard let subscription = subscriptionsByID[reminder.subscriptionID],
                  let fireDate = policy.fireDate(for: reminder, in: timeZone)
            else { continue }
            let identifier = NotificationPlanIdentifier.planned(reminder)
            let body = body(for: reminder, subscription: subscription, inputs: inputs)
            if fireDate > now {
                let time = policy.fireTime(for: reminder.kind)
                specs.append(NotificationRequestSpec(
                    identifier: identifier,
                    title: NotificationContent.title(for: reminder, subscription: subscription),
                    body: body,
                    year: reminder.day.year,
                    month: reminder.day.month,
                    day: reminder.day.day,
                    hour: time.hour,
                    minute: time.minute,
                    isTimeSensitive: reminder.kind.isTimeSensitive,
                    categoryIdentifier: NotificationCategory.identifier(for: reminder.kind)
                ))
            } else if !delivered.contains(identifier) {
                specs.append(NotificationRequestSpec(
                    identifier: identifier,
                    title: NotificationContent.title(for: reminder, subscription: subscription),
                    body: body,
                    year: reminder.day.year,
                    month: reminder.day.month,
                    day: reminder.day.day,
                    hour: 0,
                    minute: 0,
                    isTimeSensitive: reminder.kind.isTimeSensitive,
                    categoryIdentifier: NotificationCategory.identifier(for: reminder.kind),
                    catchUpIntervalSeconds: Self.catchUpIntervalSeconds
                ))
            }
        }
        return specs
    }

    /// The verification rung needs the cancellation date the record carries;
    /// every other kind is a pure function of the reminder.
    private func body(
        for reminder: PlannedReminder,
        subscription: Subscription,
        inputs: SpecInputs
    ) -> String {
        guard reminder.kind == .verification else {
            return NotificationContent.body(
                for: reminder, subscription: subscription, locale: inputs.locale
            )
        }
        return NotificationContent.verificationBody(
            subscription: subscription,
            cancelledAt: inputs.cancellations[subscription.id]?.markedCancelledAt,
            timeZone: inputs.timeZone,
            locale: inputs.locale
        )
    }
}
