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
                now: dates.now(), today: dates.today(), timeZone: dates.timeZone(),
                trigger: .stateChange
            )
            apply(outcome)
        } catch {
            // The pass failed before it could produce an outcome. DROP the old
            // one: it describes a pass that is no longer the last word, and
            // Today renders "Reminders scheduled through <day>" straight from
            // it - so keeping it means the screen keeps asserting coverage
            // earned by an earlier pass while this one failed to renew it. No
            // claim beats a false one. The permission is still worth refreshing
            // so the UI never shows stale state.
            apply(nil)
            permission = await client.permission()
        }
    }

    /// Publishes an outcome produced elsewhere (the coordinator's background and
    /// lifecycle passes), so there is one source of truth for the UI.
    ///
    /// `nil` means a pass ran and failed, i.e. nothing is currently known about
    /// coverage. The permission is left alone in that case - a failed pass says
    /// nothing about whether notifications are allowed, and the caller refreshes
    /// it from the system where it matters.
    public func apply(_ outcome: ScheduleOutcome?) {
        self.outcome = outcome
        if let outcome {
            permission = outcome.permission
        }
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
