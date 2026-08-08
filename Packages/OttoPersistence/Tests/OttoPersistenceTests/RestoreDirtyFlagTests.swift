import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// The §5.3 restore dirty flag (v2.2): a crash between a replace-restore's two
// saves used to leave the PRE-IMPORT watermarks - which can sit ahead of the
// imported ledger, vouching for rows the restored database does not have, the
// one direction the whole design refuses. These tests interrupt the window for
// real (through the production path, stopped between the saves) and prove it
// self-heals through the reconstruction that already exists.
extension SerializedPersistenceTests {
    @Suite("The restore dirty flag (spec §5.3, v2.2)")
    struct RestoreDirtyFlagTests {

        /// The v2.2 crash window, interrupted for real: through the first of
        /// restore's two saves via the production path, stopped before the
        /// reconstruction save - exactly what a crash there leaves on disk.
        /// The subscription is `fixtureUUID(1)`, watermark Sep 1, restored
        /// ledger ending Jan 15.
        private func interruptedRestore() async throws -> (store: OttoStore, containers: OttoContainers) {
            let (store, containers) = try makeStore()
            let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await store.save(subscription)
            try await store.initializeMaterializationWatermark(
                forSubscription: subscription.id, at: try day(2026, 9, 1)
            )
            // The file's ledger ends at Jan 15 - far behind the pre-import
            // watermark, which now vouches for rows this database won't have.
            let snapshot = OttoDataSnapshot(
                subscriptions: [subscription],
                billingEvents: [
                    try makeBillingEvent(
                        index: 101, subscriptionID: subscription.id, expectedDate: try day(2026, 1, 15)
                    )
                ]
            )
            try await store.restoreThroughMainSave(
                snapshot, at: Date(timeIntervalSince1970: 11_000), markingDirty: true
            )
            return (store, containers)
        }

        private func storedFlags(in containers: OttoContainers) throws -> [StoredRestoreDirtyFlag] {
            try ModelContext(containers.deviceState).fetch(FetchDescriptor<StoredRestoreDirtyFlag>())
        }

        @Test("interrupted between the two saves, a relaunch reconstructs - stale-ahead never survives")
        func interruptedRestoreHealsOnRelaunch() async throws {
            let (_, containers) = try await interruptedRestore()

            // Relaunch: a fresh store over the same files. The first watermark
            // access must answer from the restored ledger (Jan 15), not report
            // the pre-import Sep 1 - the one direction the design refuses.
            let relaunched = OttoStore(containers: containers)
            #expect(
                try await relaunched.materializationWatermark(forSubscription: try fixtureUUID(1))
                    == (try day(2026, 1, 15))
            )
            // The heal cleared the flag; the reconstruction is not re-run.
            #expect(try storedFlags(in: containers).isEmpty)
        }

        @Test("after the interrupt, the next pass materializes the window the stale watermark would have skipped")
        func interruptedRestoreDoesNotSkipTheWindow() async throws {
            let (_, containers) = try await interruptedRestore()

            // The founding-hazard consequence, not just the mechanism: a pass
            // on the relaunched store must reach back to the restored ledger's
            // edge and create Feb 15 - under the stale Sep 1 watermark that
            // charge would silently never get a row.
            let relaunched = OttoStore(containers: containers)
            let subscription = try #require(try await relaunched.subscription(withID: try fixtureUUID(1)))
            let created = try await relaunched.materializeEvents(
                for: subscription, from: try day(2026, 3, 1), horizonDays: 90,
                maxReminderLeadDays: 7, at: Date(timeIntervalSince1970: 12_000)
            )
            #expect(created.contains { $0.expectedDate == (try? day(2026, 2, 15)) })
        }

        @Test("the dirty flag is durable before the main save and gone once reconstruction commits")
        func dirtyFlagBracketsTheTwoSaves() async throws {
            let (store, containers) = try await interruptedRestore()

            // Present in the window - written durably before the main store
            // could change, so a crash anywhere inside it is flagged.
            #expect(try storedFlags(in: containers).count == 1)

            // The second save clears it atomically with the reconstruction.
            try await store.reconstructMaterializationWatermarks()
            #expect(try storedFlags(in: containers).isEmpty)
        }

        @Test("the double fault - flag written, main save and retraction failed - keeps a rewound watermark behind its gap")
        func doubleFaultKeepsRewoundWatermarkBehindItsGap() async throws {
            let (store, containers) = try makeStore()
            let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await store.save(subscription)
            // A ledger through Dec 15 whose interior the backwards-edit rule
            // (§5.3, v1.7) decided must be re-observed: the rewind to Oct 1
            // strands the gap (Oct 1 .. Dec 15] behind rows that still exist,
            // so a reconstruction from the ledger alone cannot see it.
            try await store.save(try makeBillingEvent(
                index: 101, subscriptionID: subscription.id, expectedDate: try day(2026, 12, 15)
            ))
            try await store.initializeMaterializationWatermark(
                forSubscription: subscription.id, at: try day(2026, 12, 15)
            )
            try await store.rewindMaterializationWatermark(
                forSubscription: subscription.id, to: try day(2026, 10, 1)
            )

            // The double fault's on-disk signature, driven through the
            // production path: the flag written durably, the ledger left
            // unreplaced (a failed main save persists nothing - which a
            // content-identical restore's first save reproduces exactly), and
            // the failed retraction leaving the flag standing.
            let snapshot = try await store.completeSnapshot()
            try await store.restoreThroughMainSave(
                snapshot, at: Date(timeIntervalSince1970: 11_000), markingDirty: true
            )
            #expect(try storedFlags(in: containers).count == 1)

            // Relaunch: the heal reconstructs over the unreplaced ledger. A
            // bare reconstruction would answer Dec 15 - advancing past the
            // stranded gap, the one direction the design refuses. The v2.5
            // min keeps the rewind.
            let relaunched = OttoStore(containers: containers)
            #expect(
                try await relaunched.materializationWatermark(forSubscription: try fixtureUUID(1))
                    == (try day(2026, 10, 1))
            )
            #expect(try storedFlags(in: containers).isEmpty)
        }

        @Test("a completed replace and a merge both end with no dirty flag - a merge never writes one")
        func completedRestoresLeaveNoFlag() async throws {
            let (store, containers) = try makeStore()
            let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await store.save(subscription)
            let snapshot = try await store.completeSnapshot()

            try await store.restore(snapshot, at: Date(timeIntervalSince1970: 11_000), watermarks: .reconstruct)
            #expect(try storedFlags(in: containers).isEmpty)

            try await store.restore(snapshot, at: Date(timeIntervalSince1970: 12_000), watermarks: .keep)
            #expect(try storedFlags(in: containers).isEmpty)
        }

        @Test("a refused restore writes no flag - the flag write is the last act of the refuse phase")
        func refusedRestoreWritesNoFlag() async throws {
            let (store, containers) = try makeStore(
                syncState: SyncState(isEnabled: true, killSwitchEngaged: false)
            )
            await #expect(throws: RepositoryError.restoreRequiresSyncDisengaged) {
                try await store.restore(
                    OttoDataSnapshot(), at: Date(timeIntervalSince1970: 11_000), watermarks: .reconstruct
                )
            }
            #expect(try storedFlags(in: containers).isEmpty)
        }
    }
}
