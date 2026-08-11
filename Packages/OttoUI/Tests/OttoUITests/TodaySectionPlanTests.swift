import Foundation
import Testing
import OttoDomain
import OttoServices
@testable import OttoUI

// Wave 9A defect 1: Today's composition, pinned where the defect lived. The
// permission surface was only ever composed on the non-empty branch, so the
// one user who most needs the request button - first launch, nothing entered
// yet - was the one user who couldn't see it. These tests run host-side, so
// verify.sh counts them.
@Suite("Today's section plan (spec §6 constraint 3, §7.1)")
struct TodaySectionPlanTests {

    /// The horizon day the outcome fixtures claim coverage through. A stored
    /// constant rather than a force-unwrap, so an invalid literal would be a
    /// compile-time-visible nil here instead of a crash inside a test.
    private static let horizon = CalendarDay(year: 2026, month: 11, day: 4)

    /// A pass that succeeded with nothing left behind.
    private func healthyOutcome(ledgerFailures: [UUID] = []) throws -> ScheduleOutcome {
        ScheduleOutcome(
            permission: .authorized,
            scheduledCount: 3,
            truncatedAfter: nil,
            coveredThrough: try #require(Self.horizon),
            ledgerFailures: ledgerFailures
        )
    }

    /// The rule R0-1 added, pinned where it is actually applied.
    ///
    /// The gate lived in the SwiftUI body as `outcome?.canClaimCoverage ?? false`
    /// - unreachable by any test, so reverting it left the suite green. It is
    /// `plan`'s decision now, and this asserts the mapping rather than
    /// restating `ledgerFailures.isEmpty` under another name.
    @Test("a pass that failed some subscriptions' ledgers withdraws the coverage claim from Today")
    func ledgerFailuresWithdrawCoverageFromThePlan() throws {
        #expect(plan(scheduleOutcome: try healthyOutcome()).contains(.coverage))
        #expect(!plan(scheduleOutcome: try healthyOutcome(ledgerFailures: [UUID()])).contains(.coverage))
    }

    /// R4-1. Withdrawing the coverage sentence was right, but `.notificationStatus`
    /// renders only for a permission other than authorized, so what an authorized
    /// user with a broken engine saw afterwards was a screen with no notification
    /// surface on it at all - the same screen a healthy engine produces, minus one
    /// line they had no way to miss.
    @Test("⛔ an authorized user with a failing engine is NOT shown a healthy Today")
    func aFailingEngineIsVisibleToAnAuthorizedUser() throws {
        let healthy = plan(hasNext30Days: true, scheduleOutcome: try healthyOutcome())
        let ledgerFailed = plan(
            hasNext30Days: true,
            scheduleOutcome: try healthyOutcome(ledgerFailures: [UUID()])
        )
        let passFailed = plan(hasNext30Days: true, lastPassFailed: true)

        // The whole finding in one line: before the gap card, both of these
        // equalled `healthy` minus `.coverage` and carried nothing in its place.
        #expect(ledgerFailed != healthy)
        #expect(passFailed != healthy)
        #expect(ledgerFailed.contains(.coverageGap))
        #expect(passFailed.contains(.coverageGap))
        #expect(!healthy.contains(.coverageGap))
        // Never both: the screen states coverage or states that it could not be
        // earned, never one under the other.
        #expect(!ledgerFailed.contains(.coverage))
    }

    @Test("the gap card does not fire before the first pass has run, or where nothing can be delivered")
    func theGapCardDoesNotCryWolf() throws {
        // Fresh launch: no pass has run, `outcome` is nil and nothing failed.
        // A warning here would appear on every cold start.
        #expect(!plan(scheduleOutcome: nil).contains(.coverageGap))
        // Denied and not-determined already have `.notificationStatus`, which
        // says something truer and more actionable.
        #expect(!plan(permission: .denied, lastPassFailed: true).contains(.coverageGap))
        #expect(!plan(permission: .notDetermined, lastPassFailed: true).contains(.coverageGap))
        #expect(!plan(permission: nil, lastPassFailed: true).contains(.coverageGap))
        // Provisional can deliver, so it gets the same honesty as authorized.
        #expect(plan(permission: .provisional, lastPassFailed: true).contains(.coverageGap))
        // An empty database has no reminders to be missing.
        #expect(!plan(subscriptionsEmpty: true, lastPassFailed: true).contains(.coverageGap))
    }

    private func plan(
        subscriptionsEmpty: Bool = false,
        permission: NotificationPermission? = .authorized,
        unreadableCount: Int = 0,
        hasReadRepairs: Bool = false,
        hasNext30Days: Bool = false,
        hasLater: Bool = false,
        scheduleOutcome: ScheduleOutcome? = nil,
        lastPassFailed: Bool = false
    ) -> [TodaySection] {
        TodaySection.plan(TodaySection.Input(
            subscriptionsEmpty: subscriptionsEmpty,
            permission: permission,
            unreadableCount: unreadableCount,
            hasReadRepairs: hasReadRepairs,
            hasNext30Days: hasNext30Days,
            hasLater: hasLater,
            scheduleOutcome: scheduleOutcome,
            lastPassFailed: lastPassFailed
        ))
    }

    @Test("a first-launch user with zero subscriptions can reach the permission request from Today")
    func firstLaunchReachesPermissionRequest() {
        // Empty database, permission never asked - the exact state the first
        // hands-on session found: iOS Settings had no Notifications row at all.
        let sections = plan(subscriptionsEmpty: true, permission: .notDetermined)
        #expect(sections == [.notificationStatus, .noSubscriptionsYet])
    }

    @Test("the denied banner also survives an empty database")
    func deniedBannerSurvivesEmptyDatabase() {
        let sections = plan(subscriptionsEmpty: true, permission: .denied)
        #expect(sections.first == .notificationStatus)
    }

    @Test("an authorized empty database shows only the empty state - no nagging")
    func authorizedEmptyDatabaseIsQuiet() {
        let sections = plan(subscriptionsEmpty: true, permission: .authorized)
        #expect(sections == [.noSubscriptionsYet])
    }

    @Test("unreadable-record and read-repair cards also survive an empty readable list")
    func needsReviewCardsSurviveEmptyDatabase() {
        // Every readable record failing to map leaves an empty list - the state
        // where hiding "N subscriptions couldn't be read" would be worst.
        let sections = plan(
            subscriptionsEmpty: true,
            permission: .authorized,
            unreadableCount: 2,
            hasReadRepairs: true
        )
        #expect(sections == [.unreadableRecords, .readRepairs, .noSubscriptionsYet])
    }

    @Test("a populated database composes the sections in spec §7.1 order")
    func populatedOrder() {
        let sections = plan(
            permission: .notDetermined,
            unreadableCount: 1,
            hasReadRepairs: true,
            hasNext30Days: true,
            hasLater: true
        )
        #expect(sections == [
            .notificationStatus, .unreadableRecords, .readRepairs,
            .needsAction, .next30Days, .later
        ])
    }

    @Test("the coverage footer needs a schedule outcome AND a permission that can deliver")
    func coverageFooterConditions() throws {
        #expect(plan(scheduleOutcome: try healthyOutcome()).contains(.coverage))
        #expect(plan(permission: .provisional, scheduleOutcome: try healthyOutcome()).contains(.coverage))
        #expect(!plan(permission: .denied, scheduleOutcome: try healthyOutcome()).contains(.coverage))
        #expect(!plan(scheduleOutcome: nil).contains(.coverage))
        // An empty database schedules nothing worth a horizon statement.
        #expect(!plan(subscriptionsEmpty: true, scheduleOutcome: try healthyOutcome()).contains(.coverage))
    }

    @Test("no notification engine means no notification surface, never a crash")
    func absentEngine() {
        #expect(plan(subscriptionsEmpty: true, permission: nil) == [.noSubscriptionsYet])
        #expect(plan(permission: nil) == [.needsAction])
    }
}
