import Foundation
import OttoDomain

/// What a scheduling pass produced - the facts Today needs to state honestly:
/// whether anything can be delivered at all, and through which day coverage
/// actually extends (spec §6.1 point 4).
public struct ScheduleOutcome: Hashable, Sendable {
    public let permission: NotificationPermission
    /// Planned requests now pending (snoozes not included).
    public let scheduledCount: Int
    /// The last day with complete coverage when the budget truncated the plan,
    /// nil when nothing was dropped.
    public let truncatedAfter: CalendarDay?
    /// The day through which the UI may claim coverage: the truncation point if
    /// one exists, the horizon end otherwise. Never let the user believe coverage
    /// extends further than it does.
    public let coveredThrough: CalendarDay
    /// Subscriptions whose ledger reconciliation failed this pass - scheduling
    /// continued without them rather than aborting, but the failure is not
    /// swallowed.
    public let ledgerFailures: [UUID]
    /// The subset of `ledgerFailures` skipped because a stored day is
    /// detected-implausible (R0-7 / N2-2): Otto silenced these ON PURPOSE and
    /// they stay silent until the user repairs the dates, which is a different
    /// fact from a transient failure that the next pass may clear. The gap
    /// card's copy branches on it (round 5, item 9 / N3-5) - describing a
    /// deliberate silencing as "it will try again" told the user to wait for
    /// a repair only they can make. Identifiers rather than a count, matching
    /// `ledgerFailures`: the card renders a count, but the subset relationship
    /// is only checkable on identifiers.
    public let implausibleDayFailures: [UUID]

    /// Whether `coveredThrough` may be STATED to the user.
    ///
    /// A pass that reconciled the ledger for only some subscriptions still
    /// returns normally, with `coveredThrough` at the full horizon - it
    /// describes the plan, not the subscriptions that fell out of it. A
    /// subscription whose materialization threw has no rows and no reminders
    /// this pass, so a screen that reads `coveredThrough` alone tells the user
    /// their reminders are scheduled for the next ninety days when some of them
    /// are not scheduled at all.
    public var canClaimCoverage: Bool { ledgerFailures.isEmpty }

    public init(
        permission: NotificationPermission,
        scheduledCount: Int,
        truncatedAfter: CalendarDay?,
        coveredThrough: CalendarDay,
        ledgerFailures: [UUID] = [],
        implausibleDayFailures: [UUID] = []
    ) {
        self.permission = permission
        self.scheduledCount = scheduledCount
        self.truncatedAfter = truncatedAfter
        self.coveredThrough = coveredThrough
        self.ledgerFailures = ledgerFailures
        self.implausibleDayFailures = implausibleDayFailures
    }
}

/// The store layer talks to the scheduler through this seam so store tests can
/// substitute a spy.
public protocol ReminderScheduling: Sendable {
    @discardableResult
    func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome
}
