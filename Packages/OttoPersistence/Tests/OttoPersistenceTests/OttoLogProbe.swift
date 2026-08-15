import Foundation
import OSLog
import Testing
@testable import OttoPersistence

/// Tells "the app stopped logging" apart from "this host is not delivering logs
/// at all", for the `persistence` category.
///
/// The OttoUI test target has had this since round 2 (`OttoLogProbe` there);
/// this target did not, and `PROD-READINESS-2.md` recorded the remedy as
/// applying to all four log-reading tests when it applied to three.
/// `MappingLogPrivacyTests` read `OSLogStore` and asserted `!ours.isEmpty` with
/// no canary, so on a runner where the store is readable but EMPTY it failed
/// with a message meaning "the store logged nothing for the record it skipped" -
/// byte-identical to the signature of the regression it exists to catch.
///
/// **Closed in round 4 (N3-3).** Every test in this target that reads the log
/// now emits the canary into the window it already opens and calls
/// `requireDelivered` before asserting anything about content. No new query and
/// no new reader was added to do it.
///
/// **The canary is per-test, not a shared literal (N4-11).** Every emission
/// used to write the same `"otto.test.canary"`, and `OSLogStore.position(date:)`
/// reaches ~15 seconds behind `since`, so a sibling test's canary satisfied any
/// test's check even in this `.serialized` target: deleting
/// `MappingLogPrivacyTests`' emission left this suite 127 of 127 green,
/// re-measured at this stage's start. `emitCanary` now mints and returns a
/// token unique to the call, and `requireDelivered` proves THE TEST'S OWN
/// canary was delivered - so a deleted or unemitted canary fails in the full
/// suite, with no `--filter` needed.
enum OttoLogProbe {

    /// Mints this test's own token, emits it, and returns it for the matching
    /// `requireDelivered` call.
    static func emitCanary() -> String {
        let canary = "otto.test.canary.\(UUID().uuidString)"
        mappingLogger.error("\(canary, privacy: .public)")
        return canary
    }

    /// Fails with a message about the machine when the subsystem delivered
    /// nothing, so nobody reads an environment failure as a deleted log line.
    static func requireDelivered(
        _ lines: [String],
        canary: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        try #require(
            lines.contains { $0.contains(canary) },
            """
            The unified log delivered nothing carrying THIS test's own canary, \
            so nothing here is evidence about Otto's code. A sibling's canary \
            no longer stands in - that masking is what the per-test token \
            exists to end. This is an environment failure - a suppressed \
            logging subsystem (OS_ACTIVITY_MODE=disable), an unreadable log \
            store, or a runner that drops entries - not a missing log \
            statement. Do not "fix" it by deleting the assertions it guards.
            """,
            sourceLocation: sourceLocation
        )
    }

    /// Every `persistence` line this process emitted since `since`.
    /// `.currentProcessIdentifier` reads only this process, so the assertion is
    /// about the app rather than about the host.
    static func persistenceLines(since: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        return try store
            .getEntries(
                at: store.position(date: since),
                matching: NSPredicate(
                    format: "subsystem == %@ AND category == %@",
                    "com.arthurzhang.otto", "persistence"
                )
            )
            .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
    }
}
