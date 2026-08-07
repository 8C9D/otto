import Foundation
import OttoDomain
import OttoRepositories
import SQLite3
import SwiftData
import Testing
@testable import OttoPersistence

// The V1→V2 migration (Wave 8.5, spec §5.3a): a pre-8.5 store's single
// CancellationRecord and pausedOn/pauseEndsOn pair become episode rows, with
// no data loss. Runs against a REAL on-disk store, because migration is the
// one machinery an in-memory container never exercises.

private struct V1PauseFields {
    var pausedOn: Int?
    var pauseEndsOn: Int?
    var watermark: Int?
}
extension SerializedPersistenceTests {
    @Suite("Schema V1→V2 migration (spec §5.3a)", .serialized)
    struct MigrationTests {

        /// Builds a V1 store on disk at `url`, exactly as a pre-8.5 Otto wrote it.
        private func writeV1Store(at url: URL) throws {
            let container = try ModelContainer(
                for: Schema(versionedSchema: OttoSchemaV1.self),
                configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)]
            )
            let context = ModelContext(container)
            func v1Subscription(
                _ index: Int, status: String,
                pausedOn: Int? = nil, pauseEndsOn: Int? = nil,
                watermark: Int? = nil
            ) throws -> OttoSchemaV1.StoredSubscription {
                try self.v1Subscription(
                    index, in: context, status: status,
                    fields: V1PauseFields(
                        pausedOn: pausedOn, pauseEndsOn: pauseEndsOn, watermark: watermark
                    )
                )
            }

            // The report's case: a dated pause, mid-life.
            _ = try v1Subscription(1, status: "paused", pausedOn: 20_260_601, pauseEndsOn: 20_261_201)
            // Paused before Wave 7 recorded either date.
            _ = try v1Subscription(2, status: "paused")
            // Nothing pause-shaped: must get no episode invented.
            _ = try v1Subscription(3, status: "active")

            // A watching cancellation, with an advanced watermark - the shape the
            // un-cancel rewind exists for.
            let pending = try v1Subscription(4, status: "cancellationPending", watermark: 20_261_120)
            let watch = try v1CancellationRecord(
                601, on: pending, in: context, state: "pending", checkDate: 20_260_901
            )
            watch.expectedChargeAmountCents = 1004
            watch.unansweredCheckCount = 1
            watch.evidenceNote = "conf #V1-777"
            watch.markedCancelledAt = Date(timeIntervalSince1970: 4_000)
            watch.createdAt = Date(timeIntervalSince1970: 4_000)
            watch.updatedAt = Date(timeIntervalSince1970: 4_500)

            // A finished cancellation on an archived subscription that ALSO died
            // paused - both legacy shapes on one record.
            let archived = try v1Subscription(
                5, status: "archived", pausedOn: 20_260_301, pauseEndsOn: nil
            )
            let verified = try v1CancellationRecord(
                602, on: archived, in: context, state: "verifiedStopped", checkDate: 20_260_501
            )
            verified.markedCancelledAt = Date(timeIntervalSince1970: 5_000)
            verified.verifiedAt = Date(timeIntervalSince1970: 6_000)
            verified.createdAt = Date(timeIntervalSince1970: 5_000)
            verified.updatedAt = Date(timeIntervalSince1970: 6_500)

            try context.save()
        }

        private func v1Subscription(
            _ index: Int,
            in context: ModelContext,
            status: String,
            fields: V1PauseFields
        ) throws -> OttoSchemaV1.StoredSubscription {
            let record = OttoSchemaV1.StoredSubscription()
            context.insert(record)
            record.id = try fixtureUUID(index)
            record.name = "V1 fixture \(index)"
            record.category = "other"
            record.status = status
            record.amountCents = 1000 + index
            record.currencyCode = "CAD"
            record.cycleUnit = "month"
            record.cycleInterval = 1
            record.cycleStartDay = 20_260_115
            record.reminderLeadDays = 3
            record.pausedOn = fields.pausedOn
            record.pauseEndsOn = fields.pauseEndsOn
            record.lastMaterializedThrough = fields.watermark
            record.createdAt = Date(timeIntervalSince1970: 1_000)
            record.updatedAt = Date(timeIntervalSince1970: 2_000)
            return record
        }

        private func v1CancellationRecord(
            _ index: Int,
            on subscription: OttoSchemaV1.StoredSubscription,
            in context: ModelContext,
            state: String,
            checkDate: Int?
        ) throws -> OttoSchemaV1.StoredCancellationRecord {
            let record = OttoSchemaV1.StoredCancellationRecord()
            context.insert(record)
            record.subscription = subscription
            record.id = try fixtureUUID(index)
            record.subscriptionID = subscription.id
            record.nextChargeDateIfNotCancelled = checkDate
            record.verificationState = state
            record.unansweredCheckCount = 0
            return record
        }

        /// The whole legacy-touching phase holds the shared creation lock (see
        /// TestSupport): building the V1/V2 schemas while another test builds V3
        /// races SwiftData's name-keyed registry. Synchronous so the lock is legal.
        private func migratedStore(
            at url: URL, deviceStateURL: URL, seed: (URL) throws -> Void
        ) throws -> (store: OttoStore, containers: OttoContainers) {
            containerCreationLock.lock()
            defer { containerCreationLock.unlock() }
            try seed(url)
            // Reopen through the factory - what the app does on first launch
            // after the update. The factory hands the migration plan the
            // device-state store's location for the watermark carry-over.
            let containers = try OttoContainerFactory.onDiskContainers(
                mainURL: url, deviceStateURL: deviceStateURL
            )
            return (OttoStore(containers: containers), containers)
        }

        /// A fresh pair of on-disk store URLs, cleaned up by the caller.
        private func storeURLs() -> (main: URL, deviceState: URL) {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("otto-migration-\(UUID().uuidString)")
            return (
                base.appendingPathExtension("main.store"),
                base.appendingPathExtension("device.store")
            )
        }

        @Test("a pre-8.5 store migrates its pause fields and cancellation slot into episodes, losslessly")
        func v1StoreMigrates() async throws {
            let urls = storeURLs()
            defer {
                try? FileManager.default.removeItem(at: urls.main)
                try? FileManager.default.removeItem(at: urls.deviceState)
            }

            let (store, _) = try migratedStore(
                at: urls.main, deviceStateURL: urls.deviceState, seed: writeV1Store
            )

            // The dated pause became one OPEN episode carrying both dates.
            let datedPause = try #require(await store.subscription(withID: try fixtureUUID(1)))
            let datedEpisode = try #require(datedPause.currentPauseEpisode)
            #expect(datedPause.pauseEpisodes.count == 1)
            #expect(datedEpisode.startedOn == (try day(2026, 6, 1)))
            #expect(datedEpisode.scheduledResumeOn == (try day(2026, 12, 1)))
            #expect(datedEpisode.outcome == nil)
            // And the two old questions still answer through the derived accessors.
            #expect(datedPause.pausedOn == (try day(2026, 6, 1)))
            #expect(datedPause.pauseEndsOn == (try day(2026, 12, 1)))

            // The pre-v1.7 pause still gets its episode - §5.3a's invariant
            // requires one - with honest nils where v1 recorded nothing.
            let legacyPause = try #require(await store.subscription(withID: try fixtureUUID(2)))
            let legacyEpisode = try #require(legacyPause.currentPauseEpisode)
            #expect(legacyEpisode.startedOn == nil)
            #expect(legacyEpisode.scheduledResumeOn == nil)

            // Nothing invented for the active subscription.
            let active = try #require(await store.subscription(withID: try fixtureUUID(3)))
            #expect(active.pauseEpisodes.isEmpty)

            // The watching cancellation is an OPEN episode with every field
            // carried across, id included, and no statusAtStart (v1 never knew).
            let watch = try #require(await store.openEpisode(forSubscription: try fixtureUUID(4)))
            #expect(watch.id == (try fixtureUUID(601)))
            #expect(watch.markedCancelledAt == Date(timeIntervalSince1970: 4_000))
            #expect(watch.nextChargeDateIfNotCancelled == (try day(2026, 9, 1)))
            #expect(watch.expectedChargeAmountCents == 1004)
            #expect(watch.verificationState == .pending)
            #expect(watch.unansweredCheckCount == 1)
            #expect(watch.evidenceNote == "conf #V1-777")
            #expect(watch.statusAtStart == nil)
            #expect(watch.updatedAt == Date(timeIntervalSince1970: 4_500))
            // The watermark the un-cancel rewind guards against survived as data.
            let pendingSub = try #require(await store.subscription(withID: try fixtureUUID(4)))
            #expect(pendingSub.lastMaterializedThrough == (try day(2026, 11, 20)))

            // The finished cancellation CLOSED at its verification instant - one
            // rule with the v1 export import - and the died-paused subscription
            // keeps its open pause episode: billing never resumed, so no resume
            // is invented for it.
            let archived = try #require(await store.subscription(withID: try fixtureUUID(5)))
            let finished = try #require(await store.episodes(forSubscription: try fixtureUUID(5)).first)
            #expect(!finished.isOpen)
            #expect(finished.outcome == .verifiedStopped)
            #expect(finished.endedAt == Date(timeIntervalSince1970: 6_000))
            #expect(finished.verifiedAt == Date(timeIntervalSince1970: 6_000))
            #expect(archived.currentPauseEpisode?.startedOn == (try day(2026, 3, 1)))
        }

        // MARK: - Wave 6A: the watermark relocation (spec §5.3)

        /// Builds a V2 store on disk, exactly as a pre-6A Otto wrote it:
        /// three subscriptions, two with watermarks, one without.
        private func writeV2Store(at url: URL) throws {
            let container = try ModelContainer(
                for: Schema(versionedSchema: OttoSchemaV2.self),
                configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)]
            )
            let context = ModelContext(container)
            func v2Subscription(_ index: Int, watermark: Int?) throws {
                let record = OttoSchemaV2.StoredSubscription()
                context.insert(record)
                record.id = try fixtureUUID(index)
                record.name = "V2 fixture \(index)"
                record.category = "other"
                record.status = "active"
                record.amountCents = 1000 + index
                record.currencyCode = "CAD"
                record.cycleUnit = "month"
                record.cycleInterval = 1
                record.cycleStartDay = 20_260_115
                record.reminderLeadDays = 3
                record.lastMaterializedThrough = watermark
                record.createdAt = Date(timeIntervalSince1970: 1_000)
                record.updatedAt = Date(timeIntervalSince1970: 2_000)
            }
            try v2Subscription(1, watermark: 20_260_901)
            try v2Subscription(2, watermark: 20_261_120)
            try v2Subscription(3, watermark: nil)
            try context.save()
        }

        @Test("the V2→V3 relocation carries every watermark across, and the synced store file provably loses the column")
        func v2StoreRelocatesWatermarks() async throws {
            let urls = storeURLs()
            defer {
                try? FileManager.default.removeItem(at: urls.main)
                try? FileManager.default.removeItem(at: urls.deviceState)
            }

            let (store, containers) = try migratedStore(
                at: urls.main, deviceStateURL: urls.deviceState, seed: writeV2Store
            )

            // The domain answers are identical to pre-relocation V2.
            let first = try #require(await store.subscription(withID: try fixtureUUID(1)))
            #expect(first.lastMaterializedThrough == (try day(2026, 9, 1)))
            let second = try #require(await store.subscription(withID: try fixtureUUID(2)))
            #expect(second.lastMaterializedThrough == (try day(2026, 11, 20)))
            let third = try #require(await store.subscription(withID: try fixtureUUID(3)))
            #expect(third.lastMaterializedThrough == nil)

            // The device-state store holds exactly the carried rows.
            let deviceContext = ModelContext(containers.deviceState)
            let rows = try deviceContext.fetch(FetchDescriptor<StoredMaterializationWatermark>())
            let carried = Dictionary(
                rows.compactMap { row in row.subscriptionID.map { ($0, row.lastMaterializedThrough) } },
                uniquingKeysWith: { first, _ in first }
            )
            #expect(carried == [
                try fixtureUUID(1): 20_260_901,
                try fixtureUUID(2): 20_261_120
            ])

            // The artifact itself, not the schema declaration (the Wave 4
            // lesson): the migrated MAIN store file has no watermark column and
            // no watermark table; the DEVICE store file has the table.
            let mainColumns = try sqliteColumns(of: "ZSTOREDSUBSCRIPTION", at: urls.main)
            #expect(mainColumns.contains("ZNAME"))
            #expect(!mainColumns.contains("ZLASTMATERIALIZEDTHROUGH"))
            #expect(!(try sqliteTables(at: urls.main)).contains("ZSTOREDMATERIALIZATIONWATERMARK"))
            #expect((try sqliteTables(at: urls.deviceState)).contains("ZSTOREDMATERIALIZATIONWATERMARK"))
        }

        @Test("a V2 store with watermarks refuses to migrate without a device-state destination, and the refused store retries losslessly")
        func migrationRefusesSilentWatermarkLoss() async throws {
            let urls = storeURLs()
            defer {
                try? FileManager.default.removeItem(at: urls.main)
                try? FileManager.default.removeItem(at: urls.deviceState)
            }

            let (refused, store) = try refusedThenRetriedStore(urls)
            // No destination for the carry-over means dropping the column would
            // lose the watermarks silently, so the migration must fail instead...
            #expect(refused)
            // ...and the refusal happened BEFORE the destructive stage: the same
            // store reopened through the factory migrates completely.
            let first = try #require(await store.subscription(withID: try fixtureUUID(1)))
            #expect(first.lastMaterializedThrough == (try day(2026, 9, 1)))
        }

        /// Synchronous so holding the creation lock is legal (see TestSupport).
        private func refusedThenRetriedStore(
            _ urls: (main: URL, deviceState: URL)
        ) throws -> (refused: Bool, store: OttoStore) {
            containerCreationLock.lock()
            defer { containerCreationLock.unlock() }
            try writeV2Store(at: urls.main)

            OttoMigrationPlan.deviceStateStoreURL.withLock { $0 = nil }
            var refused = false
            do {
                _ = try ModelContainer(
                    for: Schema(versionedSchema: OttoSchemaV3.self),
                    migrationPlan: OttoMigrationPlan.self,
                    configurations: [ModelConfiguration(url: urls.main, cloudKitDatabase: .none)]
                )
            } catch {
                refused = true
            }

            let containers = try OttoContainerFactory.onDiskContainers(
                mainURL: urls.main, deviceStateURL: urls.deviceState
            )
            return (refused, OttoStore(containers: containers))
        }

    }
}

// MARK: - Raw SQLite inspection (file scope: lint forbids deeper nesting)

private enum SQLiteInspectionError: Error {
    case cannotOpen(URL)
    case cannotPrepare(String)
}

private func sqliteTables(at url: URL) throws -> [String] {
    try sqliteStrings(at: url, query: "SELECT name FROM sqlite_master WHERE type = 'table'")
}

private func sqliteColumns(of table: String, at url: URL) throws -> [String] {
    try sqliteStrings(at: url, query: "SELECT name FROM pragma_table_info('\(table)')")
}

private func sqliteStrings(at url: URL, query: String) throws -> [String] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw SQLiteInspectionError.cannotOpen(url)
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
        throw SQLiteInspectionError.cannotPrepare(query)
    }
    defer { sqlite3_finalize(statement) }
    var values: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        if let text = sqlite3_column_text(statement, 0) {
            values.append(String(cString: text))
        }
    }
    return values
}
