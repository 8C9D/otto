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

        guard let parent = try storedSubscription(id: subscription.id, includingDeleted: false) else {
            throw RepositoryError.subscriptionNotFound(subscription.id)
        }

        // The window reaches back to the stored watermark (spec §5.3, v1.5), so a
        // charge date that fell between passes - the founding scenario's
        // conversion - still gets its row. The STORED record's watermark governs,
        // not the passed value's: the caller's snapshot may predate the last pass.
        // A nil watermark is a pre-v1.5 row; it materializes from today once and
        // carries a watermark from this pass on.
        let storedWatermark = parent.lastMaterializedThrough.flatMap(CalendarDay.init(yyyymmdd:))
        let windowStart = min(storedWatermark ?? today, today)
        let windowEnd = today.adding(days: horizonDays + maxReminderLeadDays)

        // An indefinitely paused subscription has no derivable resume date, so
        // its watermark must not advance (spec §5.3, v1.6): it freezes at the
        // pause, and the manual resume backfills from it. Advancing here is how
        // Wave 5.5's fourth escape route worked - the pause ends, and the dates
        // it covered are behind a watermark that vouches for rows that never
        // existed. A pause WITH an end date advances normally, because its
        // resumed sequence materializes below while the pause runs out.
        if subscription.effectiveStatus(asOf: today) == .paused && subscription.pauseEndsOn == nil {
            return []
        }

        // Which charges the effective status expects is a domain decision
        // (spec §5.2a, §5.3) - this store only creates the rows it names.
        let chargeDates = expectedCharges(
            for: subscription, from: windowStart, through: windowEnd, asOf: today
        )
        if chargeDates.isEmpty {
            // An empty window was still observed: nothing was expected in it, and
            // the watermark records that so the next pass need not re-ask.
            parent.lastMaterializedThrough = windowEnd.yyyymmdd
            try modelContext.save()
            return []
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
        // Advanced in the same save as the rows it vouches for: the watermark
        // asserts "every expected charge through this day has a row", and must
        // never persist without them (spec §5.3, v1.5). `updatedAt` is left
        // alone - this is scheduler bookkeeping, not a user edit, and bumping it
        // would make every pass look like a user modification to conflict
        // resolution (spec §5.3, v1.6: the watermark is device-local, never
        // synced, and Wave 6 must move it out of the CloudKit-backed schema).
        parent.lastMaterializedThrough = windowEnd.yyyymmdd
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
