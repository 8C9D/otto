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

        // ANY line in the window carrying both parts, never `.last`.
        //
        // The first version of this test took the LAST line matching each
        // prefix, and that is flaky by construction: `ExportServiceTests`,
        // `SubscriptionFlowTests` and `VerificationFlowTests` exercise these
        // same production paths, swift-testing runs suites in parallel, and
        // `OSLogStore.position(date:)` reaches ~80 ms behind `since` - so the
        // window legitimately holds siblings' lines and `.last` picked one of
        // them. It passed in isolation and under `swift test` here, and failed
        // in `verify.sh`'s clean clone, which is the only reason it was caught.
        // Round 2 recorded exactly this shape for its first emission test.
        //
        // The claim is about the PRODUCTION statement, so a line emitted by a
        // sibling exercising the same path is the same evidence - and deleting
        // the statement removes every one of them, which is what the
        // falsification measures.
        func expectLine(_ needle: String, _ field: String, _ comment: Comment? = nil) {
            #expect(
                lines.contains { $0.contains(needle) && $0.contains(field) },
                comment ?? "no \(needle) line in the window carried \(field)"
            )
        }

        expectLine("export kind=json", "subscriptions=")
        expectLine("export kind=csv", "bytes=")
        expectLine("import preview", "databaseEmpty=")
        expectLine("import begin", "strategy=merge")
        expectLine("import end", "subscriptions=")
        // These two carry an identifier, so they can be pinned to THIS
        // subscription rather than to the category.
        expectLine("cancellation started", subscription.id.uuidString)
        expectLine("verification answered", subscription.id.uuidString)
        #expect(
            lines.contains {
                $0.contains("verification answered")
                    && $0.contains(subscription.id.uuidString)
                    && $0.contains("chargesStopped=true")
            }
        )

        // The same privacy rule as every other category: opaque identifiers,
        // calendar days, counts and control-flow outcomes. Never what the user
        // pays for, and never a file path. Asserted over EVERY line in the
        // window rather than only this test's - a sibling breaking it would be
        // the same defect in the same category.
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
