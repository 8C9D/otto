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
        // conversion - still gets its row. The STORED watermark governs, not the
        // passed value's: the caller's snapshot may predate the last pass. Since
        // Wave 6A it lives in the device-state store (spec §5.3), one row per
        // subscription. A nil watermark is a pre-v1.5 row; it materializes from
        // today once and carries a watermark from this pass on.
        let storedWatermark = try deviceWatermark(for: subscription.id)
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

        // A pending or cancelled subscription expects no charges, but its exit
        // can re-expect them RETROACTIVELY: un-cancelling (spec §5.4, §5.3a)
        // means the vendor was charging all along, and every date the watch
        // covered needs its ledger row. So the watermark freezes here exactly
        // like the indefinite pause above - advancing it would vouch for dates
        // nothing observed, and the un-cancel backfill would find them stranded.
        // Archival ends the freeze question: archived is terminal and
        // materializes nothing ever again.
        let effective = subscription.effectiveStatus(asOf: today)
        if effective == .cancellationPending || effective == .cancelled {
            return []
        }

        // Which charges the effective status expects is a domain decision
        // (spec §5.2a, §5.3) - this store only creates the rows it names.
        let chargeDates = expectedCharges(
            for: subscription, from: windowStart, through: windowEnd, asOf: today
        )
        if chargeDates.isEmpty {
            // An empty window was still observed: nothing was expected in it, and
            // the watermark records that so the next pass need not re-ask. Only
            // the device store changes here - there are no rows to vouch for.
            try setDeviceWatermark(windowEnd, for: subscription.id)
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
        // Advanced only AFTER the rows it vouches for commit: the watermark
        // asserts "every expected charge through this day has a row", and must
        // never persist without them (spec §5.3, v1.5). The two stores cannot
        // share one atomic save since Wave 6A moved the watermark out of the
        // synced schema, so the ordering carries the invariant - a crash
        // between the saves leaves rows without an advanced watermark, and the
        // next pass re-observes them idempotently. `updatedAt` is left alone -
        // this is scheduler bookkeeping, not a user edit, and bumping it would
        // make every pass look like a user modification to conflict resolution
        // (spec §5.3, v1.6: the watermark is device-local and never synced).
        try modelContext.save()
        try setDeviceWatermark(windowEnd, for: subscription.id)
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
        // R0-11. Counted separately from `invalidated`, because they are
        // different questions: this one is "did this method change a row", and
        // the save below depends on THAT and not on whether the changed row
        // could be described back to the caller.
        //
        // Measured at `54bb611`, before this existed, on two future-dated
        // `.upcoming` rows whose `createdAt` a partial sync had left nil - a
        // shape `toDomain()` rejects and this method's own guards do not:
        //
        //     reported=0 ("nothing invalidated" is true)
        //     committedTombstonesRightAfter=0
        //     committedTombstonesAfterAnUnrelatedSave=2
        //
        // Both rows were soft-deleted in memory, the caller was told nothing
        // had happened, no save ran - and the next unrelated `save()` on this
        // actor's context flushed both tombstones in a transaction that had
        // nothing to do with them.
        var mutated = 0
        for record in candidates {
            guard let stored = record.expectedDate,
                  let day = CalendarDay(yyyymmdd: stored),
                  let amount = record.expectedAmountCents
            else { continue }
            // Only future-dated rows are invalidated (spec §5.3, v1.8): a
            // past-dated row is history whether or not it was acknowledged -
            // a record of what was expected on a date that already happened -
            // and an edit applies going forward, never retroactively. Wave 8
            // found the old behaviour silently deleting unconfirmed past
            // charges from the ledger the moment a price was corrected. A row
            // dated today stays too: whether today's charge already landed is
            // unknowable here, and Otto surfaces discrepancies rather than
            // deciding history was wrong.
            if day <= today {
                continue
            }
            if isExpectedCharge(day: day, amountCents: amount, for: subscription, asOf: today) {
                continue
            }
            record.deletedAt = monotonicStamp(instant, notBefore: record.createdAt)
            record.updatedAt = monotonicStamp(instant, notBefore: record.updatedAt)
            mutated += 1
            do {
                invalidated.append(try record.toDomain())
            } catch {
                // The row IS tombstoned - deliberately, because a live
                // `.upcoming` row blocks its own date in `materializeEvents`'
                // dedup above, which reads the raw column and never maps it. An
                // unmappable phantom left live would silently prevent the
                // correct replacement row from ever being written.
                //
                // What it cannot do is come back in `invalidated`: there is no
                // `BillingEvent` to return. So the return value undercounts
                // here by construction, and this line is the only place that
                // says so. Never the amount or the vendor - an opaque row id, a
                // packed calendar day, and the redacted mapping summary.
                mappingLogger.error("""
                    Invalidation tombstoned an unreportable row \
                    subscription=\(subscription.id.uuidString, privacy: .public) \
                    day=\(stored, privacy: .public) \
                    reason=\(mappingLogSummary(error), privacy: .public)
                    """)
            }
        }
        // On `mutated`, not on `invalidated`. Those differ exactly when a row
        // was tombstoned and could not be described, and keying the save on the
        // describable ones is what left the soft-deletes uncommitted.
        if mutated > 0 {
            try modelContext.save()
        }
        return invalidated.sorted { ($0.expectedDate, $0.id.uuidString) < ($1.expectedDate, $1.id.uuidString) }
    }

    // MARK: - The device watermark (spec §5.3, Wave 6B-Prep)

    public func materializationWatermark(forSubscription subscriptionID: UUID) async throws -> CalendarDay? {
        try deviceWatermark(for: subscriptionID)
    }

    public func initializeMaterializationWatermark(
        forSubscription subscriptionID: UUID, at day: CalendarDay
    ) async throws {
        guard try deviceWatermark(for: subscriptionID) == nil else { return }
        try setDeviceWatermark(day, for: subscriptionID)
    }

    public func rewindMaterializationWatermark(
        forSubscription subscriptionID: UUID, to day: CalendarDay
    ) async throws {
        guard let stored = try deviceWatermark(for: subscriptionID), day < stored else { return }
        try setDeviceWatermark(day, for: subscriptionID)
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
