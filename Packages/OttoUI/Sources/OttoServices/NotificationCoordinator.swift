#if os(iOS)
import BackgroundTasks
import Foundation
import OttoDomain
import UIKit
import UserNotifications

/// The app-side wiring for spec §6.2's reschedule triggers. The app target
/// creates one of these at launch and keeps it alive; everything else - what to
/// schedule, when it fires, what the actions do - lives below in the scheduler,
/// the handler, and ultimately the domain.
///
/// Triggers wired here: app foreground, notification delivered in the foreground,
/// notification acted on, `BGAppRefreshTask`, timezone change, and significant
/// time change. Create/edit/delete and permission-grant triggers run through the
/// store layer, which owns those state changes.
@MainActor
public final class NotificationCoordinator: NSObject {

    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    public static let refreshTaskIdentifier = "com.arthurzhang.otto.refresh"

    private let scheduler: any ReminderScheduling
    private let handler: NotificationActionHandler
    private let client: LiveNotificationClient
    private let now: @Sendable () -> Date
    private let today: @Sendable () -> CalendarDay
    private let timeZone: @Sendable () -> TimeZone
    private var observers: [any NSObjectProtocol] = []

    /// Where the app routes a follow-up (open a detail screen, open the
    /// cancellation URL). Set by the composition root.
    public var onFollowUp: ((NotificationActionFollowUp) -> Void)?
    /// Latest outcome, published so the store layer can surface permission and
    /// coverage without re-running a pass.
    public var onOutcome: ((ScheduleOutcome) -> Void)?

    public init(
        scheduler: any ReminderScheduling,
        handler: NotificationActionHandler,
        client: LiveNotificationClient,
        now: @escaping @Sendable () -> Date,
        today: @escaping @Sendable () -> CalendarDay,
        timeZone: @escaping @Sendable () -> TimeZone
    ) {
        self.scheduler = scheduler
        self.handler = handler
        self.client = client
        self.now = now
        self.today = today
        self.timeZone = timeZone
        super.init()
    }

    /// Called exactly once, from the app's init - BGTaskScheduler requires its
    /// registrations to happen before the app finishes launching.
    public func start() {
        client.registerCategories()
        UNUserNotificationCenter.current().delegate = self

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil
        ) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundRefresh(refreshTask)
        }

        let timezoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            // A timezone change moves fire INSTANTS, never calendar days
            // (spec §4.1) - the full reschedule recomputes every instant in the
            // new zone.
            MainActor.assumeIsolated { self?.rescheduleSoon() }
        }
        let timeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescheduleSoon() }
        }
        // The coordinator lives for the app's entire lifetime (the composition
        // root retains it), so the tokens are held but never need removing.
        observers = [timezoneObserver, timeObserver]
    }

    /// The foreground trigger - the scene phase change calls this.
    public func appDidBecomeActive() {
        rescheduleSoon()
        scheduleNextBackgroundRefresh()
    }

    private func rescheduleSoon() {
        Task { [scheduler, now, today, timeZone, onOutcome] in
            if let outcome = try? await scheduler.reschedule(
                now: now(), today: today(), timeZone: timeZone()
            ) {
                onOutcome?(outcome)
            }
        }
    }

    // MARK: - Background refresh

    /// Asks for a daily wake-up. The OS treats this as a request, not a promise;
    /// the foreground trigger remains the reliable path, and everything
    /// deadline-critical is pre-scheduled anyway (spec §6.3's reasoning).
    public func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
        // Failure here is expected in the simulator and when Background App
        // Refresh is off; the app must not depend on it, so it is logged by the
        // system and deliberately not surfaced.
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleNextBackgroundRefresh()
        let work = Task { [scheduler, now, today, timeZone] in
            let outcome = try? await scheduler.reschedule(
                now: now(), today: today(), timeZone: timeZone()
            )
            task.setTaskCompleted(success: outcome != nil)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationCoordinator: UNUserNotificationCenterDelegate {

    /// Foreground delivery: show the banner anyway - a reminder the user paid
    /// for by opening the app is still a reminder - and treat delivery as the
    /// §6.2 reschedule trigger it is. Nonisolated because the system calls the
    /// delegate off the main actor and its parameters are not Sendable; nothing
    /// from them is needed here.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { self.rescheduleSoon() }
        return [.banner, .sound, .list]
    }

    /// A tap or an action button. The Sendable facts (two strings) are extracted
    /// before any hop; the handler does the state work on its own actor, and the
    /// follow-up plus the reschedule land back on the main actor.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            ? "" : response.actionIdentifier
        let notificationIdentifier = response.notification.request.identifier
        let followUp = try? await handler.handle(
            actionIdentifier: actionIdentifier,
            notificationIdentifier: notificationIdentifier,
            now: now(),
            today: today(),
            timeZone: timeZone()
        )
        await MainActor.run {
            if let followUp, followUp != .none {
                self.onFollowUp?(followUp)
            }
            self.rescheduleSoon()
        }
    }
}
#endif
