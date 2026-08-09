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

        // `using: .main`, NOT nil. The SDK is explicit that nil means "a
        // default BACKGROUND queue", and this launch handler is formed inside
        // a `@MainActor` type and calls main-actor state - so Swift 6 emits a
        // runtime isolation check that traps the instant the system runs it
        // off-main. Observed on device (Gate 1/2, Aug 2026): every simulated
        // launch died in `_dispatch_assert_queue_fail` on the
        // `com.apple.BGTaskScheduler` queue, BEFORE the first line of the
        // handler body, so the task never reached `setTaskCompleted` on any
        // path. The handler only starts the work here; the async pass runs in
        // its own Task, so the main queue is not held.
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier, using: .main
        ) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                OttoLog.background.error("launch rejected: coordinator gone or wrong task class")
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundRefresh(refreshTask)
        }
        // Registration and execution are different claims (spec §6.3). This
        // records only the first; the handler below records the second.
        OttoLog.background.notice("""
            registered id=\(Self.refreshTaskIdentifier, privacy: .public) \
            accepted=\(registered, privacy: .public)
            """)

        let timezoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            // A timezone change moves fire INSTANTS, never calendar days
            // (spec §4.1) - the full reschedule recomputes every instant in the
            // new zone.
            MainActor.assumeIsolated { self?.rescheduleSoon(.timeZoneChange) }
        }
        let timeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescheduleSoon(.significantTimeChange) }
        }
        // The coordinator lives for the app's entire lifetime (the composition
        // root retains it), so the tokens are held but never need removing.
        observers = [timezoneObserver, timeObserver]
    }

    /// The foreground trigger - the scene phase change calls this.
    public func appDidBecomeActive() {
        rescheduleSoon(.foreground)
        scheduleNextBackgroundRefresh()
    }

    private func rescheduleSoon(_ trigger: RescheduleTrigger) {
        Task { [scheduler, now, today, timeZone, onOutcome] in
            if let outcome = try? await scheduler.reschedule(
                now: now(), today: today(), timeZone: timeZone(), trigger: trigger
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
        // Refresh is off; the app must not depend on it, so it stays unsurfaced
        // in the UI - but it is no longer unsurfaced everywhere, because "the
        // next wake-up was never armed" is the first thing an investigation
        // into a missed reminder needs to rule out.
        do {
            try BGTaskScheduler.shared.submit(request)
            OttoLog.background.notice("re-armed earliestBegin=+24h")
        } catch {
            OttoLog.background.error("re-arm failed error=\(String(describing: error), privacy: .public)")
        }
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        // This line is the §6.3 claim the spec has been unable to make since
        // Wave 4: not that the task registered, but that its handler BODY ran.
        OttoLog.background.notice("launched id=\(Self.refreshTaskIdentifier, privacy: .public)")
        // Before the work, so a pass that is cancelled or killed has already
        // asked for the next wake-up rather than depending on reaching its own
        // end to do so.
        scheduleNextBackgroundRefresh()
        let completion = CompletionLatch()
        let work = Task { [scheduler, now, today, timeZone] in
            let outcome = try? await scheduler.reschedule(
                now: now(), today: today(), timeZone: timeZone(), trigger: .backgroundRefresh
            )
            guard completion.claim() else {
                // Expiration already ended the task. Say so rather than going
                // quiet: this line means the pass outlived its expiration, and
                // if it ever appears far behind the expiration timestamp, the
                // checkpoints are too sparse for the work between them.
                OttoLog.background.notice("pass returned after expiration had already completed the task")
                return
            }
            OttoLog.background.notice("""
                completing path=normal success=\(outcome != nil, privacy: .public) \
                scheduled=\(outcome?.scheduledCount ?? -1, privacy: .public)
                """)
            task.setTaskCompleted(success: outcome != nil)
        }
        task.expirationHandler = {
            // Cancel FIRST, then claim: the pass must be told to stop before
            // the task is handed back, never after.
            work.cancel()
            guard completion.claim() else { return }
            OttoLog.background.notice("completing path=expiration success=false")
            task.setTaskCompleted(success: false)
        }
    }
}

/// Makes `setTaskCompleted` happen exactly once.
///
/// iOS treats a second `setTaskCompleted` as API misuse, and both paths can
/// reach it: expiration fires while the pass is in flight, then the pass
/// finishes and completes the task again. Observed on device (Gate 2, Aug
/// 2026) before this existed - `path=expiration` at 22:02:05.985 followed by
/// `path=normal` at 22:02:06.028, on a task the OS had already reclaimed.
///
/// A lock rather than main-actor confinement, because `BGTask` does not
/// document which queue it calls `expirationHandler` on, and correctness here
/// must not rest on an assumption the SDK never made - which is the same
/// assumption that produced the isolation crash this gate began with.
private final class CompletionLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// True for exactly one caller, ever.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
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
        await MainActor.run { self.rescheduleSoon(.notificationDelivered) }
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
            self.rescheduleSoon(.notificationAction)
        }
    }
}
#endif
