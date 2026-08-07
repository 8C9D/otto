import Foundation
import Observation
import OttoDomain
import OttoServices

/// The observable face of the notification engine: the permission state and the
/// honest coverage statement, published for Today to render (Wave 4 constraint 3 -
/// an app whose entire value is notifications must never fail silently when it
/// cannot send them).
@MainActor
@Observable
public final class NotificationStatusStore {

    public private(set) var permission: NotificationPermission = .notDetermined

    /// The latest scheduling outcome - `coveredThrough` is what "Reminders
    /// scheduled through 12 Nov" renders from. Nil until a pass has run.
    public private(set) var outcome: ScheduleOutcome?

    private let scheduler: any ReminderScheduling
    private let client: any NotificationClient
    private let dates: DateProvider

    public init(
        scheduler: any ReminderScheduling,
        client: any NotificationClient,
        dates: DateProvider = .live
    ) {
        self.scheduler = scheduler
        self.client = client
        self.dates = dates
    }

    /// Runs a full scheduling pass and publishes the result. The store layer's
    /// mutation paths call this, and the app's lifecycle triggers land here too.
    public func reschedule() async {
        do {
            let outcome = try await scheduler.reschedule(
                now: dates.now(), today: dates.today(), timeZone: dates.timeZone()
            )
            apply(outcome)
        } catch {
            // The pass failed before it could produce an outcome; the permission
            // is still worth refreshing so the UI never shows stale state.
            permission = await client.permission()
        }
    }

    /// Publishes an outcome produced elsewhere (the coordinator's background and
    /// lifecycle passes), so there is one source of truth for the UI.
    public func apply(_ outcome: ScheduleOutcome) {
        self.outcome = outcome
        permission = outcome.permission
    }

    /// Shows the system prompt; a grant is a reschedule trigger (spec §6.2).
    public func requestPermission() async {
        permission = await client.requestAuthorization()
        if permission == .authorized || permission == .provisional {
            await reschedule()
        }
    }

    /// Reads the current permission without scheduling - cheap enough for view
    /// appearance.
    public func refreshPermission() async {
        permission = await client.permission()
    }
}
