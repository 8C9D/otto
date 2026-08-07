import Foundation
import OttoDomain
import SwiftData
import Synchronization

/// The migration plan. V1→V2 is Wave 8.5's model lock (spec §5.3a): the
/// one-to-one cancellation slot and the single pause-field pair become
/// one-to-many episode tables. A CUSTOM stage, permitted exactly because
/// CloudKit is not on yet - after Wave 6 only lightweight stages are allowed,
/// which is why this wave exists at all.
enum OttoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OttoSchemaV1.self, OttoSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
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
}
