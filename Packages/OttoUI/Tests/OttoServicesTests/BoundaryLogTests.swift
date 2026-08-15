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
        let transferCanary = OttoLogProbe.emitCanary(to: OttoLog.dataTransfer)
        let flowsCanary = OttoLogProbe.emitCanary(to: OttoLog.flows)

        let exported = try await service.exportJSONFile(exportedAt: now, today: today)
        _ = try await service.exportChargesCSVFile(today: today)
        _ = try await service.importPreview(from: exported)
        _ = try await service.performImport(from: exported, strategy: .merge, now: now)
        _ = try await fixture.flows.startCancellation(subscriptionID: subscription.id, now: now, today: today)
        _ = try await fixture.flows.answerVerification(
            subscriptionID: subscription.id, chargesStopped: true, now: now, today: today
        )
        try await exerciseRefusals(fixture.flows, absent: try fixtureUUID(9_401), now: now, today: today)

        let lines = try Self.boundaryLines(since: since)
        // Both categories, each on its own token: the shared literal let
        // EITHER category's delivery satisfy this check, so the one read
        // over two categories was only ever proving one of them.
        try OttoLogProbe.requireDelivered(lines, canary: transferCanary)
        try OttoLogProbe.requireDelivered(lines, canary: flowsCanary)

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

        assertLinesRecorded(lines, own: subscription.id.uuidString, absent: try fixtureUUID(9_401).uuidString)
        assertPrivacyRule(over: lines, ownIdentifier: subscription.id.uuidString)
    }

    /// Which line must exist, and with which value.
    ///
    /// Split out to keep the scenario under SwiftLint's `function_body_length`;
    /// the seam is "run the boundaries" against "say what they must have said".
    private func assertLinesRecorded(_ lines: [String], own: String, absent: String) {
        // ANY line in the window carrying both parts, never `.last`.
        //
        // The first version took the LAST line matching each prefix, and that is
        // flaky by construction: `ExportServiceTests`, `SubscriptionFlowTests`
        // and `VerificationFlowTests` exercise these same production paths,
        // swift-testing runs suites in parallel, and `OSLogStore.position(date:)`
        // reaches ~80 ms behind `since`. It passed in isolation and failed in
        // `verify.sh`'s clean clone. The claim is about the PRODUCTION
        // statement, so a line a sibling emitted from the same path is the same
        // evidence - and deleting the statement removes every one of them,
        // which is what the falsification measures.
        func expectLine(_ needle: String, _ field: String) {
            #expect(
                lines.contains { $0.contains(needle) && $0.contains(field) },
                "no \(needle) line in the window carried \(field)"
            )
        }

        // The VALUES, not just the field names. An earlier version of the flake
        // fix dropped `subscriptions=1` to `subscriptions=` and
        // `databaseEmpty=false` to `databaseEmpty=`, so a line always reporting
        // the database as empty would have passed - a real weakening, and one
        // the ledger's closing statement denied making. Three subscriptions is
        // this fixture's discriminator: no sibling suite seeds that many.
        expectLine("export kind=json", "subscriptions=3")
        expectLine("export kind=csv", "bytes=")
        expectLine("import preview", "databaseEmpty=false")
        expectLine("import begin", "strategy=merge")
        expectLine("import end", "subscriptions=")

        // The REFUSAL lines. Deleting all five of the refusal statements added
        // for `reviews-3/REVIEW-4.md` finding 3 left the suite 207/207 green -
        // round 1's F2 shape, recorded in this target's own
        // `NotificationActionLogTests` header, shipped again. Four of the seven
        // are reachable from a missing subscription and are pinned here.
        expectLine("cancellation refused reason=noSubscription", absent)
        expectLine("cancellation abandon refused reason=noSubscription", absent)
        expectLine("verification refused reason=noOpenAnswerableEpisode", absent)
        expectLine("verification resumeDate refused", absent)

        // These carry an identifier, so they pin to THIS subscription.
        expectLine("cancellation started", own)
        expectLine("verification answered", own)
        #expect(
            lines.contains {
                $0.contains("verification answered") && $0.contains(own) && $0.contains("chargesStopped=true")
            }
        )
    }

    /// The four refusal paths that a missing subscription reaches, so their log
    /// lines have a guard rather than only a source comment.
    ///
    /// Split out to keep the scenario under SwiftLint's `function_body_length`.
    /// The other three refusals - a lifecycle already past cancellation, an
    /// un-cancel that cannot restore its interrupted status, and a dispute with
    /// no watched date - need multi-step state and are recorded as unguarded in
    /// `PROD-READINESS-3.md`.
    private func exerciseRefusals(
        _ flows: SubscriptionFlowService,
        absent: UUID,
        now: Date,
        today: CalendarDay
    ) async throws {
        _ = try await flows.startCancellation(subscriptionID: absent, now: now, today: today)
        try await flows.abandonCancellation(subscriptionID: absent, now: now, today: today)
        _ = try await flows.answerVerification(
            subscriptionID: absent, chargesStopped: true, now: now, today: today
        )
        try await flows.supplyPausedResumeDate(subscriptionID: absent, resumeDate: today, now: now)
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
        // With every UUID removed first. The shipped comment used to claim this
        // loop controlled its whole population and it did not: `cancellation
        // started … episode=<UUID()>` carries hex this test never chose, so the
        // needle could be matched by a value the assertion is not about
        // (`reviews-3/REVIEW-5.md` finding 4 - ~1.1e-5 per run rather than the
        // 25 % the earlier `999` needle carried, but the same mistake).
        for entry in lines where entry.contains(ownIdentifier) {
            #expect(!Self.withoutIdentifiers(entry).contains("99999"))
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

    /// Every `<uuid>` removed, so an assertion about CONTENT is not matched by
    /// randomly generated hex.
    private static func withoutIdentifiers(_ line: String) -> String {
        line.replacingOccurrences(
            of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
            with: "<uuid>",
            options: .regularExpression
        )
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
