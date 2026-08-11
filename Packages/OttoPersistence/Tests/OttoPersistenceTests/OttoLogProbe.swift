import Foundation
import OSLog
import Testing
@testable import OttoPersistence

/// Tells "the app stopped logging" apart from "this host is not delivering logs
/// at all", for the `persistence` category.
///
/// The OttoUI test target has had this since round 2 (`OttoLogProbe` there);
/// this target did not, and `PROD-READINESS-2.md` records the remedy as applying
/// to all four log-reading tests. It applies to three: `MappingLogPrivacyTests`
/// reads `OSLogStore` and asserts `!ours.isEmpty` with no canary, so on a runner
/// where the store is readable but EMPTY it fails with a message meaning "the
/// store logged nothing for the record it skipped" - byte-identical to the
/// signature of the regression it exists to catch. That is the misdiagnosis the
/// canary was introduced to prevent, still open in the one place nobody
/// checked. Recorded in `PROD-READINESS-3.md` NEXT ROUND; not changed here,
/// because rewriting a passing test from another round's item is outside this
/// run's scope.
enum OttoLogProbe {

    static let canary = "otto.test.canary"

    static func emitCanary() {
        mappingLogger.error("\(canary, privacy: .public)")
    }

    /// Fails with a message about the machine when the subsystem delivered
    /// nothing, so nobody reads an environment failure as a deleted log line.
    static func requireDelivered(
        _ lines: [String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        try #require(
            lines.contains { $0.contains(canary) },
            """
            The unified log delivered NOTHING for this process, so nothing here \
            is evidence about Otto's code. This is an environment failure - a \
            suppressed logging subsystem (OS_ACTIVITY_MODE=disable), an \
            unreadable log store, or a runner that drops entries - not a missing \
            log statement. Do not "fix" it by deleting the assertions it guards.
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
