import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

extension SerializedPersistenceTests {
    @Suite("Export and import against the real store (Wave 8)")
    struct DataTransferTests {

        /// Seeds a store through its public save paths with every model type,
        /// including a soft-deleted subscription and a stored watermark.
        private func seedRichStore() async throws -> (store: OttoStore, containers: OttoContainers) {
            let (store, containers) = try makeStore()

            let active = try makeSubscription(
                index: 1,
                cycleStartDay: try day(2026, 1, 15),
                trial: try makeTrialTerm(index: 501, startDate: try day(2026, 1, 1))
            )
            try await store.save(active)
            try await store.initializeMaterializationWatermark(
                forSubscription: active.id, at: try day(2026, 9, 1)
            )
            let trial = try makeSubscription(
                index: 2, status: .trial, cycleStartDay: try day(2026, 8, 1),
                trial: try makeTrialTerm(index: 502, startDate: try day(2026, 8, 1))
            )
            try await store.save(trial)
            let cancelled = try makeSubscription(index: 3, status: .cancelled, cycleStartDay: try day(2026, 2, 1))
            try await store.save(cancelled)
            let doomed = try makeSubscription(index: 4, cycleStartDay: try day(2026, 3, 1))
            try await store.save(doomed)
            try await store.save(try makeBillingEvent(index: 103, subscriptionID: doomed.id, expectedDate: try day(2026, 3, 1)))

            // Both episode tables with MULTIPLE episodes each (spec §5.3a): two
            // separate pause periods - one closed by a resume, one current...
            try await store.save(try twicePausedSubscription())

            try await store.save(try makeBillingEvent(index: 101, subscriptionID: active.id, expectedDate: try day(2026, 1, 15)))
            try await store.save(try makeBillingEvent(index: 102, subscriptionID: active.id, expectedDate: try day(2026, 2, 15)))
            try await store.append(try makePriceChange(index: 201, subscriptionID: active.id, effectiveDate: try day(2025, 3, 1)))
            try await store.save(try makeCancellationEpisode(
                index: 601, subscriptionID: cancelled.id, nextChargeDateIfNotCancelled: try day(2026, 9, 1)
            ))
            // ...and the same subscription's earlier cancellation, un-cancelled
            // (§5.3a: an abandoned episode is history and must survive a backup).
            var abandoned = try makeCancellationEpisode(
                index: 602, subscriptionID: cancelled.id, nextChargeDateIfNotCancelled: try day(2026, 5, 1)
            )
            abandoned.markedCancelledAt = Date(timeIntervalSince1970: 3_000)
            abandoned.endedAt = Date(timeIntervalSince1970: 3_500)
            abandoned.outcome = .abandoned
            try await store.save(abandoned)
            try await store.save(try makePaymentMethod(index: 300))

            // The tombstoned subscription and its cascade stay in the snapshot.
            try await store.deleteSubscription(withID: doomed.id, at: Date(timeIntervalSince1970: 9_000))
            return (store, containers)
        }

        private func twicePausedSubscription() throws -> Subscription {
            try makeSubscription(
                index: 5, status: .paused, cycleStartDay: try day(2026, 1, 10),
                pauseEpisodes: [
                    PauseEpisode(
                        id: try fixtureUUID(701),
                        startedOn: try day(2025, 11, 1),
                        scheduledResumeOn: try day(2026, 2, 1),
                        endedOn: try day(2026, 2, 1),
                        outcome: .resumed,
                        createdAt: Date(timeIntervalSince1970: 1_000),
                        updatedAt: Date(timeIntervalSince1970: 2_000)
                    ),
                    PauseEpisode(
                        id: try fixtureUUID(702),
                        startedOn: try day(2026, 6, 1),
                        createdAt: Date(timeIntervalSince1970: 3_000),
                        updatedAt: Date(timeIntervalSince1970: 3_000)
                    )
                ]
            )
        }

        @Test("export, wipe, import: the restored store holds identical domain values")
        func roundTripThroughRealStore() async throws {
            let (source, _) = try await seedRichStore()
            let original = try await source.completeSnapshot()
            let file = try exportData(from: original, exportedAt: Date(timeIntervalSince1970: 10_000))

            // Wipe: restore an empty snapshot. Since Wave 6B-Prep the wipe is
            // expressed as TOMBSTONES, never hard deletes (spec §8) - nothing
            // live remains, but the records are still there as history.
            try await source.restore(
                OttoDataSnapshot(), at: Date(timeIntervalSince1970: 10_500), watermarks: .reconstruct
            )
            #expect(try await source.subscriptions() == [])
            #expect(try await source.completeSnapshot().subscriptions.allSatisfy { $0.deletedAt != nil })

            let resolved = try resolveImport(
                current: try await source.completeSnapshot(),
                incoming: try importedSnapshot(from: file),
                strategy: .replace,
                at: Date(timeIntervalSince1970: 11_000)
            )
            try await source.restore(
                resolved.snapshot, at: Date(timeIntervalSince1970: 11_000), watermarks: .reconstruct
            )

            // Value-identical: the watermark is device state and lives outside
            // the snapshot entirely (spec §5.3, Wave 6B-Prep).
            #expect(try await source.completeSnapshot() == original)
        }

        @Test("the snapshot includes tombstones - a backup without them is not a backup")
        func snapshotIncludesTombstones() async throws {
            let (store, _) = try await seedRichStore()
            let snapshot = try await store.completeSnapshot()
            #expect(snapshot.subscriptions.contains { $0.deletedAt != nil })
            #expect(snapshot.billingEvents.contains { $0.deletedAt != nil })
        }

        @Test("a truncated or corrupted file leaves the database exactly as it was")
        func corruptedFileChangesNothing() async throws {
            let (store, _) = try await seedRichStore()
            let before = try await store.completeSnapshot()
            let file = try exportData(from: before, exportedAt: Date(timeIntervalSince1970: 10_000))

            var corruptions: [Data] = []
            // Truncations at several offsets, including a cut mid-record.
            for fraction in [0.25, 0.5, 0.75, 0.98] {
                corruptions.append(file.prefix(Int(Double(file.count) * fraction)))
            }
            // Overwrites at several offsets with bytes no JSON can contain.
            for offset in [file.count / 5, file.count / 2, file.count - 10] {
                var damaged = file
                damaged.replaceSubrange(offset ..< offset + 4, with: [0xFF, 0xFE, 0x00, 0xFF])
                corruptions.append(damaged)
            }

            for corrupted in corruptions {
                await #expect(throws: (any Error).self) {
                    let incoming = try importedSnapshot(from: corrupted)
                    let resolved = try resolveImport(
                        current: try await store.completeSnapshot(),
                        incoming: incoming,
                        strategy: .replace,
                        at: Date(timeIntervalSince1970: 11_000)
                    )
                    try await store.restore(
                        resolved.snapshot, at: Date(timeIntervalSince1970: 11_000), watermarks: .reconstruct
                    )
                }
                #expect(try await store.completeSnapshot() == before)
            }
        }

        @Test("a snapshot the store cannot hold is refused before anything is touched")
        func unholdableSnapshotRefused() async throws {
            let (store, _) = try await seedRichStore()
            let before = try await store.completeSnapshot()

            // A child naming an absent parent. resolveImport catches this earlier;
            // the store's refuse-first check is the last line, and it must fire
            // BEFORE the wipe - restore deliberately has no failure path between
            // its first mutation and the final save.
            let poisoned = OttoDataSnapshot(billingEvents: [
                try makeBillingEvent(index: 999, subscriptionID: try fixtureUUID(999), expectedDate: try day(2026, 1, 1))
            ])

            await #expect(throws: RepositoryError.self) {
                try await store.restore(poisoned, at: Date(timeIntervalSince1970: 11_000), watermarks: .reconstruct)
            }
            #expect(try await store.completeSnapshot() == before)
        }

        @Test("a merge import leaves the stored watermark untouched (spec §5.3)")
        func importLeavesWatermarkAlone() async throws {
            let (store, _) = try await seedRichStore()
            let subscriptionID = try fixtureUUID(1)

            // The file carries a newer copy of the same subscription (no watermark -
            // the format has no field for one).
            var newer = try makeSubscription(
                index: 1,
                cycleStartDay: try day(2026, 1, 15),
                trial: try makeTrialTerm(index: 501, startDate: try day(2026, 1, 1))
            )
            newer.updatedAt = Date(timeIntervalSince1970: 99_999)
            newer.notes = "edited on the other device"
            let file = try exportData(
                from: OttoDataSnapshot(subscriptions: [newer]),
                exportedAt: Date(timeIntervalSince1970: 10_000)
            )

            let resolved = try resolveImport(
                current: try await store.completeSnapshot(),
                incoming: try importedSnapshot(from: file),
                strategy: .merge,
                at: Date(timeIntervalSince1970: 11_000)
            )
            try await store.restore(resolved.snapshot, at: Date(timeIntervalSince1970: 11_000), watermarks: .keep)

            let stored = try #require(try await store.subscription(withID: subscriptionID))
            #expect(stored.notes == "edited on the other device")
            #expect(
                try await store.materializationWatermark(forSubscription: subscriptionID)
                    == (try day(2026, 9, 1))
            )
        }

        @Test("a restore refuses while sync could still run - the kill switch is structural, not remembered (spec §8, v2.1)")
        func restoreRefusesWhileSyncEngaged() async throws {
            let (store, _) = try makeStore(syncState: SyncState(isEnabled: true, killSwitchEngaged: false))
            try await store.save(try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15)))
            let before = try await store.completeSnapshot()

            await #expect(throws: RepositoryError.restoreRequiresSyncDisengaged) {
                try await store.restore(
                    OttoDataSnapshot(), at: Date(timeIntervalSince1970: 11_000), watermarks: .reconstruct
                )
            }
            // Refused before any mutation - the database is exactly as it was,
            // and the message tells the user what to do.
            #expect(try await store.completeSnapshot() == before)
            #expect(RepositoryError.restoreRequiresSyncDisengaged.errorDescription?.isEmpty == false)
        }

        @Test("the engaged kill switch is what permits a restore during an incident")
        func restoreRunsWithKillSwitchEngaged() async throws {
            let (store, _) = try makeStore(syncState: SyncState(isEnabled: true, killSwitchEngaged: true))
            try await store.save(try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15)))

            try await store.restore(
                OttoDataSnapshot(), at: Date(timeIntervalSince1970: 11_000), watermarks: .reconstruct
            )

            #expect(try await store.subscriptions() == [])
        }

        @Test("watermarks reconstruct from the ledger: latest LIVE row, anchor when none, never today (spec §5.3, v2.1)")
        func replaceImportReconstructsWatermarks() async throws {
            let (_, containers) = try await seedRichStore()

            // A tombstoned row is an invalidation artifact of a sequence that
            // no longer exists - it must not advance the reconstruction.
            let context = ModelContext(containers.main)
            let staleID: UUID? = try fixtureUUID(102)
            let stale = try #require(
                try context.fetch(FetchDescriptor<StoredBillingEvent>()).first { $0.id == staleID }
            )
            stale.deletedAt = Date(timeIntervalSince1970: 9_500)
            try context.save()

            let fresh = OttoStore(containers: containers)
            try await fresh.reconstructMaterializationWatermarks()

            // The pre-import watermark (2026-09-01) vouched for rows the file
            // may not carry; the latest live imported row IS "materialized
            // through".
            #expect(
                try await fresh.materializationWatermark(forSubscription: try fixtureUUID(1))
                    == (try day(2026, 1, 15))
            )
            // No imported rows: the anchor, never today.
            #expect(
                try await fresh.materializationWatermark(forSubscription: try fixtureUUID(2))
                    == (try day(2026, 8, 1))
            )
            #expect(
                try await fresh.materializationWatermark(forSubscription: try fixtureUUID(5))
                    == (try day(2026, 1, 10))
            )
            // A tombstoned subscription materializes nothing and needs none.
            #expect(try await fresh.materializationWatermark(forSubscription: try fixtureUUID(4)) == nil)
        }

        @Test("an unreadable record fails the export loudly - a backup with a silent hole is worse than none")
        func exportRefusesUnmappableRecord() async throws {
            let (store, containers) = try makeStore()
            try await store.save(try makeSubscription(index: 1, cycleStartDay: try day(2026, 8, 15)))
            let context = ModelContext(containers.main)
            let record = try #require(try context.fetch(FetchDescriptor<StoredSubscription>()).first)
            record.status = "hibernating"
            try context.save()

            await #expect(throws: MappingError.self) { try await store.completeSnapshot() }
        }
    }
}
