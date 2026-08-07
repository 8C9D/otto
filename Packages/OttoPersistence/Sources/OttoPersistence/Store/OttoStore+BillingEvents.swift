import Foundation
import OttoDomain
import OttoRepositories
import SwiftData

extension OttoStore: BillingEventRepository {
    public func save(_ event: BillingEvent) async throws {
        let record: StoredBillingEvent
        if let existing = try storedEvent(id: event.id) {
            record = existing
        } else {
            guard let parent = try storedSubscription(id: event.subscriptionID, includingDeleted: true) else {
                throw RepositoryError.subscriptionNotFound(event.subscriptionID)
            }
            record = StoredBillingEvent()
            modelContext.insert(record)
            record.subscription = parent
        }
        record.update(from: event)
        try modelContext.save()
    }

    public func events(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] {
        try fetchEvents(subscriptionID: subscriptionID, includingDeleted: false)
    }

    public func eventsIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] {
        try fetchEvents(subscriptionID: subscriptionID, includingDeleted: true)
    }

    public func materializeEvents(
        for subscription: Subscription,
        from today: CalendarDay,
        horizonDays: Int,
        maxReminderLeadDays: Int,
        at instant: Date
    ) async throws -> [BillingEvent] {
        guard subscription.deletedAt == nil, horizonDays >= 0, maxReminderLeadDays >= 0 else {
            return []
        }

        // Which charge dates the EFFECTIVE status expects (spec §5.2a): a converted
        // trial is an active subscription anchored at its conversion date, whether
        // or not any flow persisted the flip - the six-weeks-in-a-drawer trial still
        // materializes its charges. An unconverted trial expects exactly one charge,
        // the conversion; paused generates no rows (spec §5.1); cancellation states
        // are watched by verification rather than expectation; archived is terminal.
        let chargeDates: [(day: CalendarDay, amountCents: Int)]
        switch subscription.effectiveStatus(asOf: today) {
        case .active:
            chargeDates = activeChargeDates(
                anchor: subscription.billingAnchor(asOf: today),
                amountCents: subscription.billingAmountCents(asOf: today),
                cycle: subscription.cycle,
                from: today,
                through: today.adding(days: horizonDays + maxReminderLeadDays)
            )
        case .trial:
            // §5.2b guarantees the term exists; the guard keeps this function total.
            guard let trial = subscription.trial else { return [] }
            let window = today...today.adding(days: horizonDays + maxReminderLeadDays)
            chargeDates = window.contains(trial.conversionDate)
                ? [(trial.conversionDate, trial.convertsToAmountCents)]
                : []
        case .paused, .cancellationPending, .cancelled, .archived:
            chargeDates = []
        }
        if chargeDates.isEmpty { return [] }

        guard let parent = try storedSubscription(id: subscription.id, includingDeleted: false) else {
            throw RepositoryError.subscriptionNotFound(subscription.id)
        }

        // Dedup against live rows and non-upcoming tombstones. A tombstoned
        // NON-upcoming row was deliberate history removal and must not resurrect;
        // a tombstoned .upcoming row is a §5.3 schedule-change invalidation
        // artifact, and the new sequence's rows are new records, not resurrections -
        // so it must not block the date it happens to share.
        let existingDates = Set(
            try storedEvents(subscriptionID: subscription.id)
                .filter { $0.deletedAt == nil || $0.state != BillingEvent.State.upcoming.rawValue }
                .compactMap(\.expectedDate)
        )

        var created: [BillingEvent] = []
        for candidate in chargeDates where !existingDates.contains(candidate.day.yyyymmdd) {
            let event = BillingEvent(
                id: UUID(),
                subscriptionID: subscription.id,
                expectedDate: candidate.day,
                expectedAmountCents: candidate.amountCents,
                state: .upcoming,
                createdAt: instant,
                updatedAt: instant
            )
            let record = StoredBillingEvent()
            modelContext.insert(record)
            record.subscription = parent
            record.update(from: event)
            created.append(event)
        }
        try modelContext.save()
        return created
    }

    public func invalidateOutdatedUpcomingEvents(
        for subscription: Subscription,
        asOf today: CalendarDay,
        at instant: Date
    ) async throws -> [BillingEvent] {
        // Spec §5.3 (v1.3): a changed anchor, cycle, or amount changes the sequence,
        // and .upcoming rows for the old sequence are phantom charges on dates that
        // will never happen. Soft-delete every live .upcoming row that no longer
        // matches the effective sequence; touch NOTHING in any other state - a
        // confirmed charge is history, and history does not change because a
        // schedule did. Invalidated rows are tombstoned, never resurrected; the new
        // sequence's rows are new records (materializeEvents' dedup ignores
        // tombstoned .upcoming rows for exactly this reason).
        let upcomingRaw = BillingEvent.State.upcoming.rawValue
        let candidates = try storedEvents(subscriptionID: subscription.id)
            .filter { $0.deletedAt == nil && $0.state == upcomingRaw }

        var invalidated: [BillingEvent] = []
        for record in candidates {
            guard let stored = record.expectedDate,
                  let day = CalendarDay(yyyymmdd: stored),
                  let amount = record.expectedAmountCents
            else { continue }
            if matchesExpectedSequence(day: day, amountCents: amount, of: subscription, asOf: today) {
                continue
            }
            record.deletedAt = instant
            record.updatedAt = instant
            if let event = try? record.toDomain() {
                invalidated.append(event)
            }
        }
        if !invalidated.isEmpty {
            try modelContext.save()
        }
        return invalidated.sorted { ($0.expectedDate, $0.id.uuidString) < ($1.expectedDate, $1.id.uuidString) }
    }

    /// Whether one (date, amount) pair is a charge the subscription's EFFECTIVE
    /// schedule (spec §5.2a) still expects.
    private func matchesExpectedSequence(
        day: CalendarDay,
        amountCents: Int,
        of subscription: Subscription,
        asOf today: CalendarDay
    ) -> Bool {
        switch subscription.effectiveStatus(asOf: today) {
        case .active:
            return amountCents == subscription.billingAmountCents(asOf: today)
                && isBillingOccurrence(
                    day, anchor: subscription.billingAnchor(asOf: today), cycle: subscription.cycle
                )
        case .trial:
            guard let trial = subscription.trial else { return false }
            return day == trial.conversionDate && amountCents == trial.convertsToAmountCents
        case .paused, .cancellationPending, .cancelled, .archived:
            // A status change is not a schedule change; §5.3's rule is scoped to
            // anchor/cycle/amount edits, so rows are left for the owning flow.
            return true
        }
    }

    /// Every charge date in `[today, windowEnd]`, each computed directly from the
    /// anchor by the date engine - never by adding an interval to a previous date
    /// (spec §4.2 rule 3). The window includes today itself: today's charge is
    /// still worth confirming. The anchor and amount are the caller's EFFECTIVE
    /// values (spec §5.2a), so a converted trial's sequence runs from its
    /// conversion date at the converted price.
    private func activeChargeDates(
        anchor: CalendarDay,
        amountCents: Int,
        cycle: BillingCycle,
        from today: CalendarDay,
        through windowEnd: CalendarDay
    ) -> [(day: CalendarDay, amountCents: Int)] {
        var dates: [(day: CalendarDay, amountCents: Int)] = []
        var cursor = today.adding(days: -1)
        while true {
            let chargeDay = nextBillingDate(after: cursor, anchor: anchor, cycle: cycle)
            guard chargeDay <= windowEnd else { break }
            cursor = chargeDay
            dates.append((chargeDay, amountCents))
        }
        return dates
    }

    private func storedEvent(id: UUID) throws -> StoredBillingEvent? {
        var descriptor = FetchDescriptor<StoredBillingEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func storedEvents(subscriptionID: UUID) throws -> [StoredBillingEvent] {
        try modelContext.fetch(
            FetchDescriptor<StoredBillingEvent>(predicate: #Predicate { $0.subscriptionID == subscriptionID })
        )
    }

    private func fetchEvents(subscriptionID: UUID, includingDeleted: Bool) throws -> [BillingEvent] {
        var records = try storedEvents(subscriptionID: subscriptionID)
        if !includingDeleted {
            records = liveOnly(records, deletedAt: \.deletedAt)
        }
        return mapSkippingFailures(records) { try $0.toDomain() }
            .sorted { ($0.expectedDate, $0.id.uuidString) < ($1.expectedDate, $1.id.uuidString) }
    }
}
