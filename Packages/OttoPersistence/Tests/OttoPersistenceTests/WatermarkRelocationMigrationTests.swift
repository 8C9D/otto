import Foundation
import OttoDomain
import OttoRepositories
import SQLite3
import SwiftData
import Testing
@testable import OttoPersistence

// Wave 6A (spec §5.3): the V2→V3 relocation of the materialization watermark
// into the device-state store, and the §5.4 v1.9 fold rewrite of stored
// verification states. On-disk stores, real migration, and raw SQLite
// inspection - a claim about the artifact is not the artifact.

extension SerializedPersistenceTests {
    @Suite("Schema V2→V3 migration (spec §5.3, Wave 6A)", .serialized)
    struct WatermarkRelocationMigrationTests {

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
            // A pre-fold finished verification, exactly as the pre-v1.9 flow
            // wrote it: closed with the verified outcome AND the (since
            // removed) verifiedStopped live state.
            let subscriptions = try context.fetch(FetchDescriptor<OttoSchemaV2.StoredSubscription>())
            let parent = try #require(subscriptions.first { $0.id == (try fixtureUUID(1)) })
            try preFoldVerifiedEpisode(on: parent, in: context)
            try context.save()
        }

        private func preFoldVerifiedEpisode(
            on parent: OttoSchemaV2.StoredSubscription, in context: ModelContext
        ) throws {
            let episode = OttoSchemaV2.StoredCancellationEpisode()
            context.insert(episode)
            episode.subscription = parent
            episode.id = try fixtureUUID(601)
            episode.subscriptionID = parent.id
            episode.markedCancelledAt = Date(timeIntervalSince1970: 4_000)
            episode.nextChargeDateIfNotCancelled = 20_260_901
            episode.verificationState = "verifiedStopped"
            episode.unansweredCheckCount = 0
            episode.evidenceNote = "conf #V2-4821, spoke to Dana"
            episode.verifiedAt = Date(timeIntervalSince1970: 6_000)
            episode.endedAt = Date(timeIntervalSince1970: 6_000)
            episode.outcome = "verifiedStopped"
            episode.createdAt = Date(timeIntervalSince1970: 4_000)
            episode.updatedAt = Date(timeIntervalSince1970: 6_000)
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

            // The device-store answers are identical to pre-relocation V2.
            #expect(
                try await store.materializationWatermark(forSubscription: try fixtureUUID(1))
                    == (try day(2026, 9, 1))
            )
            #expect(
                try await store.materializationWatermark(forSubscription: try fixtureUUID(2))
                    == (try day(2026, 11, 20))
            )
            #expect(try await store.materializationWatermark(forSubscription: try fixtureUUID(3)) == nil)

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

            // The §5.4 v1.9 fold rewrite ran on the STORED row, not just at
            // read: the raw state string is remapped, the closure untouched.
            let episode = try #require(
                await store.episodes(forSubscription: try fixtureUUID(1)).first
            )
            #expect(!episode.isOpen)
            #expect(episode.outcome == .verifiedStopped)
            #expect(episode.verificationState == .pending)

            // The single evidence string became one note (spec §5.4 v1.9), by
            // the same rule the wire format uses: derived id, borrowed
            // timestamps.
            let note = try #require(episode.evidenceNotes.first)
            #expect(episode.evidenceNotes.count == 1)
            #expect(note.text == "conf #V2-4821, spoke to Dana")
            #expect(note.createdAt == Date(timeIntervalSince1970: 6_000))
            #expect(note.id == EvidenceNote.legacyNote(
                episodeID: episode.id, text: "", episodeUpdatedAt: note.createdAt
            ).id)

            try assertStoreFileArtifacts(urls)
        }

        /// The artifact itself, not the schema declaration (the Wave 4 lesson):
        /// raw SQLite inspection of both migrated store FILES.
        private func assertStoreFileArtifacts(_ urls: (main: URL, deviceState: URL)) throws {
            // The fold rewrote the stored state string...
            let rawStates = try sqliteStrings(
                at: urls.main,
                query: "SELECT ZVERIFICATIONSTATE FROM ZSTOREDCANCELLATIONEPISODE"
            )
            #expect(rawStates == ["pending"])
            // ...the evidence text moved into its own table and the old column
            // is gone...
            let episodeColumns = try sqliteColumns(of: "ZSTOREDCANCELLATIONEPISODE", at: urls.main)
            #expect(!episodeColumns.contains("ZEVIDENCENOTE"))
            #expect((try sqliteStrings(
                at: urls.main, query: "SELECT ZTEXT FROM ZSTOREDEVIDENCENOTE"
            )) == ["conf #V2-4821, spoke to Dana"])
            // ...and the MAIN store file has no watermark column and no
            // watermark table; the DEVICE store file has the table.
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
            #expect(
                try await store.materializationWatermark(forSubscription: try fixtureUUID(1))
                    == (try day(2026, 9, 1))
            )
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
