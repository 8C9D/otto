import Foundation
import OSLog
import OttoDomain
import Testing
@testable import OttoServices

private struct FirstCause: Error {}
private struct SecondCause: Error {}

/// RF-3. `reconcile` attempts every rung and collects every failure, but it can
/// rethrow only one - so a log line carrying bare identifiers left the REASONS
/// for failures 2..n reaching neither the log nor the caller. On a device where
/// two causes coexist, an investigation saw one error type and a list of names,
/// and could not tell a second cause existed.
///
/// This information did not exist before round 1's F5 fix (those adds were never
/// attempted at all), so delivery was already a strict improvement and only
/// diagnosability was short.
@Suite("What a failed scheduling pass leaves behind (RF-3)")
struct SchedulingLogTests {

    @Test("each failure contributes its own reason, not a shared one")
    func failuresCarryReasonsPerRung() {
        let rendered = OttoLog.failures([
            (id: "b|2026-08-20|renewal", error: SecondCause()),
            (id: "a|2026-08-20|trialLead", error: FirstCause())
        ])
        // Sorted, so a diff of two passes is readable.
        #expect(rendered == "a|2026-08-20|trialLead=FirstCause b|2026-08-20|renewal=SecondCause")
        // The type, never the value - an error can carry a payload.
        #expect(!rendered.contains("("))
    }

    @Test("no failures reads as a dash, like the other identifier lists")
    func noFailures() {
        #expect(OttoLog.failures([]) == "-")
    }

    /// The call site, read back out of this process's own log.
    ///
    /// Without this the fix has no executable guard: `OttoLog.failures` could be
    /// correct and unused, which is exactly the shape round 1 shipped for F2 and
    /// recorded as R5-2.
    @Test("⛔ the reconcile line the scheduler actually emits names a reason per failed rung")
    func theEmittedReconcileLineCarriesReasons() async throws {
        let fixture = SchedulerFixture()
        // A distinctive id, and one plain monthly subscription: this line has to
        // be identifiable among the reconcile lines of every other test in the
        // window (OSLogStore.position(date:) reaches ~80 ms behind `since`), and
        // short enough that os_log does not truncate the field being asserted.
        let subscription = try makeSubscription(index: 77, cycleStartDay: try day(2026, 8, 25))
        await fixture.subscriptions.seed([subscription])
        await fixture.client.refuseAdds(after: 0)

        let since = Date()
        OttoLogProbe.emitCanary(to: OttoLog.scheduling)
        await #expect(throws: FakeNotificationClient.AddRefused.self) {
            _ = try await fixture.scheduler.reschedule(
                now: Date(timeIntervalSince1970: 1_786_000_000),
                today: try day(2026, 8, 20),
                timeZone: TimeZone(identifier: "America/Toronto") ?? .current
            )
        }

        // One read, checked for both the canary and the real line.
        let lines = try Self.schedulingLogLines(since: since)
        try OttoLogProbe.requireDelivered(lines)

        let mine = try fixtureUUID(77).uuidString.lowercased()
        let line = try #require(
            lines.last { $0.hasPrefix("reconcile failed=[") && $0.lowercased().contains(mine) },
            "the pass logged no reconcile failure line naming this subscription"
        )

        // The identifiers were always here. The reasons were not. They are on
        // their own entry now, so `os_log`'s per-entry budget cannot truncate
        // them away behind the (deliberately complete) added/removed lists.
        #expect(line.contains("failed=["))
        #expect(line.contains("=AddRefused"))
        // Not the bare-identifier shape: every failed rung is followed by its
        // own reason, so two causes are distinguishable.
        let failed = try #require(line.components(separatedBy: "failed=[").last)
        let identifiers = failed.replacingOccurrences(of: "]", with: "")
            .split(separator: " ").map(String.init)
        #expect(!identifiers.isEmpty)
        #expect(identifiers.allSatisfy { $0.contains("=") })
    }

    /// Every `scheduling` line this process emitted since `since`.
    /// `.currentProcessIdentifier` reads only this process, so the assertion is
    /// about the app rather than about the host.
    static func schedulingLogLines(since: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        return try store
            .getEntries(
                at: store.position(date: since),
                matching: NSPredicate(
                    format: "subsystem == %@ AND category == %@",
                    "com.arthurzhang.otto", "scheduling"
                )
            )
            .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
    }
}
