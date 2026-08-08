import Foundation

// The remaining decisions Wave 4's scheduler needs, kept in the domain so the
// service layer translates a plan without ever computing one: when in the day a
// reminder fires, what identifies it, and how far a snooze may move.

/// The wall-clock times reminders fire at. A value type the UI can eventually bind
/// settings to (spec §7.1 item 9); the domain only ever receives it as a parameter.
public struct FireTimePolicy: Hashable, Codable, Sendable {
    /// The user's preferred notification hour (spec §10: default 09:00 local).
    public var preferredHour: Int
    public var preferredMinute: Int

    /// When the evening last-call fires on a trial's cancel-by day. 19:00 by
    /// default: late enough to be a distinct second nudge, early enough that
    /// cancelling that night is still realistic.
    public var eveningHour: Int
    public var eveningMinute: Int

    public static let standard = FireTimePolicy(
        preferredHour: 9, preferredMinute: 0, eveningHour: 19, eveningMinute: 0
    )

    public init(preferredHour: Int, preferredMinute: Int, eveningHour: Int, eveningMinute: Int) {
        self.preferredHour = preferredHour
        self.preferredMinute = preferredMinute
        self.eveningHour = eveningHour
        self.eveningMinute = eveningMinute
    }

    /// The time of day a reminder kind fires: the evening last-call at the evening
    /// time, everything else at the preferred hour.
    public func fireTime(for kind: PlannedReminder.Kind) -> (hour: Int, minute: Int) {
        kind == .trialDayOfEvening
            ? (eveningHour, eveningMinute)
            : (preferredHour, preferredMinute)
    }

    /// The instant a planned reminder fires in `timeZone` - the one place a
    /// `CalendarDay` becomes a `Date` (spec §4.1). A timezone change recomputes
    /// this; the day itself never moves.
    public func fireDate(for reminder: PlannedReminder, in timeZone: TimeZone) -> Date? {
        let time = fireTime(for: reminder.kind)
        return reminder.day.fireDate(hour: time.hour, minute: time.minute, in: timeZone)
    }
}

/// Deterministic notification identifiers (spec §6.2): "<subscriptionID>|<ISO date>|<kind>",
/// so a double-run schedules byte-identical requests and a cancel can name exactly
/// what it targets. Snoozes get their own namespace: they are user-created state
/// living only in the notification center, and a full reschedule must be able to
/// replace every planned request WITHOUT wiping the user's snoozes.
public enum NotificationPlanIdentifier {
    static let snoozePrefix = "snooze."

    public static func planned(_ reminder: PlannedReminder) -> String {
        "\(reminder.subscriptionID.uuidString)|\(reminder.day)|\(reminder.kind.rawValue)"
    }

    /// A snooze carries the kind it snoozed - "<id>|<day>|snooze.<kind>" - so
    /// snoozing a snooze still knows which deadline caps it.
    public static func snooze(subscriptionID: UUID, day: CalendarDay, of kind: PlannedReminder.Kind) -> String {
        "\(subscriptionID.uuidString)|\(day)|\(snoozePrefix)\(kind.rawValue)"
    }

    public static func isSnooze(_ identifier: String) -> Bool {
        kindComponent(of: identifier)?.hasPrefix(snoozePrefix) ?? false
    }

    /// The reminder kind an identifier carries - directly for a planned request,
    /// through the snooze prefix for a snoozed one. Nil for an identifier this
    /// scheme never produced.
    public static func kind(of identifier: String) -> PlannedReminder.Kind? {
        guard var raw = kindComponent(of: identifier) else { return nil }
        if raw.hasPrefix(snoozePrefix) { raw = String(raw.dropFirst(snoozePrefix.count)) }
        return PlannedReminder.Kind(rawValue: raw)
    }

    /// The subscription a notification identifier belongs to, or nil for an
    /// identifier this scheme never produced.
    public static func subscriptionID(of identifier: String) -> UUID? {
        guard let first = identifier.split(separator: "|").first else { return nil }
        return UUID(uuidString: String(first))
    }

    /// The calendar day an identifier carries, or nil for an identifier this
    /// scheme never produced. A §6.2 catch-up request's interval trigger has
    /// no date components, so its day is read back from here (Wave 10).
    public static func day(of identifier: String) -> CalendarDay? {
        let parts = identifier.split(separator: "|")
        guard parts.count == 3 else { return nil }
        let fields = parts[1].split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3 else { return nil }
        return CalendarDay(year: fields[0], month: fields[1], day: fields[2])
    }

    private static func kindComponent(of identifier: String) -> String? {
        let parts = identifier.split(separator: "|")
        guard parts.count == 3 else { return nil }
        return String(parts[2])
    }
}

/// Where "remind me later" lands (spec §6.4): the next day, hard-capped so it can
/// never move past the deadline - for a trial, the cancel-by date. A snooze that
/// skips the deadline is a bug that costs money, so the cap holds under repeated
/// invocation: snoozing from the deadline stays on the deadline.
public func snoozedReminderDay(from day: CalendarDay, deadline: CalendarDay?) -> CalendarDay {
    let next = day.adding(days: 1)
    guard let deadline else { return next }
    return min(next, deadline)
}
