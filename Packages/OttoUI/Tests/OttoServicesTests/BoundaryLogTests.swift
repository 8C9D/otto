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
        // Three, so `subscriptions=3` identifies THIS fixture's export line in a
        // window that also holds ExportServiceTests' (which seeds one).
        let snapshot = OttoDataSnapshot(subscriptions: [
            subscription,
            try makeSubscription(index: 92, name: "Zzyzx Two", cycleStartDay: try day(2026, 8, 7)),
            try makeSubscription(index: 93, name: "Zzyzx Three", cycleStartDay: try day(2026, 8, 8))
        ])
        let service = ExportService(transfer: Transfer(snapshot))
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

        // The VALUES, not just the field names. An earlier version of the flake
        // fix dropped `subscriptions=1` to `subscriptions=` and
        // `databaseEmpty=false` to `databaseEmpty=`, which made a line that
        // always reported the database as empty pass - a real weakening, and
        // one this ledger's closing statement denied making
        // (`reviews-3/REVIEW-4.md` finding 5). The count is this fixture's
        // discriminator: three subscriptions is a shape no sibling suite seeds.
        expectLine("export kind=json", "subscriptions=3")
        expectLine("export kind=csv", "bytes=")
        expectLine("import preview", "databaseEmpty=false")
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

        assertPrivacyRule(over: lines, ownIdentifier: subscription.id.uuidString)
    }

    /// The privacy rule `OttoLog` states, asserted over the whole window.
    ///
    /// Split out because the scenario outgrew SwiftLint's 50-line
    /// `function_body_length`; the seam is scenario versus rule, and the rule is
    /// the half worth reading on its own.
    ///
    /// Every line in the window, because a sibling breaking it would be the same
    /// defect in the same category - but ONLY on needles a sibling cannot
    /// produce by accident. `999` was not one of those: the flows category logs
    /// `episode=<random UUID>`, a hex string carries the substring `999` about
    /// 0.5 % of the time, and a full-suite window holds ~25 of them, so an
    /// earlier version of this loop failed 3 runs in 12
    /// (`reviews-3/REVIEW-4.md` finding 1). `Zzyzx` contains letters outside
    /// hex, and `$` and `/` cannot appear in a UUID at all. The amount is
    /// checked only where this test controls the whole population: the lines
    /// carrying its own subscription's identifier.
    private func assertPrivacyRule(over lines: [String], ownIdentifier: String) {
        for entry in lines {
            #expect(!entry.contains("Zzyzx"))
            #expect(!entry.contains("$"))
            #expect(!entry.contains("/"))
        }
        for entry in lines where entry.contains(ownIdentifier) {
            #expect(!entry.contains("99999"))
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
