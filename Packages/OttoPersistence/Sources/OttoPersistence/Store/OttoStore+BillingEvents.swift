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
        horizonDays: Int
    ) async throws -> [BillingEvent] {
        // Only an active subscription expects charges: paused generates no rows
        // (spec §5.1), a trial has no charges before conversion (Wave 5 owns the
        // transition), and cancellation states are watched by verification rather
        // than expectation.
        guard subscription.status == .active, subscription.deletedAt == nil, horizonDays >= 0 else {
            return []
        }
        guard let parent = try storedSubscription(id: subscription.id, includingDeleted: false) else {
            throw RepositoryError.subscriptionNotFound(subscription.id)
        }

        // Dedup against every existing row INCLUDING tombstones: a soft-deleted row
        // was deliberately removed, and re-materializing it would resurrect it.
        let existingDates = Set(
            try storedEvents(subscriptionID: subscription.id).compactMap(\.expectedDate)
        )

        // Each candidate is computed directly from the anchor by the date engine -
        // never by adding an interval to a previous date (spec §4.2 rule 3). The
        // window includes today itself: today's charge is still worth confirming.
        let horizonEnd = today.adding(days: horizonDays)
        var created: [BillingEvent] = []
        var cursor = today.adding(days: -1)
        while true {
            let chargeDay = nextBillingDate(
                after: cursor, anchor: subscription.cycleStartDay, cycle: subscription.cycle
            )
            guard chargeDay <= horizonEnd else { break }
            cursor = chargeDay
            guard !existingDates.contains(chargeDay.yyyymmdd) else { continue }

            let event = BillingEvent(
                id: UUID(),
                subscriptionID: subscription.id,
                expectedDate: chargeDay,
                expectedAmountCents: subscription.amountCents,
                state: .upcoming
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
