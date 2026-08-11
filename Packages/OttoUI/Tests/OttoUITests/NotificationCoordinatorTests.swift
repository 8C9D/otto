// R4-2. `NotificationCoordinator` is inside `#if os(iOS)` and compiles to
// nothing under host `swift test`, so reverting `rescheduleSoon` to its pre-fix
// shape left all 580 host tests green and `swiftlint --strict` clean. That path
// carries every unattended trigger - foreground, timezone change, significant
// time change, notification delivered, notification acted on - and the
// background refresh, and none of it was reachable from any test.
//
// UIKit-hosted like `DynamicTypeTests`, so this file runs on the simulator and
// compiles to nothing on a mac host. It is the carry-over `docs/next-wave.md`
// records as "simulator-hosted NotificationCoordinator tests".
#if os(iOS)
import Foundation
import Testing
import OttoDomain
import OttoRepositories
import Synchronization
import UserNotifications
@testable import OttoServices

/// Outside the `@MainActor` suite: the coordinator's `now`/`today` closures are
/// `@Sendable` and cannot capture main-actor state.
private let fixtureToday = CalendarDay(year: 2026, month: 8, day: 11)
private let fixtureInstant = Date(timeIntervalSince1970: 1_786_000_000)

/// What a failing pass throws. File-scope because SwiftLint's `nesting` rule
/// allows one level and the spy is already nested in the suite.
private struct PassRefused: Error {}

@MainActor
@Suite("NotificationCoordinator: the triggers nothing could reach (R4-2)")
struct NotificationCoordinatorTests {

    // MARK: - Fixtures

    /// Records every pass and answers with whatever the test wants. A
    /// `Mutex` rather than an actor because `reschedule` is called from the
    /// coordinator's own `Task` and the assertions read it from the test.
    private final class SchedulerSpy: ReminderScheduling {
        private let state: Mutex<(passes: [CalendarDay], outcome: ScheduleOutcome?)>

        init(outcome: ScheduleOutcome?) {
            state = Mutex(([], outcome))
        }

        var passes: [CalendarDay] { state.withLock { $0.passes } }

        func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome {
            let outcome = state.withLock { current -> ScheduleOutcome? in
                current.passes.append(today)
                return current.outcome
            }
            guard let outcome else { throw PassRefused() }
            return outcome
        }
    }

    /// A `BGAppRefreshTask` stand-in. The real type has no public initializer,
    /// which is why the handler takes the protocol.
    private final class FakeRefreshTask: BackgroundRefreshTask, @unchecked Sendable {
        private let recorded = Mutex<[Bool]>([])
        var expirationHandler: (() -> Void)?

        var completions: [Bool] { recorded.withLock { $0 } }

        func setTaskCompleted(success: Bool) {
            recorded.withLock { $0.append(success) }
        }
    }

    private func makeCoordinator(scheduler: SchedulerSpy) throws -> NotificationCoordinator {
        let day = try #require(fixtureToday)
        return NotificationCoordinator(
            scheduler: scheduler,
            handler: NotificationActionHandler(
                subscriptions: StubSubscriptionRepository(),
                flows: SubscriptionFlowService(
                    subscriptions: StubSubscriptionRepository(),
                    cancellations: StubCancellationRepository(),
                    billingEvents: StubBillingEventRepository(),
                    priceChanges: StubPriceChangeRepository()
                ),
                client: StubNotificationClient(),
                scheduler: scheduler
            ),
            // The injected centre keeps `UNUserNotificationCenter.current()` -
            // which needs an app bundle a test bundle does not have - untouched.
            client: LiveNotificationClient(center: StubCenter()),
            now: { fixtureInstant },
            today: { day },
            timeZone: { TimeZone(identifier: "America/Toronto") ?? .current }
        )
    }

    private func healthyOutcome() throws -> ScheduleOutcome {
        ScheduleOutcome(
            permission: .authorized,
            scheduledCount: 4,
            truncatedAfter: nil,
            coveredThrough: try #require(fixtureToday).adding(days: 90)
        )
    }

    // MARK: - The foreground trigger

    @Test("⛔ the foreground trigger runs a pass and publishes its outcome")
    func foregroundPassPublishes() async throws {
        let scheduler = SchedulerSpy(outcome: try healthyOutcome())
        let coordinator = try makeCoordinator(scheduler: scheduler)
        var published: [ScheduleOutcome?] = []
        coordinator.onOutcome = { published.append($0) }

        await coordinator.appDidBecomeActive().value

        #expect(scheduler.passes == [try #require(fixtureToday)])
        #expect(published.count == 1)
        #expect(published.first??.scheduledCount == 4)
    }

    @Test("⛔ a FAILED foreground pass publishes nil rather than leaving the last success standing")
    func foregroundFailurePublishesNil() async throws {
        let scheduler = SchedulerSpy(outcome: nil)
        let coordinator = try makeCoordinator(scheduler: scheduler)
        var published: [ScheduleOutcome?] = []
        coordinator.onOutcome = { published.append($0) }

        await coordinator.appDidBecomeActive().value

        // The whole point of round 1's F3 fix, and the half of it that had no
        // test: a pass that threw must REPORT the failure, because dropping it
        // leaves the store publishing the last successful outcome and Today
        // stating coverage this pass just failed to renew.
        #expect(published.count == 1)
        let reported = try #require(published.first)
        #expect(reported == nil)
    }

    // MARK: - The background refresh

    @Test("⛔ a background pass publishes its outcome, which it never did")
    func backgroundPassPublishes() async throws {
        let scheduler = SchedulerSpy(outcome: try healthyOutcome())
        let coordinator = try makeCoordinator(scheduler: scheduler)
        let task = FakeRefreshTask()
        var published: [ScheduleOutcome?] = []
        coordinator.onOutcome = { published.append($0) }

        await coordinator.handleBackgroundRefresh(task).value

        #expect(scheduler.passes.count == 1)
        #expect(published.count == 1)
        #expect(published.first??.scheduledCount == 4)
        #expect(task.completions == [true])
    }

    @Test("⛔ a FAILED background pass publishes nil and completes the task unsuccessfully")
    func backgroundFailurePublishesNil() async throws {
        let scheduler = SchedulerSpy(outcome: nil)
        let coordinator = try makeCoordinator(scheduler: scheduler)
        let task = FakeRefreshTask()
        var published: [ScheduleOutcome?] = []
        coordinator.onOutcome = { published.append($0) }

        await coordinator.handleBackgroundRefresh(task).value

        #expect(published.count == 1)
        let reported = try #require(published.first)
        #expect(reported == nil)
        #expect(task.completions == [false])
    }

    @Test("expiration completes the task exactly once, even after the pass returns")
    func expirationCompletesOnce() async throws {
        let scheduler = SchedulerSpy(outcome: try healthyOutcome())
        let coordinator = try makeCoordinator(scheduler: scheduler)
        let task = FakeRefreshTask()

        let work = coordinator.handleBackgroundRefresh(task)
        // Expiration fires while the pass is in flight - the device-observed
        // Gate 2 sequence that produced two `setTaskCompleted` calls before the
        // latch existed.
        task.expirationHandler?()
        await work.value

        #expect(task.completions == [false])
    }
}

// MARK: - Stubs

// Nothing below is exercised by the assertions above; the coordinator's
// initializer requires them, and stubbing is cheaper than reaching for the
// OttoServicesTests fakes, which that target cannot export.

private struct StubSubscriptionRepository: SubscriptionRepository {
    func save(_ subscription: Subscription) async throws {}
    func subscription(withID id: UUID) async throws -> Subscription? { nil }
    func subscriptions() async throws -> [Subscription] { [] }
    func subscriptionsIncludingDeleted() async throws -> [Subscription] { [] }
    func unreadableSubscriptionCount() async throws -> Int { 0 }
    func subscriptionReadRepairs() async throws -> [SubscriptionReadRepairReport] { [] }
    func deleteSubscription(withID id: UUID, at instant: Date) async throws {}
}

private struct StubCancellationRepository: CancellationRepository {
    func save(_ episode: CancellationEpisode) async throws {}
    func openEpisode(forSubscription subscriptionID: UUID) async throws -> CancellationEpisode? { nil }
    func episodes(forSubscription subscriptionID: UUID) async throws -> [CancellationEpisode] { [] }
    func episodesIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [CancellationEpisode] { [] }
}

private struct StubBillingEventRepository: BillingEventRepository {
    func save(_ event: BillingEvent) async throws {}
    func events(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] { [] }
    func eventsIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] { [] }
    func materializeEvents(
        for subscription: Subscription, from today: CalendarDay, horizonDays: Int,
        maxReminderLeadDays: Int, at instant: Date
    ) async throws -> [BillingEvent] { [] }
    func invalidateOutdatedUpcomingEvents(
        for subscription: Subscription, asOf today: CalendarDay, at instant: Date
    ) async throws -> [BillingEvent] { [] }
    func materializationWatermark(forSubscription subscriptionID: UUID) async throws -> CalendarDay? { nil }
    func initializeMaterializationWatermark(forSubscription subscriptionID: UUID, at day: CalendarDay) async throws {}
    func rewindMaterializationWatermark(forSubscription subscriptionID: UUID, to day: CalendarDay) async throws {}
}

private struct StubPriceChangeRepository: PriceChangeRepository {
    func append(_ change: PriceChange) async throws {}
    func history(forSubscription subscriptionID: UUID) async throws -> [PriceChange] { [] }
    func historyIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [PriceChange] { [] }
}

private struct StubNotificationClient: NotificationClient {
    func permission() async -> NotificationPermission { .authorized }
    func requestAuthorization() async -> NotificationPermission { .authorized }
    func pendingRequests() async -> [NotificationRequestSpec] { [] }
    func deliveredIdentifiers() async -> [String] { [] }
    func add(_ spec: NotificationRequestSpec) async throws {}
    func removePendingRequests(withIdentifiers identifiers: [String]) async {}
}

private struct StubCenter: UserNotificationCentering {
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func deliveredNotificationIdentifiers() async -> [String] { [] }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}
#endif
