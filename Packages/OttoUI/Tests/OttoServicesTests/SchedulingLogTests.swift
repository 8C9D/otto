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

    /// ⛔ R4-3. `ScheduleOutcome.truncatedAfter` reached nothing at all - the
    /// scheduler set it, `coveredThrough` was derived from the same local, and
    /// no reader anywhere asked the outcome for it.
    ///
    /// The discriminating case, which is the whole finding: two passes that
    /// agree on EVERY field the line used to carry, one of which dropped rungs
    /// past the 64-slot budget and one of which dropped none. `coveredThrough`
    /// cannot tell them apart, because a truncated pass's covered day IS its
    /// truncation point and a whole pass's is its horizon end - and those are
    /// the same day whenever the horizon happens to land there. Before this the
    /// two lines were byte-identical.
    @Test("⛔ the pass-end line distinguishes a truncated pass from a whole one")
    func thePassEndLineCarriesTheTruncation() throws {
        let day = try day(2026, 9, 1)
        let truncated = ScheduleOutcome(
            permission: .authorized, scheduledCount: 64,
            truncatedAfter: day, coveredThrough: day
        )
        let whole = ScheduleOutcome(
            permission: .authorized, scheduledCount: 64,
            truncatedAfter: nil, coveredThrough: day
        )

        let truncatedLine = OttoLog.passEndFields(trigger: .foreground, outcome: truncated)
        let wholeLine = OttoLog.passEndFields(trigger: .foreground, outcome: whole)

        #expect(truncatedLine != wholeLine)
        #expect(truncatedLine.contains("truncatedAfter=2026-09-01"))
        #expect(wholeLine.contains("truncatedAfter=none"))
        // The fields that were already there are still there, in a line that is
        // now composed rather than interpolated at the call site.
        for line in [truncatedLine, wholeLine] {
            #expect(line.hasPrefix("pass end trigger=foreground"))
            #expect(line.contains("permission=authorized"))
            #expect(line.contains("scheduled=64"))
            #expect(line.contains("coveredThrough=2026-09-01"))
            #expect(line.contains("ledgerFailures=0"))
        }
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

    /// R0-7 / N2-2's line, read back the same way and for the same reason.
    ///
    /// The coverage half of that fix has its own executable guard
    /// (`ImplausibleStoredDayTests`); this is the diagnostic half. A user who
    /// sees the gap card still needs someone to be able to find out WHICH days
    /// are wrong, and a log line that names them is the only surface that does
    /// - so it has to be readable, and it has to still be there after the next
    /// edit.
    @Test("⛔ a skipped subscription's line names the offending days, and nothing about the vendor")
    func theEmittedSkipLineNamesTheDays() async throws {
        let fixture = SchedulerFixture()
        // What a pre-F1 build wrote on a Buddhist device. The name is
        // distinctive so its ABSENCE from the line is a real assertion.
        let subscription = try makeSubscription(
            index: 88, name: "Zzyzx Streaming", amountCents: 999_99, cycleStartDay: try day(2569, 8, 6)
        )
        await fixture.subscriptions.seed([subscription])

        let since = Date()
        OttoLogProbe.emitCanary(to: OttoLog.scheduling)
        _ = try await fixture.scheduler.reschedule(
            now: Date(timeIntervalSince1970: 1_786_000_000),
            today: try day(2026, 8, 11),
            timeZone: TimeZone(identifier: "America/Toronto") ?? .current
        )

        let lines = try Self.schedulingLogLines(since: since)
        try OttoLogProbe.requireDelivered(lines)

        let mine = try fixtureUUID(88).uuidString.lowercased()
        let line = try #require(
            lines.last { $0.contains("reason=implausibleStoredDays") && $0.lowercased().contains(mine) },
            "the pass skipped the subscription without saying which days made it skip"
        )

        // The days themselves, not a count: "one of its dates is wrong" is not
        // something a user can act on, and 2569-08-06 is.
        #expect(line.contains("2569-08-06"))
        #expect(line.contains("today=2026-08-11"))
        // The same privacy rule as every other line in this file: an opaque
        // identifier, calendar days, and a control-flow outcome. Never what the
        // user pays for.
        #expect(!line.contains("Zzyzx"))
        #expect(!line.contains("999"))
        #expect(!line.contains("$"))
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
