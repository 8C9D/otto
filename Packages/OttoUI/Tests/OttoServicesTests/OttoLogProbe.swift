import Foundation
import OSLog
import Testing
@testable import OttoServices

/// Tells "the app stopped logging" apart from "this host is not delivering
/// logs at all".
///
/// The tests that read `OSLogStore` fail at a `#require(… != nil)` when the line
/// they expect is absent - and `reviews-2/REVIEW-6.md` measured that a host with
/// emission suppressed (`OS_ACTIVITY_MODE=disable`) fails those same tests with
/// a byte-identical signature. Two very different causes, one message, and the
/// wrong one is what a reader will assume.
///
/// So each test emits a known line on the category it is about to read, then
/// checks for it in the SAME read as its real assertion - one `OSLogStore`
/// query per test, because a query costs seconds.
enum OttoLogProbe {

    static let canary = "otto.test.canary"

    static func emitCanary(to logger: Logger) {
        logger.notice("\(canary, privacy: .public)")
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
            unreadable log store, or a runner that drops notice-level entries - \
            not a missing log statement. Do not "fix" it by deleting the \
            assertions it guards.
            """,
            sourceLocation: sourceLocation
        )
    }
}
