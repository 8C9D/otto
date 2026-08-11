import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import os

/// One error log per skipped record; see MappingError for the skip policy.
let mappingLogger = Logger(subsystem: "com.arthurzhang.otto", category: "persistence")

/// The SwiftData implementation of every repository protocol - one actor over one
/// model context, so a write and its cascade always happen on the same serialized
/// context. Callers hold it as the protocols; the concrete type exists only to be
/// constructed and injected.
///
/// Since Wave 6A the actor also owns the device-state store (spec §5.3): a
/// second context over `OttoContainers.deviceState`, serialized by this same
/// actor, holding the materialization watermarks. The two stores are separate
/// files, so a single atomic save across them does not exist; every method
/// that writes both orders its two saves so a crash between them lands on the
/// safe side (a REGRESSED watermark re-observes idempotently; an ADVANCED one
/// vouches for rows that may not exist - spec §5.3).
///
/// Reads never surface a `MappingError`: an unmappable record (a partially synced
/// arrival, once CloudKit is on) is skipped with an error log, because in domain
/// terms it is not there yet. Reads exclude tombstones unless the method name says
/// otherwise. No method reads a clock - every instant is a parameter or a field of
/// the value being saved.
@ModelActor
public actor OttoStore {

    /// Defaulted so the macro's `init(modelContainer:)` still compiles; that
    /// init is never used - construction goes through `init(containers:)`.
    private var deviceStateContainer: ModelContainer! = nil
    private var _deviceStateContext: ModelContext?
    /// Read fresh on every guard rather than captured once: the kill switch
    /// can be engaged mid-session, and `restore()` (spec §8, v2.1) must see
    /// the switch as it is NOW. Defaulted for the macro's unused init.
    var syncState: @Sendable () -> SyncState = { .load() }
    /// The sync mode the main container was OPENED with - the flags alone
    /// cannot prove the live store is not mirroring, because the kill switch
    /// acts at the next launch. Defaulted for the macro's unused init.
    var mainSyncMode: OttoContainerFactory.MainStoreSyncMode = .off

    public init(
        containers: OttoContainers,
        syncState: @escaping @Sendable () -> SyncState = { .load() }
    ) {
        let context = ModelContext(containers.main)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = containers.main
        self.deviceStateContainer = containers.deviceState
        self.syncState = syncState
        self.mainSyncMode = containers.mainSyncMode
    }

    /// Lazily created on the actor so its use is serialized with `modelContext`.
    var deviceStateContext: ModelContext {
        if let existing = _deviceStateContext { return existing }
        guard let container = deviceStateContainer else {
            fatalError("OttoStore was built without a device-state container; use init(containers:)")
        }
        let created = ModelContext(container)
        _deviceStateContext = created
        return created
    }

    // MARK: - The materialization watermark (spec §5.3, device state)

    func deviceWatermark(for subscriptionID: UUID) throws -> CalendarDay? {
        try healInterruptedRestoreIfNeeded()
        let rows = try deviceStateContext.fetch(
            FetchDescriptor<StoredMaterializationWatermark>(
                predicate: #Predicate { $0.subscriptionID == subscriptionID }
            )
        )
        return Self.watermarkDay(in: rows, for: subscriptionID)
    }

    /// One subscription's stored watermark, distinguishing "no watermark" from
    /// "a watermark that is not a date" - and logging the second (R0-5).
    ///
    /// Both used to collapse into the same nil, and a nil watermark sends
    /// `materializeEvents` back to TODAY, which is F6's exact signature: the
    /// rows between the last real charge and today are silently never created.
    /// Neither path said anything, so that failure had a third unlogged route
    /// into it. This is not hypothetical - `OttoMigrationPlan` carries
    /// `lastMaterializedThrough` out of the V2 column into V3 without
    /// validating it, so a corrupt V2 value arrives intact.
    ///
    /// The row is chosen by MINIMUM, not by `rows.first`. There is no unique
    /// constraint and the fetch is unsorted, so `first` was nondeterministic
    /// across duplicate rows; the minimum is deterministic and it is the
    /// direction §5.3 already requires - a watermark errs earlier, never later,
    /// because a regressed one re-observes idempotently while an advanced one
    /// vouches for rows that may not exist.
    ///
    /// A corrupt value still reads as nil, because there is nothing safe to
    /// invent from it. What changes is that it is no longer silent.
    static func watermarkDay(
        in rows: [StoredMaterializationWatermark],
        for subscriptionID: UUID
    ) -> CalendarDay? {
        guard let stored = rows.compactMap(\.lastMaterializedThrough).min() else { return nil }
        guard let day = CalendarDay(yyyymmdd: stored) else {
            // The packed value, not a redaction: a calendar day is exactly what
            // OttoLog permits in the clear, and which impossible date it is
            // ("Feb 30" versus zero versus garbage) is the whole diagnosis.
            mappingLogger.error("""
                watermark unreadable - materializing from today for this \
                subscription: id=\(subscriptionID.uuidString, privacy: .public) \
                stored=\(stored, privacy: .public)
                """)
            return nil
        }
        return day
    }

    /// Upserts (or clears, on nil) one watermark and SAVES the device store.
    /// Callers choose where this falls relative to the main store's save; see
    /// the actor comment for the ordering rule.
    func setDeviceWatermark(_ day: CalendarDay?, for subscriptionID: UUID) throws {
        try healInterruptedRestoreIfNeeded()
        let rows = try deviceStateContext.fetch(
            FetchDescriptor<StoredMaterializationWatermark>(
                predicate: #Predicate { $0.subscriptionID == subscriptionID }
            )
        )
        if let day {
            if let row = rows.first {
                row.lastMaterializedThrough = day.yyyymmdd
            } else {
                let row = StoredMaterializationWatermark()
                deviceStateContext.insert(row)
                row.subscriptionID = subscriptionID
                row.lastMaterializedThrough = day.yyyymmdd
            }
            for extra in rows.dropFirst() { deviceStateContext.delete(extra) }
        } else {
            for row in rows { deviceStateContext.delete(row) }
        }
        if deviceStateContext.hasChanges {
            try deviceStateContext.save()
        }
    }

    // MARK: - Shared helpers

    func liveOnly<Record>(_ records: [Record], deletedAt: (Record) -> Date?) -> [Record] {
        records.filter { deletedAt($0) == nil }
    }

    /// Maps records to domain values, skipping (with a log) any that fail.
    func mapSkippingFailures<Record, Value>(
        _ records: [Record],
        _ transform: (Record) throws -> Value
    ) -> [Value] {
        records.compactMap { record in
            do {
                return try transform(record)
            } catch {
                mappingLogger.error(
                    "Skipping unmappable record: \(mappingLogSummary(error), privacy: .public)"
                )
                return nil
            }
        }
    }

    func storedSubscription(id: UUID, includingDeleted: Bool) throws -> StoredSubscription? {
        var descriptor = FetchDescriptor<StoredSubscription>(
            predicate: includingDeleted
                ? #Predicate { $0.id == id }
                : #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
