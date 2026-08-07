import Foundation
import OttoDomain

/// The notification permission states the app distinguishes (Wave 4 constraint 3):
/// not-yet-asked, denied, and provisional are real, distinct situations with
/// distinct UI - an app whose entire value is notifications must never fail
/// silently when it cannot send them.
public enum NotificationPermission: String, Sendable, Hashable, Codable, CaseIterable {
    /// The system prompt has never been shown; asking is still possible.
    case notDetermined
    /// The user said no. Only the Settings app can change this, and Today must
    /// say so, at the top, permanently.
    case denied
    /// Full authorization.
    case authorized
    /// Quiet, notification-center-only delivery - real but degraded, since
    /// time-sensitive interruptions will not break through.
    case provisional
}

/// One notification request as the scheduler describes it - a value, so tests can
/// compare pending sets byte for byte and the live client is a thin translation.
public struct NotificationRequestSpec: Hashable, Sendable {
    /// Deterministic (spec §6.2): `NotificationPlanIdentifier` shapes.
    public let identifier: String
    public let title: String
    public let body: String
    /// The local wall-clock fire time: year, month, day, hour, minute. Calendar
    /// triggers take components rather than instants so the pending request is
    /// legible and the timezone conversion happened in exactly one place.
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    /// Delivered with the time-sensitive interruption level (spec §6.3).
    public let isTimeSensitive: Bool
    /// The `UNNotificationCategory` identifier carrying the action buttons, or
    /// empty for a plain notification.
    public let categoryIdentifier: String

    public init(
        identifier: String,
        title: String,
        body: String,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        isTimeSensitive: Bool,
        categoryIdentifier: String
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.isTimeSensitive = isTimeSensitive
        self.categoryIdentifier = categoryIdentifier
    }
}

/// The seam between the scheduler and `UNUserNotificationCenter`. The live
/// implementation translates specs into system requests; tests substitute an
/// in-memory fake, which is what lets the entire engine run under `swift test`
/// with no simulator.
public protocol NotificationClient: Sendable {
    func permission() async -> NotificationPermission

    /// Shows the system prompt. Returns the resulting permission - callers
    /// reschedule when it lands on `.authorized` (spec §6.2's "permission newly
    /// granted" trigger).
    func requestAuthorization() async -> NotificationPermission

    /// Every pending request, as specs, in insertion order.
    func pendingRequests() async -> [NotificationRequestSpec]

    /// Adds one request. An existing pending request with the same identifier is
    /// replaced - `UNUserNotificationCenter` semantics, which is what makes
    /// deterministic identifiers idempotent.
    func add(_ spec: NotificationRequestSpec) async throws

    func removePendingRequests(withIdentifiers identifiers: [String]) async
}
