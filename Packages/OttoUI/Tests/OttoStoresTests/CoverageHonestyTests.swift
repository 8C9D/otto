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
private struct SchedulerFailed: Error {}

private struct ThrowingScheduler: ReminderScheduling {
    func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome {
        throw SchedulerFailed()
    }
}

@MainActor
@Suite("Coverage is stated only when it is true")
struct CoverageHonestyTests {

    private struct FixedClient: NotificationClient {
        var permission: NotificationPermission = .denied
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
        // The system says denied; the stale outcome says authorized. A failed
        // pass has to go to the system rather than trust what it already held.
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
        // The permission is still refreshed FROM THE SYSTEM. Asserting
        // .authorized here would have been unfalsifiable: apply(outcome) on the
        // seeding line already set it, so deleting the refresh entirely left
        // the assertion green.
        #expect(store.permission == .denied)
    }

    /// R4-1's store half. `outcome == nil` means two opposite things - "no pass
    /// has run yet" and "the last pass failed" - and Today has to tell them
    /// apart, or the replacement for the withdrawn coverage sentence would fire
    /// on every cold start before the first pass finished.
    @Test("a failed pass is distinguishable from no pass having run yet")
    func failureIsDistinguishableFromNotYetRun() async throws {
        let store = NotificationStatusStore(
            scheduler: ThrowingScheduler(), client: FixedClient(),
            dates: .fixed(today: try day(2026, 8, 6))
        )
        // Fresh: nothing has run, so nothing has failed.
        #expect(store.outcome == nil)
        #expect(!store.lastPassFailed)

        await store.reschedule()
        #expect(store.outcome == nil)
        #expect(store.lastPassFailed)

        // And a later successful pass clears it, so the warning does not
        // outlive the failure it describes.
        store.apply(outcome(coveredThrough: try day(2026, 11, 4)))
        #expect(!store.lastPassFailed)
    }
}
