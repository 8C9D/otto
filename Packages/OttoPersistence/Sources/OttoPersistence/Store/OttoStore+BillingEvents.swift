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

        // Which charge dates a status expects (spec §5.3): active expects its whole
        // cycle sequence; a trial expects exactly one - the conversion charge, the
        // charge this app exists to catch; paused generates no rows (spec §5.1);
        // cancellation states are watched by verification rather than expectation;
        // archived is terminal.
        let chargeDates: [(day: CalendarDay, amountCents: Int)]
        switch subscription.status {
        case .active:
            chargeDates = activeChargeDates(
                for: subscription, from: today, through: today.adding(days: horizonDays + maxReminderLeadDays)
            )
        case .trial:
            // A trial subscription with no trial term cannot place its conversion
            // charge; the reminder planner treats that state the same way.
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

        // Dedup against every existing row INCLUDING tombstones: a soft-deleted row
        // was deliberately removed, and re-materializing it would resurrect it.
        let existingDates = Set(
            try storedEvents(subscriptionID: subscription.id).compactMap(\.expectedDate)
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

    /// Every charge date in `[today, windowEnd]`, each computed directly from the
    /// anchor by the date engine - never by adding an interval to a previous date
    /// (spec §4.2 rule 3). The window includes today itself: today's charge is
    /// still worth confirming.
    private func activeChargeDates(
        for subscription: Subscription,
        from today: CalendarDay,
        through windowEnd: CalendarDay
    ) -> [(day: CalendarDay, amountCents: Int)] {
        var dates: [(day: CalendarDay, amountCents: Int)] = []
        var cursor = today.adding(days: -1)
        while true {
            let chargeDay = nextBillingDate(
                after: cursor, anchor: subscription.cycleStartDay, cycle: subscription.cycle
            )
            guard chargeDay <= windowEnd else { break }
            cursor = chargeDay
            dates.append((chargeDay, subscription.amountCents))
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
