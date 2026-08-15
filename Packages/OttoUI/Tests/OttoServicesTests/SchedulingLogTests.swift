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

    /// Followed the item-3 emission change (N2-4 reopened): `OttoLog.failures`
    /// joined every rung into ONE entry, `os_log`'s ~1024-byte per-entry budget
    /// cut the join at 15-16 of 64 rungs named, and the joined-and-sorted
    /// rendering this test asserted no longer exists. Each rung renders alone
    /// now, on an entry of its own, and the ceiling test below asserts that
    /// all 64 arrive - which is what the sorted join could never survive.
    @Test("each failure carries its own reason, rendered as identifier=ErrorType")
    func failedRungCarriesItsReason() {
        #expect(
            OttoLog.failedRung("a|2026-08-20|trialLead", FirstCause())
                == "a|2026-08-20|trialLead=FirstCause"
        )
        // Two causes stay distinguishable pair by pair.
        #expect(
            OttoLog.failedRung("b|2026-08-20|renewal", SecondCause())
                == "b|2026-08-20|renewal=SecondCause"
        )
        // The type, never the value - an error can carry a payload.
        #expect(!OttoLog.failedRung("a|2026-08-20|trialLead", FirstCause()).contains("("))
    }

    /// ⛔ R4-3. `ScheduleOutcome.truncatedAfter` reached no PRODUCTION reader -
    /// the scheduler set it, `coveredThrough` was derived from the same local
    /// variable rather than from the field, and nothing in the app, the UI or
    /// the store layer asked the outcome for it. Two tests did read it
    /// (`NotificationSchedulerTests`, `CatchUpDeliveryTests`), which is why the
    /// claim is scoped here rather than written as "no reader anywhere".
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

    /// The call site, read back out of this process's own log - at the ceiling.
    ///
    /// Without this the fix has no executable guard: `OttoLog.failedRung` could
    /// be correct and unused, which is exactly the shape round 1 shipped for F2
    /// and recorded as R5-2. And the ceiling is the load this guard must carry:
    /// this test's predecessor asserted one subscription's failures inside the
    /// round-2 aggregate entry, which is why the aggregate's truncation - ~1037
    /// characters naming 15 of 64 failed rungs at the 64-slot device ceiling,
    /// measured at this stage's own head - stayed green for two rounds (N2-4
    /// reopened, `reviews-4/REVIEW-AA92CA7.md`).
    @Test("⛔ every failed rung at the 64-rung device ceiling is named, each with its own reason")
    func everyFailedRungIsNamedAtTheCeiling() async throws {
        let fixture = SchedulerFixture()
        // 64 subscriptions this test owns - indices 9_100...9_163, used nowhere
        // else in the package - so every asserted line pins to identifiers no
        // sibling test in the window can emit.
        var subscriptions: [Subscription] = []
        for index in 9_100..<9_164 {
            subscriptions.append(
                try makeSubscription(index: index, cycleStartDay: try day(2026, 8, 25))
            )
        }
        await fixture.subscriptions.seed(subscriptions)
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

        // The fake records every attempted add, refused ones included, so the
        // expected set is calibrated by the pass itself rather than predicted -
        // and its size is the device ceiling, which is the whole point.
        let attempted = await fixture.client.addCalls.map(\.identifier)
        #expect(attempted.count == 64)

        // One read, checked for the canary and all 64 entries.
        let lines = try Self.schedulingLogLines(since: since)
        try OttoLogProbe.requireDelivered(lines)

        // Byte-for-byte, one COMPLETE entry per failed rung, reason included:
        // a prefix or contains match could still be satisfied by a truncated
        // tail, and a rung that fails and is then not named is exactly the
        // loss RF-3 exists to repair.
        for identifier in attempted {
            #expect(
                lines.contains { $0 == "reconcile failed \(identifier)=AddRefused" },
                "failed rung \(identifier) has no complete entry of its own"
            )
        }
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
        // The TRIGGER-TAGGED entry point, which every production caller uses -
        // the coordinator, the action handler and NotificationStatusStore all
        // route through it. Using it here costs nothing (the same pass, the
        // same window, the same single query) and puts the `pass end` line in
        // this test's window, which is what closes N4-5 below.
        _ = try await fixture.scheduler.reschedule(
            now: Date(timeIntervalSince1970: 1_786_000_000),
            today: try day(2026, 8, 11),
            timeZone: TimeZone(identifier: "America/Toronto") ?? .current,
            trigger: .significantTimeChange
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

        // ⛔ R4-3's EMISSION, in the window this test already opened.
        //
        // `OttoLog.passEndFields` has a unit test of its own, and
        // `reviews-4/REVIEW-5.md` measured what that is worth: restoring the
        // pre-fix interpolation at the call site leaves the composer correct,
        // its test green, and all 209 host tests passing - the whole of R4-3
        // put back in production behind a green guard. An earlier version of
        // this run declined to close that on the grounds that it would cost a
        // tenth `OSLogStore` reader. It costs none: this query is already open.
        // Pinned to a trigger no other test in this target uses, because
        // `pass end` carries no subscription identifier and this window is
        // shared - `reviews-4/REVIEW-6.md` made an unpinned version of this
        // assertion pass on a sibling's line while this test's own path was
        // retagged. `.significantTimeChange` appears nowhere else in
        // OttoServicesTests.
        let passEnd = try #require(
            lines.last { $0.hasPrefix("pass end trigger=significantTimeChange") },
            "the trigger-tagged pass emitted no pass-end line of its own"
        )
        #expect(passEnd.contains("truncatedAfter="))
        #expect(passEnd.contains("coveredThrough="))
        #expect(passEnd.contains("ledgerFailures="))
        // And no pass-end line from ANY pass in the window lacks the field, so
        // a second emission site could not reintroduce R4-3 beside this one.
        let allPassEnds = lines.filter { $0.hasPrefix("pass end ") }
        #expect(allPassEnds.allSatisfy { $0.contains("truncatedAfter=") })
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
