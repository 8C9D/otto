// Round 5, item 10 (N3-6b): `start()` and the delegate bodies, which nothing
// could reach. Reproduced by execution at the stage start: with the delegate
// assignment deleted from `start()` AND the `.notificationDelivered` reschedule
// deleted from `willPresent`, the full host suite (232) and the full simulator
// suite (133/73/67) were green.
//
// What closed it: the delegate install goes through the `UserNotificationCentering`
// seam, the `BGTaskScheduler` registration through `BackgroundTaskRegistering`
// (both at the system boundary, the `LiveNotificationClient` rule), and the two
// delegate bodies are internal methods on the facts the responses carry. The
// residual floor, stated rather than papered over: the two `nonisolated`
// wrappers (`UNNotification`/`UNNotificationResponse` have no public
// initializers) and the launch closure's downcast-and-reject body (`BGTask`
// has none either) stay reachable only by the OS.
//
// UIKit-hosted like the sibling coordinator files: simulator only, nothing on
// a mac host. `.serialized`, because `start()` installs observers on the
// process-global `NotificationCenter.default` and the timezone tests post to
// it - two live started coordinators would count each other's posts.
#if os(iOS)
import BackgroundTasks
import Foundation
import Testing
import OttoDomain
import Synchronization
import UIKit
import UserNotifications
@testable import OttoServices

/// Outside the `@MainActor` suite for the reason the sibling files record: the
/// coordinator's closures are `@Sendable`.
private let startFixtureDay = CalendarDay(year: 2026, month: 8, day: 15)
private let startFixtureInstant = Date(timeIntervalSince1970: 1_786_000_000)

/// Counts passes and answers healthily - these tests assert that a pass RAN,
/// not what it did; the pass's own semantics are the sibling suites' business.
/// File-scope for the `nesting` reason `NotificationCoordinatorTests` records.
private final class CountingScheduler: ReminderScheduling {
    private let recorded = Mutex(0)

    var passes: Int { recorded.withLock { $0 } }

    func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome {
        recorded.withLock { $0 += 1 }
        return ScheduleOutcome(
            permission: .authorized, scheduledCount: 4, truncatedAfter: nil,
            coveredThrough: today
        )
    }
}

/// `StubCenter` plus the two records `start()`'s claims need: the categories
/// handed over and the delegate installed. `@unchecked Sendable` because every
/// property is read and written on the main actor alone (the `FakeRefreshTask`
/// precedent); the delegate is weak, as the real center's is.
private final class RecordingCenter: UserNotificationCentering, @unchecked Sendable {
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) weak var installedDelegate: (any UNUserNotificationCenterDelegate)?
    private(set) var installCount = 0

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = categories
    }

    func installDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        installedDelegate = delegate
        installCount += 1
    }

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func deliveredNotificationIdentifiers() async -> [String] { [] }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}

/// Records what `start()` registers. The captured handler is held but never
/// invoked: it takes the framework's `BGTask`, which no test can construct -
/// the residual floor the header states. `handleBackgroundRefresh` itself is
/// covered through the `BackgroundRefreshTask` seam in the sibling suites.
private final class RecordingTaskRegistrar: BackgroundTaskRegistering {
    struct Registration {
        let identifier: String
        let queue: DispatchQueue?
        let launchHandler: (BGTask) -> Void
    }

    private(set) var registrations: [Registration] = []

    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (BGTask) -> Void
    ) -> Bool {
        registrations.append(Registration(
            identifier: identifier, queue: queue, launchHandler: launchHandler
        ))
        return true
    }
}

@MainActor
@Suite("NotificationCoordinator.start() and the delegate bodies (N3-6b)", .serialized)
struct NotificationCoordinatorStartTests {

    private struct Rig {
        let coordinator: NotificationCoordinator
        let scheduler: CountingScheduler
        let center: RecordingCenter
        let registrar: RecordingTaskRegistrar
    }

    private func makeRig() throws -> Rig {
        let scheduler = CountingScheduler()
        let center = RecordingCenter()
        let registrar = RecordingTaskRegistrar()
        let day = try #require(startFixtureDay)
        let coordinator = NotificationCoordinator(
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
            client: LiveNotificationClient(center: center),
            taskRegistrar: registrar,
            now: { startFixtureInstant },
            today: { day },
            timeZone: { TimeZone(identifier: "America/Toronto") ?? .current }
        )
        return Rig(coordinator: coordinator, scheduler: scheduler, center: center, registrar: registrar)
    }

    private func makeStartedRig() throws -> Rig {
        let rig = try makeRig()
        rig.coordinator.start()
        return rig
    }

    private func settle(until condition: () -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if condition() { return true }
            await Task.yield()
        }
        return false
    }

    // MARK: - start()

    @Test("⛔ start() registers the three §6.4 action categories")
    func startRegistersTheCategories() throws {
        let rig = try makeStartedRig()
        #expect(Set(rig.center.categories.map(\.identifier)) == [
            NotificationCategory.actionable,
            NotificationCategory.verification,
            NotificationCategory.usage
        ])
    }

    @Test("⛔ start() installs the coordinator itself as the notification delegate")
    func startInstallsTheDelegate() throws {
        let rig = try makeStartedRig()
        #expect(rig.center.installCount == 1)
        #expect(rig.center.installedDelegate === rig.coordinator)
    }

    @Test("⛔ start() registers the refresh task under the permitted identifier, on the main queue")
    func startRegistersTheRefreshTask() throws {
        let rig = try makeStartedRig()
        #expect(rig.registrar.registrations.count == 1)
        let registration = try #require(rig.registrar.registrations.first)
        // The literal, not `NotificationCoordinator.refreshTaskIdentifier`:
        // what has to match is Info.plist's BGTaskSchedulerPermittedIdentifiers
        // entry, so corrupting the constant must die here too.
        #expect(registration.identifier == "com.arthurzhang.otto.refresh")
        // `using: .main`, NOT nil - nil is a background queue, and the launch
        // handler calls main-actor state (the Gate 1/2 crash the start()
        // comment records).
        #expect(registration.queue === DispatchQueue.main)
    }

    @Test("⛔ a system timezone change runs a pass")
    func timezoneChangeRunsAPass() async throws {
        let rig = try makeStartedRig()
        // start() itself schedules nothing; the pass below is the observer's.
        #expect(rig.scheduler.passes == 0)
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        #expect(await settle { rig.scheduler.passes == 1 })
    }

    @Test("⛔ a significant time change runs a pass")
    func significantTimeChangeRunsAPass() async throws {
        let rig = try makeStartedRig()
        #expect(rig.scheduler.passes == 0)
        NotificationCenter.default.post(
            name: UIApplication.significantTimeChangeNotification, object: nil
        )
        #expect(await settle { rig.scheduler.passes == 1 })
    }

    // MARK: - The delegate bodies

    @Test("⛔ willPresent's body reschedules and keeps the banner")
    func willPresentBodyReschedulesAndPresents() async throws {
        let rig = try makeRig()
        let options = rig.coordinator.notificationWillPresent()
        #expect(options == [.banner, .sound, .list])
        #expect(await settle { rig.scheduler.passes == 1 })
    }

    @Test("⛔ a plain tap maps the default action identifier to \"\", opens the detail, and reschedules")
    func defaultActionIdentifierMapsToPlainTap() async throws {
        let rig = try makeRig()
        let subscriptionID = UUID()
        var followUps: [NotificationActionFollowUp] = []
        rig.coordinator.onFollowUp = { followUps.append($0) }

        await rig.coordinator.notificationResponseReceived(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            notificationIdentifier: "\(subscriptionID.uuidString)|2026-09-03|renewal"
        )

        // "" is the handler's spelling for a plain tap, which routes to the
        // subscription's detail without touching any repository.
        #expect(followUps == [.openDetail(subscriptionID: subscriptionID)])
        #expect(await settle { rig.scheduler.passes == 1 })
    }

    @Test("⛔ a real action identifier reaches the handler unmapped")
    func realActionIdentifierIsNotMappedAway() async throws {
        let rig = try makeRig()
        var followUps: [NotificationActionFollowUp] = []
        rig.coordinator.onFollowUp = { followUps.append($0) }

        // "I'm cancelling" over an empty repository: the flow refuses
        // (noSubscription), the follow-up is `.none`, and `.none` must not be
        // published. Under an INVERTED default-action mapping this identifier
        // becomes "" and routes as a plain tap, whose `.openDetail` publish
        // fails the first assertion - the mutant M3's grave.
        await rig.coordinator.notificationResponseReceived(
            actionIdentifier: NotificationAction.cancelling.rawValue,
            notificationIdentifier: "\(UUID().uuidString)|2026-09-03|renewal"
        )

        #expect(followUps.isEmpty)
        #expect(await settle { rig.scheduler.passes == 1 })
    }
}
#endif
