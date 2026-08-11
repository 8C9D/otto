import Foundation
import OSLog
import OttoDomain
import OttoRepositories
import Testing
@testable import OttoServices

/// F11's remainder. Round 1 verified by grep that there was no logging on
/// import/export, on cancellation or verification, or on notification actions;
/// round 2 closed the third. These are the first two, and they are the two that
/// matter most for a device nobody is watching: a restore that went wrong left
/// no record that a restore had been attempted, and a cancellation that ended a
/// subscription's life left no record either.
///
/// **One `OSLogStore` query for both categories**, because a query costs
/// seconds and this file would otherwise add four. The scenario runs an export,
/// a preview, an import, a cancellation and a verification, then reads once.
@Suite("The boundaries that recorded nothing (F11)")
struct BoundaryLogTests {

    /// The transfer seam, in memory.
    private actor Transfer: DataTransferRepository {
        private var stored: OttoDataSnapshot
        init(_ snapshot: OttoDataSnapshot) { stored = snapshot }
        func completeSnapshot() async throws -> OttoDataSnapshot { stored }
        func restore(
            _ snapshot: OttoDataSnapshot, at instant: Date, watermarks: RestoreWatermarkPolicy
        ) async throws {
            stored = snapshot
        }
        func reconstructMaterializationWatermarks() async throws {}
    }

    @Test("⛔ an export, an import and a cancellation each leave a record")
    func theBoundariesRecordThemselves() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(
            index: 91, name: "Zzyzx Streaming", amountCents: 999_99,
            cycleStartDay: try day(2026, 8, 6),
            cancellationURL: URL(string: "https://zzyzx.example.com/cancel")
        )
        await fixture.subscriptions.seed([subscription])
        let service = ExportService(transfer: Transfer(OttoDataSnapshot(subscriptions: [subscription])))
        let today = try day(2026, 8, 11)
        let now = try fixtureNow()

        let since = Date()
        OttoLogProbe.emitCanary(to: OttoLog.dataTransfer)
        OttoLogProbe.emitCanary(to: OttoLog.flows)

        let exported = try await service.exportJSONFile(exportedAt: now, today: today)
        _ = try await service.exportChargesCSVFile(today: today)
        _ = try await service.importPreview(from: exported)
        _ = try await service.performImport(from: exported, strategy: .merge, now: now)
        _ = try await fixture.flows.startCancellation(subscriptionID: subscription.id, now: now, today: today)
        _ = try await fixture.flows.answerVerification(
            subscriptionID: subscription.id, chargesStopped: true, now: now, today: today
        )

        let lines = try Self.boundaryLines(since: since)
        try OttoLogProbe.requireDelivered(lines)

        func line(_ needle: String) throws -> String {
            try #require(lines.last { $0.contains(needle) }, "nothing was logged for \(needle)")
        }

        #expect(try line("export kind=json").contains("subscriptions=1"))
        #expect(try line("export kind=csv").contains("bytes="))
        #expect(try line("import preview").contains("databaseEmpty=false"))
        #expect(try line("import begin").contains("strategy=merge"))
        #expect(try line("import end").contains("subscriptions="))
        #expect(try line("cancellation started").contains(subscription.id.uuidString))
        #expect(try line("verification answered").contains("chargesStopped=true"))

        // The same privacy rule as every other category: opaque identifiers,
        // calendar days, counts and control-flow outcomes. Never what the user
        // pays for, and never a file path.
        for entry in lines {
            #expect(!entry.contains("Zzyzx"))
            #expect(!entry.contains("999"))
            #expect(!entry.contains("$"))
            #expect(!entry.contains("/"))
        }
    }

    @Test("⛔ the picker's failure half is a failure, and its cancel half is not")
    func pickerOutcomesAreDistinguished() throws {
        struct Unreadable: Error {}
        let url = try #require(URL(string: "file:///tmp/does-not-matter.json"))

        #expect(importPickerOutcome(of: .success(url)) == .selected(url))
        // A dismissed picker must not raise "Nothing was imported" at a user
        // who chose not to import anything.
        #expect(importPickerOutcome(of: .failure(CocoaError(.userCancelled))) == .cancelled)
        // A genuine read error on the recovery path must reach the alert. Before
        // this, it and the cancel above were the same silence.
        let failed = importPickerOutcome(of: .failure(Unreadable()))
        #expect(failed != .cancelled)
        guard case .failed = failed else {
            Issue.record("a real read error was not reported as a failure: \(failed)")
            return
        }
    }

    /// The two new categories in one read.
    private static func boundaryLines(since: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        return try store
            .getEntries(
                at: store.position(date: since),
                matching: NSPredicate(
                    format: "subsystem == %@ AND (category == %@ OR category == %@)",
                    "com.arthurzhang.otto", "transfer", "flows"
                )
            )
            .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
    }
}
