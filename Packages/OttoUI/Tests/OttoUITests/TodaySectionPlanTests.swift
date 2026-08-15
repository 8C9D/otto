import Foundation
import Testing
import OttoDomain
import OttoServices
import OttoStores
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

/// R4-1's copy. Asserting the RENDERED string needs an accessibility tree this
/// host does not vend, but choosing between the two wordings does not - and
/// while that choice was private both could be swapped, so a whole failed pass
/// rendered "0 subscriptions couldn't be updated", with every test green.
@Suite("The coverage-gap card says the right one of its two things")
struct CoverageGapCardTests {

    @Test("⛔ a whole failed pass never claims a count, least of all zero")
    func aWholePassFailureHasNoCount() {
        let card = CoverageGapCard(failureCount: 0)
        #expect(card.headline == "Reminders couldn't be updated")
        // The sentence this branch exists to prevent. `subscriptionCountText(0)`
        // rather than "0", so the assertion holds in a locale whose numbering
        // system does not use ASCII digits.
        #expect(!card.headline.contains(subscriptionCountText(0)))
        #expect(card.detail.contains("didn't finish"))
    }

    @Test("a partial failure names how many subscriptions, inflected, and no more than that")
    func aPartialFailureNamesTheCount() {
        // Compared against `subscriptionCountText`, not against a literal
        // "1 subscription": under a locale with its own numbering system that
        // phrase is "١ subscription", and pinning the ASCII form made this suite
        // fail on a host the run itself created as an evidence surface. The
        // branch is still pinned - swap the wordings and the count phrase is
        // absent from the headline entirely.
        // Exact equality, with the count phrase interpolated rather than
        // spelled out: that pins the WHOLE string and still holds in a locale
        // whose numbering system is not ASCII. `contains` alone would accept
        // "1 subscription subscriptions couldn't be updated".
        let one = CoverageGapCard(failureCount: 1)
        #expect(one.headline == "\(subscriptionCountText(1)) couldn't be updated")
        let three = CoverageGapCard(failureCount: 3)
        #expect(three.headline == "\(subscriptionCountText(3)) couldn't be updated")
        // The count is actually used, rather than a fixed phrase that happens
        // to contain one of them.
        #expect(one.headline != three.headline)
        // Wave 10 defect I: the inflection must be RESOLVED, not left as markup.
        #expect(!three.headline.contains("^["))
        #expect(three.detail.contains("their reminders"))
    }
}

private struct SchedulerFailed: Error {}

private struct ThrowingScheduler: ReminderScheduling {
    func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome {
        throw SchedulerFailed()
    }
}

private struct AuthorizedClient: NotificationClient {
    func permission() async -> NotificationPermission { .authorized }
    func requestAuthorization() async -> NotificationPermission { .authorized }
    func pendingRequests() async -> [NotificationRequestSpec] { [] }
    func deliveredIdentifiers() async -> [String] { [] }
    func add(_ spec: NotificationRequestSpec) async throws {}
    func removePendingRequests(withIdentifiers identifiers: [String]) async {}
}

/// The mapping from the stores to `TodaySection.Input`, which used to live in a
/// private method on `TodayView` where nothing could reach it. Deleting the
/// notification half of it left all 185 tests green, so the plan tests above
/// were guarding a rule nothing was feeding.
@MainActor
@Suite("Today reads its input from the stores")
struct TodayInputTests {

    private var overview: TodayOverview {
        TodayOverview(needsAction: [], next30Days: [], later: [])
    }

    private func input(_ notifications: NotificationStatusStore?) -> TodaySection.Input {
        TodaySection.input(
            overview: overview,
            subscriptionsEmpty: false,
            unreadableCount: 0,
            hasReadRepairs: false,
            notifications: notifications
        )
    }

    @Test("⛔ a pass that failed reaches Today - the flag is read from the store, not defaulted")
    func aFailedPassReachesTheScreen() async throws {
        let store = NotificationStatusStore(
            scheduler: ThrowingScheduler(), client: AuthorizedClient(),
            dates: .fixed(today: try #require(CalendarDay(year: 2026, month: 8, day: 6)))
        )
        // Before any pass: nothing has failed, so nothing is claimed.
        #expect(!input(store).lastPassFailed)
        #expect(!TodaySection.plan(input(store)).contains(.coverageGap))

        await store.reschedule()

        // The whole chain, end to end: the pass threw, the store recorded it,
        // the input carried it, and Today plans the card that says so.
        #expect(input(store).lastPassFailed)
        #expect(TodaySection.plan(input(store)).contains(.coverageGap))
    }

    @Test("the permission and the outcome come from the store too, and an absent engine is not a crash")
    func theRestOfTheMappingIsRead() async throws {
        let store = NotificationStatusStore(
            scheduler: ThrowingScheduler(), client: AuthorizedClient(),
            dates: .fixed(today: try #require(CalendarDay(year: 2026, month: 8, day: 6)))
        )
        let horizon = try #require(CalendarDay(year: 2026, month: 11, day: 4))
        store.apply(ScheduleOutcome(
            permission: .authorized, scheduledCount: 3,
            truncatedAfter: nil, coveredThrough: horizon
        ))

        #expect(input(store).permission == .authorized)
        #expect(input(store).scheduleOutcome?.coveredThrough == horizon)
        #expect(TodaySection.plan(input(store)).contains(.coverage))

        #expect(input(nil).permission == nil)
        #expect(input(nil).scheduleOutcome == nil)
        #expect(!input(nil).lastPassFailed)
    }

    /// The last frame the view still owns. `TodayView` used to pick the fields
    /// itself, so `notifications: model.notifications` could be replaced with
    /// `nil` - deleting the permission banner, the coverage sentence and the
    /// gap card at once - with every test green. It passes the whole model now,
    /// and this asserts the model-to-input mapping that replaced it.
    @Test("⛔ Today's input comes from the model's notification store, not from nil")
    func theModelFeedsTheInput() async throws {
        let store = NotificationStatusStore(
            scheduler: ThrowingScheduler(), client: AuthorizedClient(),
            dates: .fixed(today: try #require(CalendarDay(year: 2026, month: 8, day: 6)))
        )
        await store.reschedule()

        let repository = PreviewRepository()
        let model = AppModel(
            repositories: AppModel.Repositories(
                subscriptions: repository, billingEvents: repository,
                cancellations: repository, priceChanges: repository,
                paymentMethods: repository, transfer: repository
            ),
            notifications: store,
            settings: SettingsStore(
                userDefaults: UserDefaults(suiteName: "otto.tests.todayinput") ?? .standard
            ),
            dates: .fixed(today: try #require(CalendarDay(year: 2026, month: 8, day: 6)))
        )

        let built = TodaySection.input(model: model, overview: overview, subscriptionsEmpty: false)
        #expect(built.permission == .authorized)
        #expect(built.lastPassFailed)
        #expect(TodaySection.plan(built).contains(.coverageGap))

        // Every field this function chooses, not just the one the review
        // happened to name: replacing either of the other two with a constant
        // deletes the §5.2b unreadable-record card or the read-repair card from
        // Today for every user, and nothing would have noticed.
        await repository.seedNeedsReview(
            unreadableCount: 2,
            readRepairs: [SubscriptionReadRepairReport(
                subscriptionID: UUID(), name: "Gate Test", repairs: []
            )]
        )
        await model.subscriptionsStore.refresh()
        let withCards = TodaySection.input(
            model: model, overview: overview, subscriptionsEmpty: false
        )
        #expect(withCards.unreadableCount == 2)
        #expect(withCards.hasReadRepairs)
        #expect(TodaySection.plan(withCards).contains(.unreadableRecords))
        #expect(TodaySection.plan(withCards).contains(.readRepairs))
    }
}
