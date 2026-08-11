import Foundation
import OSLog
import OttoDomain
import SwiftData
import Testing
@testable import OttoPersistence

/// An error that is not a `MappingError` and carries something that must not
/// reach the log.
private struct CarryingError: Error { let secret = "4821" }

/// R0-4. `mappingLogger` handed `String(describing: error)` a whole
/// `MappingError`, and `.invalidValue` carries the offending value: a trial
/// conversion AMOUNT from `SubscriptionMapping`, or a raw vendor URL from
/// `URL.storedOptional`. Both rendered `<private>` on an ordinary read, which is
/// exactly the reassurance this project tells its readers not to accept -
/// `OttoLog`: *".private redaction is a display rule, not a guarantee about what
/// was written"*, and a sysdiagnose is readable by anyone holding the device.
extension SerializedPersistenceTests {
    @Suite("The persistence log never carries an amount or a vendor URL (R0-4)")
    struct MappingLogPrivacyTests {

        @Test("the value is withheld from the summary, and the field is kept")
        func summaryWithholdsTheValue() {
            let amount = MappingError.invalidValue(
                entity: "TrialTerm",
                field: "lengthDays/bufferDays/convertsToAmountCents",
                value: "14/2/1599"
            )
            #expect(!amount.logSummary.contains("1599"))
            #expect(amount.logSummary.contains("TrialTerm"))
            #expect(amount.logSummary.contains("convertsToAmountCents"))

            let vendor = MappingError.invalidValue(
                entity: "Subscription", field: "vendorURL", value: "https://vendor.example/secret"
            )
            #expect(!vendor.logSummary.contains("vendor.example"))
            #expect(vendor.logSummary.contains("Subscription.vendorURL"))

            // `description` deliberately keeps the value - it is what a thrown
            // error carries to a caller who is entitled to it. Only the LOG
            // summary is redacted, and the two must not be confused.
            #expect(amount.description.contains("1599"))
        }

        @Test("a non-mapping error contributes its type name, never its value")
        func foreignErrorsContributeOnlyAType() {
            #expect(mappingLogSummary(CarryingError()) == "CarryingError")
            #expect(!mappingLogSummary(CarryingError()).contains("4821"))
        }

        /// The emission itself, read back out of this process's own log.
        ///
        /// `OSLogStore(scope: .currentProcessIdentifier)` reads only this
        /// process, so this asserts about the app's code and not about the
        /// host - the objection round 1 recorded as fact and `reviews/REVIEW-5.md`
        /// disproved. Without it the fix has no executable guard at all:
        /// reverting the call site to `String(describing: error)` leaves every
        /// other assertion in this file green, because they test the helper the
        /// call site is supposed to use rather than the call site.
        @Test("⛔ the line the store actually emits carries the field and NOT the value")
        func theEmittedLineIsRedacted() async throws {
            let (store, containers) = try makeStore()
            try await store.save(try makeSubscription(cycleStartDay: try day(2026, 8, 15)))

            // A real unmappable record, corrupted the way a partial sync would:
            // an impossible packed date, whose value reaches `.invalidValue`.
            let context = ModelContext(containers.main)
            let record = try #require(try context.fetch(FetchDescriptor<StoredSubscription>()).first)
            record.cycleStartDay = 20260230
            try context.save()

            let since = Date()
            // Reads through `mapSkippingFailures`, which logs and skips.
            #expect(try await store.subscriptions().isEmpty)

            // Every skip line in the window, not the first.
            //
            // NOT because suites run concurrently - this whole target is
            // `@Suite(.serialized)` (`TestSupport.swift`), so they do not.
            // `OSLogStore.position(date:)` is approximate: it reaches ~80 ms
            // behind `since`, so the window legitimately contains lines from
            // tests that ran just before this one, and the first version of
            // this test asserted about whichever of those came first.
            let skipped = try Self.persistenceLogLines(since: since)
                .filter { $0.contains("Skipping unmappable record") }

            // The discriminating assertion: OUR line, from the record this test
            // corrupted. Every falsification of the fix fails here.
            let ours = skipped.filter { $0.contains("cycleStartDay") }
            #expect(!ours.isEmpty, "the store logged nothing for the record it skipped")
            #expect(ours.allSatisfy { $0.contains("Subscription.cycleStartDay") })
            for line in ours {
                // The packed value the pre-fix line carried into the log.
                #expect(!line.contains("20260230"))
                #expect(!line.contains("<private>"))
            }
            // And, more weakly, no skip line from ANY test in the window
            // carries a redaction marker - after the fix none of them can. A
            // failure here is about the subsystem, not necessarily about this
            // test's record, which is why it is separate from the block above.
            #expect(skipped.allSatisfy { !$0.contains("<private>") })
        }

        /// Every `persistence` line this process emitted since `since`.
        private static func persistenceLogLines(since: Date) throws -> [String] {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: since)
            return try store
                .getEntries(
                    at: position,
                    matching: NSPredicate(
                        format: "subsystem == %@ AND category == %@",
                        "com.arthurzhang.otto", "persistence"
                    )
                )
                .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
        }
    }
}
