import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// The restore-into-an-empty-store cases, split out of DataTransferTests.swift
// which passed SwiftLint's 400-line file_length. Same restore path, and they
// already lived in their own extension because DataTransferTests is at its
// type_body_length ceiling.

extension SerializedPersistenceTests {
    /// Kept out of `DataTransferTests` only because that struct is at its
    /// `type_body_length` ceiling; this is the same restore path.
    @Suite("Restoring into an empty store (spec §5.3, the recovery case)")
    struct RestoreIntoEmptyStoreTests {

    /// The recovery case, end to end through `restore` itself: a fresh
    /// install with an EMPTY store takes a file and must come out with
    /// watermarks that describe the imported ledger.
    ///
    /// `DataTransferTests`'s `replaceImportReconstructsWatermarks` proves what
    /// `reconstructMaterializationWatermarks()`
    /// computes, but calls it directly on an already-seeded store - it never
    /// goes through `restore(_:at:watermarks:)` and never sees an empty
    /// database, which is the exact composition a restore-after-reinstall
    /// exercises. Both policies are asserted here, because "reconstruct
    /// produced a watermark" means nothing unless "keep" demonstrably does
    /// not on the same input.
    @Test("restoring into an EMPTY store reconstructs from the imported ledger; keep leaves it nil")
    func restoreIntoEmptyStoreReconstructsWatermarks() async throws {
        let imported = try await { () async throws -> OttoDataSnapshot in
            let (source, _) = try makeStore()
            let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await source.save(subscription)
            try await source.save(BillingEvent(
                id: try fixtureUUID(101),
                subscriptionID: subscription.id,
                expectedDate: try day(2026, 6, 15),
                expectedAmountCents: 1099,
                state: .confirmedCharged,
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 2_000)
            ))
            return try await source.completeSnapshot()
        }()

        // .keep on an empty store: there is no progress to keep, so the
        // watermark stays nil - and a nil watermark makes materialization
        // start from today, losing every row back to the file's last charge.
        let (kept, _) = try makeStore()
        #expect(try await kept.subscriptions().isEmpty)
        try await kept.restore(imported, at: Date(timeIntervalSince1970: 11_000), watermarks: .keep)
        #expect(try await kept.materializationWatermark(forSubscription: try fixtureUUID(1)) == nil)

        // .reconstruct on the same empty store and the same file: the
        // watermark is the latest live imported row, never nil, never today.
        let (rebuilt, _) = try makeStore()
        #expect(try await rebuilt.subscriptions().isEmpty)
        try await rebuilt.restore(
            imported, at: Date(timeIntervalSince1970: 11_000), watermarks: .reconstruct
        )
        #expect(
            try await rebuilt.materializationWatermark(forSubscription: try fixtureUUID(1))
                == (try day(2026, 6, 15))
        )
        // The data arrived either way - the difference is only the watermark.
        #expect(try await rebuilt.subscriptions().count == 1)
        #expect(try await rebuilt.events(forSubscription: try fixtureUUID(1)).count == 1)
    }

    /// R3-1's store half, so the policy assertion in `ExportServiceTests` is not
    /// the only evidence. An ALL-TOMBSTONED database is not `isEmpty`, so the UI
    /// asks merge-or-replace and the user can answer Merge - and `.keep` then
    /// leaves the restored subscription with no watermark, which is F6 exactly,
    /// one prompt later. Both policies are asserted on the same input, because
    /// "reconstruct produced a watermark" means nothing unless "keep"
    /// demonstrably does not.
    @Test("⛔ restoring into an ALL-TOMBSTONED store: reconstruct gives a watermark, keep leaves it nil")
    func restoreIntoAllTombstonedStoreReconstructsWatermarks() async throws {
        let imported = try await { () async throws -> OttoDataSnapshot in
            let (source, _) = try makeStore()
            let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await source.save(subscription)
            try await source.save(try makeBillingEvent(
                index: 101, subscriptionID: subscription.id, expectedDate: try day(2026, 6, 15)
            ))
            return try await source.completeSnapshot()
        }()

        /// A store holding records that are all tombstoned - deleted by hand,
        /// then left. Not `isEmpty`, and no ledger progress worth keeping.
        func allTombstonedStore() async throws -> OttoStore {
            let (store, _) = try makeStore()
            let doomed = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await store.save(doomed)
            try await store.deleteSubscription(withID: doomed.id, at: Date(timeIntervalSince1970: 9_000))
            let snapshot = try await store.completeSnapshot()
            #expect(!snapshot.isEmpty)
            #expect(snapshot.hasNoLiveRecords)
            return store
        }

        // .keep on an all-tombstoned store: the watermark the resurrection
        // needs is never written.
        let kept = try await allTombstonedStore()
        try await kept.restore(imported, at: Date(timeIntervalSince1970: 11_000), watermarks: .keep)
        #expect(try await kept.materializationWatermark(forSubscription: try fixtureUUID(1)) == nil)

        // .reconstruct on the same input: the latest live imported row.
        let rebuilt = try await allTombstonedStore()
        try await rebuilt.restore(
            imported, at: Date(timeIntervalSince1970: 11_000), watermarks: .reconstruct
        )
        #expect(
            try await rebuilt.materializationWatermark(forSubscription: try fixtureUUID(1))
                == (try day(2026, 6, 15))
        )
        #expect(try await rebuilt.subscriptions().count == 1)
    }

    /// R0-6. `reconstructWatermarksNow` deletes every watermark row and then
    /// rebuilt one only for subscriptions that were live AT THAT MOMENT, so a
    /// subscription that was tombstoned when the reconstruction ran and
    /// resurrected afterwards - which a merge import does by clearing
    /// `deletedAt` (`ImportResolution`) - came back with a nil watermark and
    /// materialized from TODAY. That is the founding v2.1 hazard and F6's exact
    /// failure signature, reached by a second route.
    @Test("⛔ a subscription tombstoned at reconstruct time and resurrected later still has a watermark")
    func resurrectedSubscriptionKeepsItsWatermark() async throws {
        let (store, containers) = try makeStore()
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 3, 1))
        try await store.save(subscription)
        // The event is dated LATER than the anchor on purpose. With both on the
        // same day - as the sibling fixture has them - the expected watermark is
        // simultaneously the anchor and the dead ledger row, so the assertion
        // cannot tell which one produced it and the "live events only" rule is
        // unguarded for exactly the case this test is about.
        try await store.save(try makeBillingEvent(
            index: 101, subscriptionID: subscription.id, expectedDate: try day(2026, 5, 1)
        ))
        try await store.deleteSubscription(withID: subscription.id, at: Date(timeIntervalSince1970: 9_000))
        #expect(try await store.subscriptions().isEmpty)

        // The reconstruction runs while it is tombstoned - a replace-restore or
        // the §5.3 dirty-flag heal, neither of which knows what a later merge
        // will bring back.
        try await store.reconstructMaterializationWatermarks()

        // Resurrection, exactly as a merge import performs it.
        let context = ModelContext(containers.main)
        let record = try #require(
            try context.fetch(FetchDescriptor<StoredSubscription>())
                .first { $0.id == subscription.id }
        )
        record.deletedAt = nil
        try context.save()

        let revived = OttoStore(containers: containers)
        #expect(try await revived.subscriptions().count == 1)
        // The ANCHOR (2026-03-01), never nil and never the tombstoned ledger
        // row (2026-05-01): a nil makes materializeEvents start from today and
        // silently skip every charge back to the last real one, and inheriting
        // a dead row's progress would vouch for charges that no longer exist.
        #expect(
            try await revived.materializationWatermark(forSubscription: subscription.id)
                == (try day(2026, 3, 1))
        )
    }
    }
}
