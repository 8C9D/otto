import Foundation
import OttoDomain
import UserNotifications

/// The seam over `UNUserNotificationCenter` (Wave 10): exactly the calls the
/// live client makes, so the translation layer - trigger construction, the
/// component fields, categories, interruption levels, and `add`'s error path -
/// is testable host-side against a fake that records the REAL
/// `UNNotificationRequest` objects. The seam sits at the system boundary, not
/// above `LiveNotificationClient`, because a mock of the client would mock
/// away the thing under test: every engine test runs against a fake whose
/// `add` never throws, and both device defects this wave fixes lived in the
/// untested translation underneath it.
///
/// `UNNotificationSettings` and `UNNotification` have no public initializers,
/// so the two calls that would return them are narrowed to the values the
/// client actually reads - a fake cannot construct the framework types, and a
/// seam a fake cannot implement tests nothing.
public protocol UserNotificationCentering: Sendable {
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

// UNUserNotificationCenter is documented thread-safe, and the request/category
// types are immutable once handed over (the mutable content subclass is copied
// on add) - the annotations state what the framework already guarantees but
// predates Sendable checking.
extension UNUserNotificationCenter: @retroactive @unchecked Sendable {}
extension UNNotificationRequest: @retroactive @unchecked Sendable {}
extension UNNotificationCategory: @retroactive @unchecked Sendable {}

extension UNUserNotificationCenter: UserNotificationCentering {
    public func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

/// The `UNUserNotificationCenter`-backed client - a pure translation layer. Every
/// decision was made upstream; this converts specs to system requests and back,
/// and registers the §6.4 action category once at startup.
public final class LiveNotificationClient: NotificationClient {

    private let center: any UserNotificationCentering

    /// The app target passes nothing and gets the real center; tests inject
    /// the recording fake, and `UNUserNotificationCenter.current()` - which
    /// requires an app bundle `swift test` does not have - is then never
    /// touched.
    public init(center: (any UserNotificationCentering)? = nil) {
        self.center = center ?? UNUserNotificationCenter.current()
    }

    /// Registers the action categories (spec §6.4; §5.4's verification answers
    /// since Wave 5). Called once at launch, before any notification can be
    /// interacted with.
    public func registerCategories() {
        let reminder = UNNotificationCategory(
            identifier: NotificationCategory.actionable,
            actions: [
                UNNotificationAction(
                    identifier: NotificationAction.keepingIt.rawValue,
                    title: String(localized: "Keeping it")
                ),
                UNNotificationAction(
                    identifier: NotificationAction.cancelling.rawValue,
                    title: String(localized: "I'm cancelling"),
                    // Foreground, because the follow-up opens the stored
                    // cancellation URL - the state work itself already happened
                    // in the background handler.
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: NotificationAction.remindLater.rawValue,
                    title: String(localized: "Remind me later")
                )
            ],
            intentIdentifiers: []
        )
        let verification = UNNotificationCategory(
            identifier: NotificationCategory.verification,
            actions: [
                UNNotificationAction(
                    identifier: NotificationAction.chargesStopped.rawValue,
                    title: String(localized: "Yes - it stopped")
                ),
                UNNotificationAction(
                    identifier: NotificationAction.stillCharging.rawValue,
                    title: String(localized: "No - still charging"),
                    // Foreground so the dispute summary is on screen the moment
                    // it exists; the state work happened in the background
                    // handler regardless.
                    options: [.foreground]
                )
            ],
            intentIdentifiers: []
        )
        let usage = UNNotificationCategory(
            identifier: NotificationCategory.usage,
            actions: [
                UNNotificationAction(
                    identifier: NotificationAction.stillUsing.rawValue,
                    title: String(localized: "Yes - still using it")
                ),
                UNNotificationAction(
                    identifier: NotificationAction.notUsing.rawValue,
                    title: String(localized: "Not really…"),
                    // Foreground: what to do about an unused subscription is
                    // the user's decision, so this opens the facts.
                    options: [.foreground]
                )
            ],
            intentIdentifiers: []
        )
        center.setNotificationCategories([reminder, verification, usage])
    }

    public func permission() async -> NotificationPermission {
        switch await center.authorizationStatus() {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .provisional: .provisional
        case .authorized, .ephemeral: .authorized
        @unknown default: .denied
        }
    }

    public func requestAuthorization() async -> NotificationPermission {
        // A denied or error outcome reads back the actual status rather than
        // guessing - the system dialog result and the settings can disagree
        // transiently, and the settings are the truth.
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        return await permission()
    }

    public func pendingRequests() async -> [NotificationRequestSpec] {
        await center.pendingNotificationRequests().compactMap { request in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let year = trigger.dateComponents.year,
                  let month = trigger.dateComponents.month,
                  let day = trigger.dateComponents.day,
                  let hour = trigger.dateComponents.hour,
                  let minute = trigger.dateComponents.minute
            else { return nil }
            return NotificationRequestSpec(
                identifier: request.identifier,
                title: request.content.title,
                body: request.content.body,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                isTimeSensitive: request.content.interruptionLevel == .timeSensitive,
                categoryIdentifier: request.content.categoryIdentifier
            )
        }
    }

    public func add(_ spec: NotificationRequestSpec) async throws {
        let content = UNMutableNotificationContent()
        content.title = spec.title
        content.body = spec.body
        content.sound = .default
        content.categoryIdentifier = spec.categoryIdentifier
        if spec.isTimeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        // Wall-clock components with NO timezone, deliberately (spec §4.1): the
        // day and hour are the user's local ones, and a timezone change fires a
        // full reschedule anyway - so the pending request stays legible and the
        // one instant conversion happened upstream, in exactly one place.
        var components = DateComponents()
        components.year = spec.year
        components.month = spec.month
        components.day = spec.day
        components.hour = spec.hour
        components.minute = spec.minute
        let request = UNNotificationRequest(
            identifier: spec.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try await center.add(request)
    }

    public func removePendingRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
