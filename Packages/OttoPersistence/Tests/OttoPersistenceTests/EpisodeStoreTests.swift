import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// Wave 8.5's storage behaviours (spec §5.3, §5.3a): episode CRUD, the
// past-dated-row rule, and the watermark freeze on cancellation states.

@Suite("Cancellation episode storage (spec §5.3a)")
struct CancellationEpisodeStoreTests {

    @Test("episodes accumulate per subscription; the open one is the current watch")
    func episodesAccumulate() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
        )
        try await store.save(subscription)

        // An earlier cancellation, un-cancelled last spring.
        var abandoned = try makeCancellationEpisode(
            index: 601, subscriptionID: subscription.id,
            nextChargeDateIfNotCancelled: try day(2026, 4, 1)
        )
        abandoned.endedAt = Date(timeIntervalSince1970: 5_000)
        abandoned.outcome = .abandoned
        try await store.save(abandoned)

        // The current one.
        var current = try makeCancellationEpisode(
            index: 602, subscriptionID: subscription.id,
            nextChargeDateIfNotCancelled: try day(2026, 9, 1)
        )
        current.markedCancelledAt = Date(timeIntervalSince1970: 7_000)
        current.statusAtStart = .active
        try await store.save(current)

        #expect(try await store.episodes(forSubscription: subscription.id).count == 2)
        // Newest first, and the open one is found by openness, not recency.
        #expect(try await store.episodes(forSubscription: subscription.id).map(\.id)
            == [current.id, abandoned.id])
        #expect(try await store.openEpisode(forSubscription: subscription.id) == current)

        // Saving an edit rewrites the row carrying that id - no new row.
        var updated = current
        updated.evidenceNote = "conf #999"
        updated.updatedAt = Date(timeIntervalSince1970: 8_000)
        try await store.save(updated)
        #expect(try await store.episodes(forSubscription: subscription.id).count == 2)
        #expect(try await store.openEpisode(forSubscription: subscription.id) == updated)
    }

    @Test("deleting a PAUSED subscription stays readable and exportable - the tombstoned whole is history")
    func deletedPausedSubscriptionExports() async throws {
        // The §5.3a invariants' status-coupled halves apply to live records
        // only: the delete cascade tombstones the open episode with its
        // subscription, and a backup must still carry both (spec §3.5 - a
        // soft-deleted row is communicable data).
        let (store, _) = try makeStore()
        let paused = try makeSubscription(status: .paused, cycleStartDay: try day(2026, 1, 15))
        try await store.save(paused)

        try await store.deleteSubscription(withID: paused.id, at: Date(timeIntervalSince1970: 9_000))

        let everything = try await store.subscriptionsIncludingDeleted()
        #expect(everything.count == 1)
        #expect(everything.first?.deletedAt == Date(timeIntervalSince1970: 9_000))
        #expect(everything.first?.pauseEpisodes.first?.deletedAt == Date(timeIntervalSince1970: 9_000))
        // And the export path - the read that throws instead of skipping -
        // still produces the complete snapshot.
        let snapshot = try await store.completeSnapshot()
        #expect(snapshot.subscriptions.count == 1)
        _ = try exportData(from: snapshot, exportedAt: Date(timeIntervalSince1970: 10_000))
    }

    @Test("a subscription's pause history round-trips: closed and open episodes, every field")
    func pauseEpisodesRoundTrip() async throws {
        let (store, _) = try makeStore()
        let winter = PauseEpisode(
            id: try fixtureUUID(701),
            startedOn: try day(2025, 11, 1),
            scheduledResumeOn: try day(2026, 2, 1),
            endedOn: try day(2026, 2, 1),
            outcome: .resumed,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let current = PauseEpisode(
            id: try fixtureUUID(702),
            startedOn: try day(2026, 6, 1),
            scheduledResumeOn: nil,
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 3_000)
        )
        let subscription = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 1, 15),
            pauseEpisodes: [winter, current]
        )

        try await store.save(subscription)
        let loaded = try #require(await store.subscription(withID: subscription.id))

        #expect(loaded == subscription)
        #expect(loaded.pauseEpisodes == [winter, current])
        #expect(loaded.currentPauseEpisode == current)

        // Resuming closes the open episode in place; history keeps both rows.
        let resumed = try #require(loaded.resuming(on: try day(2026, 8, 7), at: Date(timeIntervalSince1970: 9_000)))
        try await store.save(resumed)
        let reloaded = try #require(await store.subscription(withID: subscription.id))
        #expect(reloaded.pauseEpisodes.count == 2)
        #expect(reloaded.currentPauseEpisode == nil)
        #expect(reloaded.pauseEpisodes.last?.endedOn == (try day(2026, 8, 7)))
        #expect(reloaded.pauseEpisodes.last?.outcome == .resumed)
    }
}

@Suite("Invalidation never touches past-dated rows (spec §5.3, v1.8)")
struct PastDatedInvalidationTests {

    private let instant = Date(timeIntervalSince1970: 8_000)
    private let editInstant = Date(timeIntervalSince1970: 9_000)

    @Test("a price edit tombstones only FUTURE old-amount rows - an unacknowledged past row is history")
    func priceEditSparesThePast() async throws {
        // The Wave 8 bug: monthly on the 15th, materialized through November,
        // and the July and August 15 rows passed unconfirmed. Editing the
        // price used to tombstone them with nothing to recreate them - the
        // charge dates vanished from the ledger.
        let (store, _) = try makeStore()
        let original = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
        try await store.save(original)
        _ = try await store.materializeEvents(
            for: original, from: try day(2026, 7, 1), horizonDays: 90,
            maxReminderLeadDays: 30, at: instant
        )
        let editDay = try day(2026, 8, 20)
        let julyCharge = try day(2026, 7, 15)
        let augustCharge = try day(2026, 8, 15)
        let before = try await store.events(forSubscription: original.id)
        let pastDates = before.map(\.expectedDate).filter { $0 <= editDay }
        #expect(pastDates.contains(julyCharge))
        #expect(pastDates.contains(augustCharge))

        let edited = try makeSubscription(amountCents: 1299, cycleStartDay: try day(2026, 1, 15))
        try await store.save(edited)
        let invalidated = try await store.invalidateOutdatedUpcomingEvents(
            for: edited, asOf: editDay, at: editInstant
        )

        // Only future-dated rows went; the passed charge dates stay in the
        // ledger at the amount that was expected when they passed.
        #expect(invalidated.allSatisfy { $0.expectedDate > editDay })
        let after = try await store.events(forSubscription: original.id)
        #expect(after.contains { $0.expectedDate == julyCharge && $0.expectedAmountCents == 1099 })
        #expect(after.contains { $0.expectedDate == augustCharge && $0.expectedAmountCents == 1099 })
        #expect(after.filter { $0.expectedDate > editDay }.isEmpty)
    }

    @Test("a row dated today survives an edit too - whether today's charge landed is unknowable")
    func todayRowSurvives() async throws {
        let (store, _) = try makeStore()
        let today = try day(2026, 8, 15)
        let original = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
        try await store.save(original)
        _ = try await store.materializeEvents(
            for: original, from: today, horizonDays: 60, maxReminderLeadDays: 0, at: instant
        )

        let edited = try makeSubscription(amountCents: 1299, cycleStartDay: try day(2026, 1, 15))
        try await store.save(edited)
        let invalidated = try await store.invalidateOutdatedUpcomingEvents(
            for: edited, asOf: today, at: editInstant
        )

        #expect(invalidated.allSatisfy { $0.expectedDate > today })
        let live = try await store.events(forSubscription: original.id)
        #expect(live.contains { $0.expectedDate == today && $0.expectedAmountCents == 1099 })
    }
}

@Suite("The watermark freezes on cancellation states (spec §5.3, §5.4)")
struct CancellationWatermarkFreezeTests {

    private let instant = Date(timeIntervalSince1970: 8_000)

    @Test("a pending cancellation materializes nothing and leaves the watermark alone")
    func pendingFreezesWatermark() async throws {
        let (store, container) = try makeStore()
        let pending = try makeSubscription(
            status: .cancellationPending,
            cycleStartDay: try day(2026, 1, 15),
            lastMaterializedThrough: try day(2026, 8, 1)
        )
        try await store.save(pending)

        let created = try await store.materializeEvents(
            for: pending, from: try day(2026, 10, 20), horizonDays: 90,
            maxReminderLeadDays: 0, at: instant
        )

        #expect(created.isEmpty)
        let context = ModelContext(container)
        let stored = try #require(try context.fetch(FetchDescriptor<StoredSubscription>()).first)
        // NOT advanced to the window's end: an un-cancel re-expects these
        // dates retroactively, and a vouched-for-but-unobserved window is the
        // founding scenario's shape.
        #expect(stored.lastMaterializedThrough == 20_260_801)
    }

    @Test("un-cancel then next pass: every charge date the watch covered gets its row")
    func backfillAfterAbandon() async throws {
        let (store, _) = try makeStore()
        let pending = try makeSubscription(
            status: .cancellationPending,
            cycleStartDay: try day(2026, 1, 15),
            lastMaterializedThrough: try day(2026, 8, 1)
        )
        try await store.save(pending)
        // Three passes during the watch: nothing materializes, nothing advances.
        for passDay in [try day(2026, 9, 1), try day(2026, 10, 1), try day(2026, 11, 5)] {
            _ = try await store.materializeEvents(
                for: pending, from: passDay, horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )
        }

        // The un-cancel restores .active (the flow's job); the next ordinary
        // pass backfills from the frozen watermark.
        let restored = try #require(
            pending.abandoningCancellation(restoringTo: .active, at: instant)
        )
        try await store.save(restored)
        let created = try await store.materializeEvents(
            for: restored, from: try day(2026, 11, 5), horizonDays: 30,
            maxReminderLeadDays: 0, at: instant
        )

        // Aug 15, Sep 15, Oct 15 fell inside the watch and were never
        // observed; they materialize now, with the ordinary future ones.
        let dates = created.map(\.expectedDate)
        #expect(dates.contains(try day(2026, 8, 15)))
        #expect(dates.contains(try day(2026, 9, 15)))
        #expect(dates.contains(try day(2026, 10, 15)))
        #expect(dates.contains(try day(2026, 11, 15)))
    }
}
