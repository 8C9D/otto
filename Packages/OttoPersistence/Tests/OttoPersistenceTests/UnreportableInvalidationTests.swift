import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence
// R0-11. `invalidateOutdatedUpcomingEvents` mutated a row and then decided
// whether to SAVE by asking whether the row could be described back to the
// caller - two different questions. A candidate that passes this method's own
// guards (a future date, a readable packed day, an amount) can still fail
// `toDomain()`, because `toDomain()` also requires the audit fields a partial
// sync may not have delivered yet.
//
// Measured at `54bb611`, before the fix, on two such rows:
//
//     reported=0 ("nothing invalidated" is true)
//     committedTombstonesRightAfter=0
//     committedTombstonesAfterAnUnrelatedSave=2
//
// Both rows soft-deleted in memory, the caller told nothing had happened, no
// save run - and the next unrelated `save()` on the actor's shared context
// flushing both tombstones in a transaction that had nothing to do with them.
extension SerializedPersistenceTests {
    @Suite("Invalidating a row that cannot be described (R0-11)")
    struct UnreportableInvalidationTests {

        private let instant = Date(timeIntervalSince1970: 8_000)
        private let editInstant = Date(timeIntervalSince1970: 9_000)

        /// Nils the audit field on every future-dated row, which is what a
        /// partially synced arrival looks like: the columns this method reads
        /// are present, and the one `toDomain()` needs is not.
        private func breakFutureRows(
            after today: CalendarDay, in containers: OttoContainers
        ) throws -> Int {
            let context = ModelContext(containers.main)
            var broken = 0
            for row in try context.fetch(FetchDescriptor<StoredBillingEvent>())
            where (row.expectedDate ?? 0) > today.yyyymmdd {
                row.createdAt = nil
                broken += 1
            }
            try context.save()
            return broken
        }

        /// What a SEPARATE context can see - i.e. what is actually committed,
        /// rather than what is pending in the store's own context.
        private func committedTombstones(in containers: OttoContainers) throws -> Int {
            try ModelContext(containers.main)
                .fetch(FetchDescriptor<StoredBillingEvent>())
                .count { $0.deletedAt != nil }
        }

        @Test("⛔ a soft-delete this method cannot describe is still committed by it")
        func theSoftDeleteIsCommitted() async throws {
            let (store, containers) = try makeStore()
            let today = try day(2026, 8, 6)
            let original = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(original)
            _ = try await store.materializeEvents(
                for: original, from: today, horizonDays: 40, maxReminderLeadDays: 0, at: instant
            )
            #expect(try breakFutureRows(after: today, in: containers) == 2)

            let edited = try makeSubscription(amountCents: 1299, cycleStartDay: try day(2026, 1, 15))
            try await store.save(edited)
            let invalidated = try await store.invalidateOutdatedUpcomingEvents(
                for: edited, asOf: today, at: editInstant
            )

            // The return value still undercounts, and that is not the defect:
            // there is no `BillingEvent` to hand back for a row that will not
            // map. What the defect was is everything below.
            #expect(invalidated.isEmpty)
            // Committed by THIS call, visible from a context that never saw the
            // pending change. At `54bb611` this was 0.
            #expect(try committedTombstones(in: containers) == 2)
        }

        /// The reason the row is tombstoned rather than skipped: a LIVE
        /// `.upcoming` row blocks its own date in `materializeEvents`' dedup,
        /// which reads the raw column and never maps it. Leaving an unmappable
        /// phantom alive would silently prevent the correct replacement row
        /// from ever being written - a missing ledger row, which is F6's
        /// family.
        @Test("⛔ tombstoning it is what lets the correct row be written")
        func thePhantomStopsBlockingItsDate() async throws {
            let (store, containers) = try makeStore()
            let today = try day(2026, 8, 6)
            let original = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(original)
            let created = try await store.materializeEvents(
                for: original, from: today, horizonDays: 40, maxReminderLeadDays: 0, at: instant
            )
            let blockedDates = created.map(\.expectedDate)
            #expect(try breakFutureRows(after: today, in: containers) == 2)

            let edited = try makeSubscription(amountCents: 1299, cycleStartDay: try day(2026, 1, 15))
            try await store.save(edited)
            _ = try await store.invalidateOutdatedUpcomingEvents(
                for: edited, asOf: today, at: editInstant
            )
            let rematerialized = try await store.materializeEvents(
                for: edited, from: today, horizonDays: 40, maxReminderLeadDays: 0, at: editInstant
            )

            #expect(rematerialized.map(\.expectedDate) == blockedDates)
            #expect(rematerialized.allSatisfy { $0.expectedAmountCents == 1299 })
        }

        /// The undercount is deliberate and must not be silent. This is the
        /// only surface that names the row, so it is guarded like every other
        /// log statement in this tree.
        ///
        /// **Cost, stated because the round-4 prompt requires it**: this is a
        /// tenth `OSLogStore(scope: .currentProcessIdentifier)` read in the
        /// tree and a third in this target, at roughly 7-11 s. A shared query
        /// would not do: the two existing persistence readers assert about the
        /// watermark path and the mapping-privacy path, each over its own
        /// `since` window, and folding a third subject into either makes that
        /// test's failure ambiguous between two unrelated causes - which is the
        /// misdiagnosis the canary exists to prevent, reintroduced one level up.
        @Test("⛔ the row it could not report is named in the log")
        func theUnreportableRowIsNamed() async throws {
            let (store, containers) = try makeStore()
            let today = try day(2026, 8, 6)
            // Its OWN subscription index, and every assertion below is filtered
            // to that identifier. The two sibling tests in this suite drive the
            // same production path and therefore emit the same lines, and
            // `OSLogStore.position(date:)` reaches ~80 ms behind `since`, so the
            // window legitimately holds theirs too - measured, as six matches
            // where this test controls two. Round 3's flake, one file over.
            let mineIndex = 7011
            let original = try makeSubscription(index: mineIndex, cycleStartDay: try day(2026, 1, 15))
            try await store.save(original)
            _ = try await store.materializeEvents(
                for: original, from: today, horizonDays: 40, maxReminderLeadDays: 0, at: instant
            )
            #expect(try breakFutureRows(after: today, in: containers) == 2)
            let edited = try makeSubscription(
                index: mineIndex, amountCents: 1299, cycleStartDay: try day(2026, 1, 15)
            )
            try await store.save(edited)

            let since = Date()
            OttoLogProbe.emitCanary()
            _ = try await store.invalidateOutdatedUpcomingEvents(
                for: edited, asOf: today, at: editInstant
            )

            let lines = try OttoLogProbe.persistenceLines(since: since)
            try OttoLogProbe.requireDelivered(lines)
            let mine = edited.id.uuidString.lowercased()
            let named = lines.filter {
                $0.contains("Invalidation tombstoned an unreportable row")
                    && $0.lowercased().contains(mine)
            }
            #expect(named.count == 2, "two rows were tombstoned unreportably and \(named.count) were named")
            // The packed day, which is what a reader needs to find the row, and
            // nothing about what the subscription costs or who it is with.
            #expect(named.contains { $0.contains("20260815") })
            #expect(named.contains { $0.contains("20260915") })
            for line in named {
                // 1099 is what the ROWS carry - they were materialized from the
                // original subscription - and 1299 is the edited amount that
                // made them phantom. An earlier version asserted only the
                // latter, so a line leaking the row's own amount would have
                // passed (`reviews-4/REVIEW-4.md`).
                #expect(!line.contains("1099"))
                #expect(!line.contains("1299"))
                #expect(!line.contains("$"))
            }
        }
    }
}
