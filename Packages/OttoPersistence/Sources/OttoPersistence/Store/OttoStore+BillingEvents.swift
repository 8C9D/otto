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

        // Which charges the effective status expects is a domain decision
        // (spec §5.2a, §5.3) - this store only creates the rows it names.
        let chargeDates = expectedCharges(
            for: subscription,
            from: today,
            through: today.adding(days: horizonDays + maxReminderLeadDays)
        )
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
        // Spec §5.3: any change that alters the expected sequence - an edited
        // anchor, cycle, or amount, and since v1.4 a transition into a
        // non-expecting status - leaves .upcoming rows behind as phantom charges.
        // Soft-delete every live .upcoming row the effective sequence no longer
        // expects (a domain decision); touch NOTHING in any other state - a
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
            if isExpectedCharge(day: day, amountCents: amount, for: subscription, asOf: today) {
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
