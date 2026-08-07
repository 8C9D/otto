import Foundation
import Testing
import OttoDomain
import OttoRepositories
@testable import OttoServices

/// An in-memory stand-in for the store's data-transfer seam.
private actor MockTransfer: DataTransferRepository {
    private(set) var snapshot: OttoDataSnapshot
    private(set) var restoredSnapshots: [OttoDataSnapshot] = []

    init(snapshot: OttoDataSnapshot = OttoDataSnapshot()) {
        self.snapshot = snapshot
    }

    func completeSnapshot() async throws -> OttoDataSnapshot { snapshot }

    func restore(_ snapshot: OttoDataSnapshot) async throws {
        restoredSnapshots.append(snapshot)
        self.snapshot = snapshot
    }
}

@MainActor
@Suite("ExportService: files in, files out, decisions in the domain")
struct ExportServiceTests {

    private func seededSnapshot() throws -> OttoDataSnapshot {
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        return OttoDataSnapshot(
            subscriptions: [subscription],
            billingEvents: [
                BillingEvent(
                    id: try fixtureUUID(101),
                    subscriptionID: subscription.id,
                    expectedDate: try day(2026, 1, 15),
                    expectedAmountCents: 1099,
                    state: .confirmedCharged,
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    updatedAt: Date(timeIntervalSince1970: 2_000)
                )
            ]
        )
    }

    @Test("the JSON export writes a dated, decodable file ready for the share sheet")
    func jsonExportFile() async throws {
        let service = ExportService(transfer: MockTransfer(snapshot: try seededSnapshot()))

        let url = try await service.exportJSONFile(
            exportedAt: Date(timeIntervalSince1970: 10_000), today: try day(2026, 8, 6)
        )

        #expect(url.lastPathComponent == "Otto-Export-2026-08-06.json")
        let restored = try importedSnapshot(from: try Data(contentsOf: url))
        #expect(restored.subscriptions.map(\.id) == [try fixtureUUID(1)])
        #expect(restored.billingEvents.count == 1)
    }

    @Test("the CSV export writes the charge history file")
    func csvExportFile() async throws {
        let service = ExportService(transfer: MockTransfer(snapshot: try seededSnapshot()))

        let url = try await service.exportChargesCSVFile(today: try day(2026, 8, 6))

        #expect(url.lastPathComponent == "Otto-Charges-2026-08-06.csv")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasPrefix("date,subscription,state,expected amount,actual amount,currency"))
        #expect(text.contains("2026-01-15"))
        #expect(text.contains("10.99"))
    }

    @Test("the preview reports what the file brings and whether the database is empty")
    func preview() async throws {
        let service = ExportService(transfer: MockTransfer())
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("otto-preview-test.json")
        try exportData(from: try seededSnapshot(), exportedAt: Date(timeIntervalSince1970: 0))
            .write(to: file)

        let preview = try await service.importPreview(from: file)

        #expect(preview.databaseIsEmpty)
        #expect(preview.subscriptionCount == 1)
        #expect(preview.billingEventCount == 1)
    }

    @Test("a merge import restores the resolved snapshot and reports the counts")
    func mergeImport() async throws {
        let transfer = MockTransfer(snapshot: try seededSnapshot())
        let service = ExportService(transfer: transfer)
        var incoming = OttoDataSnapshot(subscriptions: [
            try makeSubscription(index: 2, cycleStartDay: try day(2026, 2, 1))
        ])
        incoming.subscriptions[0].updatedAt = Date(timeIntervalSince1970: 50_000)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("otto-merge-test.json")
        try exportData(from: incoming, exportedAt: Date(timeIntervalSince1970: 0)).write(to: file)

        let summary = try await service.performImport(from: file, strategy: .merge)

        #expect(summary.subscriptions == ImportCounts(added: 1))
        let stored = await transfer.snapshot
        #expect(stored.subscriptions.count == 2)
        #expect(stored.billingEvents.count == 1)
    }

    @Test("a corrupt file fails the import and nothing is restored")
    func corruptImportTouchesNothing() async throws {
        let transfer = MockTransfer(snapshot: try seededSnapshot())
        let service = ExportService(transfer: transfer)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("otto-corrupt-test.json")
        try Data("not an export".utf8).write(to: file)

        await #expect(throws: ExportFormatError.self) {
            try await service.performImport(from: file, strategy: .replace)
        }
        #expect(await transfer.restoredSnapshots.isEmpty)
    }
}
