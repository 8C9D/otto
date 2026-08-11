import Foundation
import Testing
import OttoDomain
import OttoRepositories
@testable import OttoServices

/// An in-memory stand-in for the store's data-transfer seam.
private actor MockTransfer: DataTransferRepository {
    private(set) var snapshot: OttoDataSnapshot
    private(set) var restoredSnapshots: [OttoDataSnapshot] = []
    private(set) var restoredWatermarkPolicies: [RestoreWatermarkPolicy] = []

    init(snapshot: OttoDataSnapshot = OttoDataSnapshot()) {
        self.snapshot = snapshot
    }

    func completeSnapshot() async throws -> OttoDataSnapshot { snapshot }

    func restore(
        _ snapshot: OttoDataSnapshot, at instant: Date, watermarks: RestoreWatermarkPolicy
    ) async throws {
        restoredSnapshots.append(snapshot)
        restoredWatermarkPolicies.append(watermarks)
        self.snapshot = snapshot
    }

    func reconstructMaterializationWatermarks() async throws {}
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

        let summary = try await service.performImport(from: file, strategy: .merge, now: Date(timeIntervalSince1970: 11_000))

        #expect(summary.subscriptions == ImportCounts(added: 1))
        let stored = await transfer.snapshot
        #expect(stored.subscriptions.count == 2)
        #expect(stored.billingEvents.count == 1)
        // A merge leaves this device's ledger progress untouched (spec §5.3).
        #expect(await transfer.restoredWatermarkPolicies == [.keep])
    }

    /// The recovery case: restoring into a fresh install. The UI never asks
    /// merge-or-replace when there is nothing to merge with, so the restore
    /// that matters most arrives here as a `.merge` - and `.keep` kept nothing,
    /// leaving every watermark nil and making the ledger materialize from today
    /// instead of from the file's last charge.
    ///
    /// The assertion is the POLICY, because the policy is the decision this
    /// seam owns; what `.reconstruct` then does to the stored watermarks is
    /// proved against the real store in OttoPersistence's DataTransferTests
    /// ("watermarks reconstruct from the ledger: latest LIVE row, anchor when
    /// none, never today").
    @Test("a merge into an EMPTY database reconstructs anyway - the empty database is the recovery case")
    func mergeIntoEmptyDatabaseReconstructsWatermarks() async throws {
        // No seed: this is a fresh install, exactly as SettingsView finds it.
        let transfer = MockTransfer()
        let service = ExportService(transfer: transfer)
        let incoming = try seededSnapshot()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("otto-empty-merge-test.json")
        try exportData(from: incoming, exportedAt: Date(timeIntervalSince1970: 0)).write(to: file)

        _ = try await service.performImport(
            from: file, strategy: .merge, now: Date(timeIntervalSince1970: 11_000)
        )

        #expect(await transfer.restoredWatermarkPolicies == [.reconstruct])
        // And the data itself still arrived, so this is not reconstruction
        // bought by dropping the import.
        let stored = await transfer.snapshot
        #expect(stored.subscriptions.count == 1)
        #expect(stored.billingEvents.count == 1)
    }

    /// R3-1. `isEmpty` was the wrong predicate for the stated principle: a
    /// database whose every record is tombstoned has no ledger progress worth
    /// keeping either, but it is not `isEmpty` - `completeSnapshot()` carries
    /// tombstones by design - so the prompt appeared and answering Merge
    /// reproduced F6 exactly. Narrower than F6 (it takes a deliberate answer at
    /// an explicit prompt rather than a silent default), which is why round 1
    /// rated it P2, but the prompt asks about *records* and the user is not
    /// consenting to this.
    @Test("⛔ a merge into an ALL-TOMBSTONED database reconstructs too - tombstones are not progress")
    func mergeIntoAllTombstonedDatabaseReconstructsWatermarks() async throws {
        // Every record present and every record tombstoned: not `isEmpty`, and
        // nothing live to keep.
        var buried = try seededSnapshot()
        let buriedAt = Date(timeIntervalSince1970: 9_000)
        for index in buried.subscriptions.indices { buried.subscriptions[index].deletedAt = buriedAt }
        for index in buried.billingEvents.indices { buried.billingEvents[index].deletedAt = buriedAt }
        // A LIVE payment method, deliberately. `deleteSubscription` cascades to
        // trials, episodes, billing events and price changes but not to payment
        // methods, so this is the state a user actually reaches by deleting
        // every subscription - and a predicate that demanded every record type
        // be tombstoned would answer "something is live" and miss it.
        buried.paymentMethods = [PaymentMethod(
            id: try fixtureUUID(300),
            label: "Test card",
            last4: "4821",
            issuer: "Test Issuer",
            expiryMonth: 12,
            expiryYear: 2030,
            isDefault: true,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )]
        #expect(!buried.isEmpty)
        #expect(buried.hasNoLiveSubscriptions)

        let transfer = MockTransfer(snapshot: buried)
        let service = ExportService(transfer: transfer)
        var incoming = try seededSnapshot()
        incoming.subscriptions[0].updatedAt = Date(timeIntervalSince1970: 50_000)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("otto-tombstoned-merge-test.json")
        try exportData(from: incoming, exportedAt: Date(timeIntervalSince1970: 0)).write(to: file)

        _ = try await service.performImport(
            from: file, strategy: .merge, now: Date(timeIntervalSince1970: 11_000)
        )

        #expect(await transfer.restoredWatermarkPolicies == [.reconstruct])
    }

    @Test("a replace import names the reconstruct policy, so the store runs the §5.3 sequence")
    func replaceImportReconstructsWatermarks() async throws {
        let transfer = MockTransfer(snapshot: try seededSnapshot())
        let service = ExportService(transfer: transfer)
        let incoming = OttoDataSnapshot(subscriptions: [
            try makeSubscription(index: 2, cycleStartDay: try day(2026, 2, 1))
        ])
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("otto-replace-test.json")
        try exportData(from: incoming, exportedAt: Date(timeIntervalSince1970: 0)).write(to: file)

        _ = try await service.performImport(from: file, strategy: .replace, now: Date(timeIntervalSince1970: 11_000))

        #expect(await transfer.restoredWatermarkPolicies == [.reconstruct])
    }

    @Test("a corrupt file fails the import and nothing is restored")
    func corruptImportTouchesNothing() async throws {
        let transfer = MockTransfer(snapshot: try seededSnapshot())
        let service = ExportService(transfer: transfer)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("otto-corrupt-test.json")
        try Data("not an export".utf8).write(to: file)

        await #expect(throws: ExportFormatError.self) {
            try await service.performImport(from: file, strategy: .replace, now: Date(timeIntervalSince1970: 11_000))
        }
        #expect(await transfer.restoredSnapshots.isEmpty)
    }
}
