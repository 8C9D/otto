import Foundation
import Testing
import OttoDomain
import OttoServices
@testable import OttoStores

/// What Today is allowed to SAY about coverage.
///
/// The screen renders "Reminders scheduled through <day>" from the published
/// `ScheduleOutcome`. Two different ways that sentence can be a lie, and one
/// fix does not close the other:
///  - the last pass FAILED, and the sentence still describes the pass before it;
///  - the last pass SUCCEEDED but reconciled the ledger for only some
///    subscriptions, so `coveredThrough` describes a plan that some of the
///    user's subscriptions are not in.
@MainActor
@Suite("Coverage is stated only when it is true")
struct CoverageHonestyTests {

    private struct ThrowingScheduler: ReminderScheduling {
        struct Failed: Error {}
        func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome {
            throw Failed()
        }
    }

    private struct FixedClient: NotificationClient {
        var permission: NotificationPermission = .authorized
        func permission() async -> NotificationPermission { permission }
        func requestAuthorization() async -> NotificationPermission { permission }
        func pendingRequests() async -> [NotificationRequestSpec] { [] }
        func deliveredIdentifiers() async -> [String] { [] }
        func add(_ spec: NotificationRequestSpec) async throws {}
        func removePendingRequests(withIdentifiers identifiers: [String]) async {}
    }

    private func outcome(
        ledgerFailures: [UUID] = [], coveredThrough: CalendarDay
    ) -> ScheduleOutcome {
        ScheduleOutcome(
            permission: .authorized,
            scheduledCount: 3,
            truncatedAfter: nil,
            coveredThrough: coveredThrough,
            ledgerFailures: ledgerFailures
        )
    }

    @Test("a failed pass drops the previous outcome - no claim beats a stale one")
    func failedPassClearsTheOutcome() async throws {
        let store = NotificationStatusStore(
            scheduler: ThrowingScheduler(), client: FixedClient(),
            dates: .fixed(today: try day(2026, 8, 6))
        )
        let day = try day(2026, 11, 4)
        store.apply(outcome(coveredThrough: day))
        #expect(store.outcome?.coveredThrough == day)

        await store.reschedule()

        // Not the old outcome, and not a fabricated new one.
        #expect(store.outcome == nil)
        // The permission is still refreshed - a failed pass says nothing about
        // whether notifications are allowed.
        #expect(store.permission == .authorized)
    }

    @Test("a pass that failed some subscriptions' ledgers may not claim coverage")
    func ledgerFailuresWithdrawTheCoverageClaim() throws {
        let day = try day(2026, 11, 4)
        #expect(outcome(coveredThrough: day).canClaimCoverage)
        // Succeeded overall, and reports the full horizon - but a subscription
        // whose materialization threw has no rows and no reminders this pass.
        #expect(!outcome(ledgerFailures: [UUID()], coveredThrough: day).canClaimCoverage)
    }
}
