import Foundation

/// One reminder the scheduler intends to deliver (spec §6.1) - a plan entry, not a
/// scheduled notification. Wave 4 turns these into notification requests; the domain
/// only ever plans.
public struct PlannedReminder: Hashable, Codable, Sendable {

    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// An ordinary renewal warning, `reminderLeadDays` ahead of a billing date.
        case renewal
        /// The lead-time warning ahead of a trial's cancel-by day.
        case trialLead
        /// Morning of the cancel-by day itself - time-sensitive at delivery.
        case trialDayOfMorning
        /// Evening of the cancel-by day - the last call.
        case trialDayOfEvening
        /// Post-cancellation check: a charge would have landed today; did it stop?
        case verification
        /// The 90-day "are you still using this?" check-in (spec §7.3).
        case usageCheckIn
        /// A paused subscription is about to resume billing (spec §5.1). Added beyond
        /// the spec §6 kind list because the resume reminder is required and no other
        /// kind describes it honestly.
        case pauseEnding
    }

    /// Budget priority for the 64-slot notification limit (spec §6.1). Lower rank
    /// always wins a slot.
    public enum Priority: Int, Codable, Hashable, Sendable, CaseIterable, Comparable {
        /// P1 - trial deadlines: unrecoverable money, and there are few of them.
        case trial = 1
        /// P2 - cancellation-verification checks.
        case verification = 2
        /// P3 - renewal reminders and pause-ending warnings, nearest first.
        case renewal = 3
        /// P4 - usage check-ins.
        case usageCheckIn = 4

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let subscriptionID: UUID

    /// The calendar day the reminder should fire. The wall-clock fire time is applied
    /// at scheduling time (Wave 4) via `CalendarDay.fireDate(hour:minute:in:)` - which
    /// is also how morning and evening trial reminders sharing a day differ.
    public let day: CalendarDay

    public let kind: Kind

    /// Derived from `kind` so the two can never disagree.
    public var priority: Priority {
        switch kind {
        case .trialLead, .trialDayOfMorning, .trialDayOfEvening: .trial
        case .verification: .verification
        case .renewal, .pauseEnding: .renewal
        case .usageCheckIn: .usageCheckIn
        }
    }

    public init(subscriptionID: UUID, day: CalendarDay, kind: Kind) {
        self.subscriptionID = subscriptionID
        self.day = day
        self.kind = kind
    }
}
