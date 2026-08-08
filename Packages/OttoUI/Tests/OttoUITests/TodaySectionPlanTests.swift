import Testing
import OttoServices
@testable import OttoUI

// Wave 9A defect 1: Today's composition, pinned where the defect lived. The
// permission surface was only ever composed on the non-empty branch, so the
// one user who most needs the request button - first launch, nothing entered
// yet - was the one user who couldn't see it. These tests run host-side, so
// verify.sh counts them.
@Suite("Today's section plan (spec §6 constraint 3, §7.1)")
struct TodaySectionPlanTests {

    private func plan(
        subscriptionsEmpty: Bool = false,
        permission: NotificationPermission? = .authorized,
        unreadableCount: Int = 0,
        hasReadRepairs: Bool = false,
        hasNext30Days: Bool = false,
        hasLater: Bool = false,
        hasScheduleOutcome: Bool = false
    ) -> [TodaySection] {
        TodaySection.plan(TodaySection.Input(
            subscriptionsEmpty: subscriptionsEmpty,
            permission: permission,
            unreadableCount: unreadableCount,
            hasReadRepairs: hasReadRepairs,
            hasNext30Days: hasNext30Days,
            hasLater: hasLater,
            hasScheduleOutcome: hasScheduleOutcome
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
    func coverageFooterConditions() {
        #expect(plan(hasScheduleOutcome: true).contains(.coverage))
        #expect(plan(permission: .provisional, hasScheduleOutcome: true).contains(.coverage))
        #expect(!plan(permission: .denied, hasScheduleOutcome: true).contains(.coverage))
        #expect(!plan(hasScheduleOutcome: false).contains(.coverage))
        // An empty database schedules nothing worth a horizon statement.
        #expect(!plan(subscriptionsEmpty: true, hasScheduleOutcome: true).contains(.coverage))
    }

    @Test("no notification engine means no notification surface, never a crash")
    func absentEngine() {
        #expect(plan(subscriptionsEmpty: true, permission: nil) == [.noSubscriptionsYet])
        #expect(plan(permission: nil) == [.needsAction])
    }
}
