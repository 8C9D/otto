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
///
/// **The canary is per-test, not a shared literal (N4-11).** Every emission
/// used to write the same `"otto.test.canary"`, and `OSLogStore.position(date:)`
/// reaches ~15 seconds behind `since`, so a sibling test's canary satisfied any
/// test's check: deleting one test's emission left both hosts' full suites
/// green, measured twice in round 4 and re-measured at this stage's start.
/// `emitCanary` now mints and returns a token unique to the call, and
/// `requireDelivered` proves THE TEST'S OWN canary was delivered - so a deleted
/// or unemitted canary fails in the full suite, with no `--filter` needed.
enum OttoLogProbe {

    /// Mints this test's own token, emits it, and returns it for the matching
    /// `requireDelivered` call.
    static func emitCanary(to logger: Logger) -> String {
        let canary = "otto.test.canary.\(UUID().uuidString)"
        logger.notice("\(canary, privacy: .public)")
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
            store, or a runner that drops notice-level entries - not a missing \
            log statement. Do not "fix" it by deleting the assertions it guards.
            """,
            sourceLocation: sourceLocation
        )
    }
}
