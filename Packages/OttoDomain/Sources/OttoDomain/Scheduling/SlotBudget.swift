import Foundation

/// Fits a reminder plan into iOS's 64-pending-local-notification budget (spec §6.1).
///
/// iOS silently drops pending notifications beyond the limit, furthest-out first -
/// which is exactly the annual renewals most worth warning about. So the cut is made
/// here, explicitly and deterministically, instead of letting the OS make it silently:
/// priority first (a trial deadline in November outranks a renewal tomorrow), nearest
/// date first within a priority, then stable identifiers so the same plan always
/// budgets the same way.
///
/// - Returns: the reminders to schedule, in date order, plus `truncatedAfter`: the
///   last day with complete coverage, so the UI can say "reminders scheduled through
///   12 Nov" and mean it (spec §6.1 point 4). It is nil when nothing was dropped;
///   otherwise it is the day before the earliest dropped reminder - the last day
///   through which the plan is still fully scheduled.
public func budgeted(
    _ reminders: [PlannedReminder],
    limit: Int
) -> (scheduled: [PlannedReminder], truncatedAfter: CalendarDay?) {
    let slotCount = max(0, limit)

    let ranked = reminders.sorted { lhs, rhs in
        (lhs.priority.rawValue, lhs.day, lhs.kind.rawValue, lhs.subscriptionID.uuidString)
            < (rhs.priority.rawValue, rhs.day, rhs.kind.rawValue, rhs.subscriptionID.uuidString)
    }
    let kept = ranked.prefix(slotCount)
    let dropped = ranked.dropFirst(slotCount)

    let scheduled = kept.sorted { lhs, rhs in
        (lhs.day, lhs.priority.rawValue, lhs.kind.rawValue, lhs.subscriptionID.uuidString)
            < (rhs.day, rhs.priority.rawValue, rhs.kind.rawValue, rhs.subscriptionID.uuidString)
    }
    let truncatedAfter = dropped.map(\.day).min().map { $0.adding(days: -1) }
    return (scheduled, truncatedAfter)
}
