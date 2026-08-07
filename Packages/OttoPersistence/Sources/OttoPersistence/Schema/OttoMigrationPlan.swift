import Foundation
import OttoDomain
import SwiftData
import Synchronization

/// The migration plan. V1→V2 is Wave 8.5's model lock (spec §5.3a): the
/// one-to-one cancellation slot and the single pause-field pair become
/// one-to-many episode tables. V2→V3 is Wave 6A's relocation (spec §5.3): the
/// watermark leaves the synced schema for the device-state store. Both are
/// CUSTOM stages, permitted exactly because CloudKit is not on yet - after
/// Wave 6B only lightweight stages are allowed.
enum OttoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OttoSchemaV1.self, OttoSchemaV2.self, OttoSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    /// Where the V2→V3 stage writes the carried watermarks. Set by
    /// `OttoContainerFactory` (or a migration test) BEFORE the main container
    /// opens; a V2 store with watermarks refuses to migrate without it, because
    /// proceeding would drop them silently (spec §5.3: an advanced watermark
    /// lost is re-materialization; lost SILENTLY it is unobserved charge dates).
    static let deviceStateStoreURL = Mutex<URL?>(nil)

    enum MigrationError: Error {
        /// The V2 store carries watermarks but no device-state store URL was
        /// provided to carry them into.
        case deviceStateStoreUnavailable
        /// The carried watermarks did not read back from the device-state
        /// store; the migration aborts BEFORE the schema drops the column.
        case watermarkCarryOverIncomplete(expected: Int, found: Int)
    }

    // What willMigrate reads out of the V1 store for didMigrate to write into
    // V2 - carried across the schema swap in memory because the V1 models
    // (with the legacy fields) and the V2 episode tables never exist in the
    // same context. Static because the stage closures are; Mutex because the
    // plan must be concurrency-clean, though migration itself is one pass.
    private struct LegacyPause: Sendable {
        let subscriptionID: UUID
        let startedOn: Int?
        let scheduledResumeOn: Int?
        let createdAt: Date?
        let updatedAt: Date?
    }

    private struct LegacyCancellation: Sendable {
        let subscriptionID: UUID
        let id: UUID?
        let markedCancelledAt: Date?
        let nextChargeDateIfNotCancelled: Int?
        let expectedChargeAmountCents: Int?
        let verificationState: String?
        let unansweredCheckCount: Int?
        let verifiedAt: Date?
        let evidenceNote: String?
        let createdAt: Date?
        let updatedAt: Date?
        let deletedAt: Date?
    }

    private static let stash = Mutex<(pauses: [LegacyPause], cancellations: [LegacyCancellation])>(([], []))

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: OttoSchemaV1.self,
        toVersion: OttoSchemaV2.self,
        willMigrate: { context in
            var pauses: [LegacyPause] = []
            var cancellations: [LegacyCancellation] = []

            for record in try context.fetch(FetchDescriptor<OttoSchemaV1.StoredSubscription>()) {
                guard let subscriptionID = record.id else { continue }
                // One rule with the export format's v1 import (spec §5.3a):
                // every pause a v1 record describes becomes an OPEN episode -
                // it was never closed, v1 had nothing to close it with.
                if PauseEpisode.legacyEpisodeExists(
                    statusRaw: record.status,
                    hasStart: record.pausedOn != nil,
                    hasScheduledResume: record.pauseEndsOn != nil
                ) {
                    pauses.append(LegacyPause(
                        subscriptionID: subscriptionID,
                        startedOn: record.pausedOn,
                        scheduledResumeOn: record.pauseEndsOn,
                        createdAt: record.createdAt,
                        updatedAt: record.updatedAt
                    ))
                }
            }

            for record in try context.fetch(FetchDescriptor<OttoSchemaV1.StoredCancellationRecord>()) {
                guard let subscriptionID = record.subscriptionID ?? record.subscription?.id else { continue }
                cancellations.append(LegacyCancellation(
                    subscriptionID: subscriptionID,
                    id: record.id,
                    markedCancelledAt: record.markedCancelledAt,
                    nextChargeDateIfNotCancelled: record.nextChargeDateIfNotCancelled,
                    expectedChargeAmountCents: record.expectedChargeAmountCents,
                    verificationState: record.verificationState,
                    unansweredCheckCount: record.unansweredCheckCount,
                    verifiedAt: record.verifiedAt,
                    evidenceNote: record.evidenceNote,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    deletedAt: record.deletedAt
                ))
            }

            stash.withLock { $0 = (pauses, cancellations) }
        },
        didMigrate: { context in
            let (pauses, cancellations) = stash.withLock { staged in
                let taken = staged
                staged = ([], [])
                return taken
            }

            var subscriptionsByID: [UUID: OttoSchemaV2.StoredSubscription] = [:]
            for record in try context.fetch(FetchDescriptor<OttoSchemaV2.StoredSubscription>()) {
                if let id = record.id { subscriptionsByID[id] = record }
            }

            for legacy in pauses {
                guard let parent = subscriptionsByID[legacy.subscriptionID] else { continue }
                let episode = OttoSchemaV2.StoredPauseEpisode()
                context.insert(episode)
                episode.subscription = parent
                // The id is minted here, once, and persists - migration is the
                // one writer that cannot receive a client-generated id from a
                // flow. Timestamps reuse the subscription's: the last touch
                // that could have written the pause is the closest honest
                // instant v1 recorded, and migration reads no clock.
                episode.id = UUID()
                episode.startedOn = legacy.startedOn
                episode.scheduledResumeOn = legacy.scheduledResumeOn
                episode.endedOn = nil
                episode.outcome = nil
                episode.createdAt = legacy.updatedAt ?? legacy.createdAt
                episode.updatedAt = legacy.updatedAt ?? legacy.createdAt
            }

            for legacy in cancellations {
                guard let parent = subscriptionsByID[legacy.subscriptionID] else { continue }
                let episode = OttoSchemaV2.StoredCancellationEpisode()
                context.insert(episode)
                episode.subscription = parent
                episode.id = legacy.id ?? UUID()
                episode.subscriptionID = legacy.subscriptionID
                episode.markedCancelledAt = legacy.markedCancelledAt
                // v1 never recorded what the cancellation interrupted; the
                // un-cancel path derives an honest restore for nil (spec §5.3a).
                episode.statusAtStart = nil
                episode.nextChargeDateIfNotCancelled = legacy.nextChargeDateIfNotCancelled
                episode.expectedChargeAmountCents = legacy.expectedChargeAmountCents
                episode.verificationState = legacy.verificationState
                episode.unansweredCheckCount = legacy.unansweredCheckCount
                episode.verifiedAt = legacy.verifiedAt
                episode.evidenceNote = legacy.evidenceNote
                let closure = CancellationEpisode.legacyClosure(
                    verificationStateRaw: legacy.verificationState,
                    verifiedAt: legacy.verifiedAt,
                    updatedAt: legacy.updatedAt
                )
                episode.endedAt = closure.endedAt
                episode.outcome = closure.outcome?.rawValue
                episode.createdAt = legacy.createdAt
                episode.updatedAt = legacy.updatedAt
                episode.deletedAt = legacy.deletedAt
            }

            try context.save()
        }
    )

    /// The Wave 6A stage (spec §5.3). All the work happens in `willMigrate`,
    /// deliberately: the watermarks are written into the device-state store -
    /// their own file, their own container - and VERIFIED by readback while the
    /// V2 column still exists. A crash or failure at any point leaves the main
    /// store at V2 and the carry-over re-runs (the upsert makes it idempotent);
    /// only after the values durably exist twice does the destructive stage
    /// drop the column. There is no window in which the values exist nowhere.
    static let migrateV2toV3 = MigrationStage.custom(
        fromVersion: OttoSchemaV2.self,
        toVersion: OttoSchemaV3.self,
        willMigrate: { context in
            var carried: [(subscriptionID: UUID, watermark: Int)] = []
            for record in try context.fetch(FetchDescriptor<OttoSchemaV2.StoredSubscription>()) {
                guard let id = record.id, let watermark = record.lastMaterializedThrough else { continue }
                carried.append((id, watermark))
            }
            guard !carried.isEmpty else { return }
            guard let url = deviceStateStoreURL.withLock({ $0 }) else {
                throw MigrationError.deviceStateStoreUnavailable
            }

            let schema = Schema(versionedSchema: OttoDeviceStateSchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            )
            let deviceContext = ModelContext(container)
            let existing = try deviceContext.fetch(FetchDescriptor<StoredMaterializationWatermark>())
            var rowsByID: [UUID: StoredMaterializationWatermark] = [:]
            for row in existing {
                if let id = row.subscriptionID { rowsByID[id] = row }
            }
            for carry in carried {
                if let row = rowsByID[carry.subscriptionID] {
                    row.lastMaterializedThrough = carry.watermark
                } else {
                    let row = StoredMaterializationWatermark()
                    deviceContext.insert(row)
                    row.subscriptionID = carry.subscriptionID
                    row.lastMaterializedThrough = carry.watermark
                }
            }
            try deviceContext.save()

            // The carry-over is asserted, not assumed: every value must read
            // back from the device store before the column is allowed to drop.
            let persisted = Dictionary(
                try deviceContext.fetch(FetchDescriptor<StoredMaterializationWatermark>())
                    .compactMap { row in row.subscriptionID.map { ($0, row.lastMaterializedThrough) } },
                uniquingKeysWith: { first, _ in first }
            )
            let found = carried.count { persisted[$0.subscriptionID] == $0.watermark }
            guard found == carried.count else {
                throw MigrationError.watermarkCarryOverIncomplete(expected: carried.count, found: found)
            }
        },
        didMigrate: nil
    )
}
