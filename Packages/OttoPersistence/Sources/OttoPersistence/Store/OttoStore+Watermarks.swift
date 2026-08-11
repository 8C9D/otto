import Foundation
import OttoDomain
import OttoRepositories
import SwiftData

// The device-state half of the transfer path: rebuilding the §5.3
// materialization watermarks from the ledger, and the restore dirty flag that
// makes an interrupted restore self-heal. Split out of
// OttoStore+DataTransfer.swift, which passed SwiftLint's 400-line file_length;
// these methods write the deviceState context while everything left behind
// writes the main one, so the seam is the store they touch.

extension OttoStore {

    /// The watermark reconstruction (spec §5.3, v2.1): each live
    /// subscription's watermark becomes the latest expected date among
    /// its LIVE ledger rows - what "materialized through" means - or its
    /// anchor when it has none, never today. Live rows only, because a
    /// tombstoned `.upcoming` row is an invalidation artifact of a sequence
    /// that no longer exists; excluding it can only pull the watermark
    /// EARLIER, and a regressed watermark re-observes idempotently while an
    /// advanced one vouches for rows that may not exist. Run by
    /// `restore(_:at:watermarks: .reconstruct)` as its second save, and by
    /// the dirty-flag heal on the first watermark access after an interrupted
    /// one - the v2.2 crash window between the two saves self-heals here
    /// instead of being accepted.
    ///
    /// Since v2.5 the result is capped at the CURRENT stored watermark - the
    /// min of current and reconstructed. This deviates from v2.1's literal
    /// definition in the service of the principle the definition exists for
    /// (watermarks err earlier, never later): in the double fault - flag
    /// written, main save failed, retraction failed - the heal runs over a
    /// ledger that was never replaced, where a bare reconstruction would
    /// advance a deliberately rewound watermark (the backwards-edit rule)
    /// past its stranded gap. The cap can only pull a watermark earlier,
    /// which is always safe, so it applies to every reconstruction rather
    /// than making the heal guess whether the ledger was replaced.
    public func reconstructMaterializationWatermarks() async throws {
        try reconstructWatermarksNow()
    }

    /// The shared body: rebuilds every watermark from the ledger and clears
    /// any §5.3 dirty flag IN THE SAME SAVE, so "reconstructed" and "no longer
    /// dirty" commit together or not at all.
    func reconstructWatermarksNow() throws {
        // EVERY subscription, tombstoned ones included (R0-6). The delete loop
        // below drops every watermark row unconditionally, so a subscription
        // skipped here comes back with none - and a merge import can resurrect a
        // tombstoned subscription by clearing its `deletedAt`. It would then
        // materialize from TODAY, which is the founding v2.1 hazard and the
        // exact failure F6 exists to prevent, reached by a second route.
        //
        // A watermark for a tombstoned subscription costs one device-state row
        // and is never read while it stays tombstoned; the ledger below is still
        // built from LIVE events only, so a tombstoned subscription falls back
        // to its anchor rather than inheriting a dead row's progress.
        let subscriptions = try modelContext.fetch(FetchDescriptor<StoredSubscription>())
        let events = try modelContext.fetch(
            FetchDescriptor<StoredBillingEvent>(predicate: #Predicate { $0.deletedAt == nil })
        )
        var latestBySubscription: [UUID: Int] = [:]
        for event in events {
            guard let subscriptionID = event.subscriptionID, let date = event.expectedDate else { continue }
            latestBySubscription[subscriptionID] = max(latestBySubscription[subscriptionID] ?? date, date)
        }
        let rows = try deviceStateContext.fetch(FetchDescriptor<StoredMaterializationWatermark>())
        var current: [UUID: Int] = [:]
        for row in rows {
            if let id = row.subscriptionID, let stored = row.lastMaterializedThrough {
                current[id] = min(current[id] ?? stored, stored)
            }
            deviceStateContext.delete(row)
        }
        for subscription in subscriptions {
            guard let id = subscription.id,
                  let reconstructed = latestBySubscription[id] ?? subscription.cycleStartDay
            else { continue }
            let row = StoredMaterializationWatermark()
            deviceStateContext.insert(row)
            row.subscriptionID = id
            // The v2.5 cap: never later than the watermark already stored.
            row.lastMaterializedThrough = min(reconstructed, current[id] ?? reconstructed)
        }
        for flag in try deviceStateContext.fetch(FetchDescriptor<StoredRestoreDirtyFlag>()) {
            deviceStateContext.delete(flag)
        }
        if deviceStateContext.hasChanges {
            try deviceStateContext.save()
        }
    }

    // MARK: - The §5.3 restore dirty flag

    /// Durably marks device state dirty before a replace-restore mutates the
    /// main store. Idempotent - one flag row is enough for any number of
    /// interrupted attempts.
    ///
    /// Not private since the split: `restoreThroughMainSave` in
    /// `OttoStore+DataTransfer.swift` calls it, and `private` is file-scoped.
    func markRestoreDirty(at instant: Date) throws {
        var descriptor = FetchDescriptor<StoredRestoreDirtyFlag>()
        descriptor.fetchLimit = 1
        guard try deviceStateContext.fetch(descriptor).isEmpty else { return }
        let flag = StoredRestoreDirtyFlag()
        deviceStateContext.insert(flag)
        flag.markedAt = instant
        do {
            try deviceStateContext.save()
        } catch {
            // The insert never committed; drop it so the context stays clean
            // (a lone pending insert is safe to roll back).
            deviceStateContext.rollback()
            throw error
        }
    }

    /// Retracts the flag without reconstructing - only correct when the main
    /// store is known unchanged (a failed first save).
    func clearRestoreDirtyFlag() throws {
        for flag in try deviceStateContext.fetch(FetchDescriptor<StoredRestoreDirtyFlag>()) {
            deviceStateContext.delete(flag)
        }
        if deviceStateContext.hasChanges {
            try deviceStateContext.save()
        }
    }

    /// The §5.3 heal, run before every watermark read or write: a present
    /// dirty flag means an interrupted replace-restore may have left stored
    /// watermarks ahead of the ledger - the one direction the design refuses -
    /// so they are reconstructed from the ledger (which clears the flag)
    /// before any pass can trust or advance them. Guarding the accessors
    /// rather than app launch makes the ordering structural: there is no code
    /// path to a stale-ahead watermark, whoever calls first.
    func healInterruptedRestoreIfNeeded() throws {
        var descriptor = FetchDescriptor<StoredRestoreDirtyFlag>()
        descriptor.fetchLimit = 1
        guard try !deviceStateContext.fetch(descriptor).isEmpty else { return }
        try reconstructWatermarksNow()
    }
}
