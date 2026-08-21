import Foundation
import Observation
import OttoDomain

/// The user's settings (spec §7.1 item 9, Wave 8), persisted in `UserDefaults`:
/// the default reminder leads new entries start from, the default trial buffer,
/// and the wall-clock time reminders fire at.
///
/// Two different change semantics, deliberately:
/// - the DEFAULTS shape new entries only - existing subscriptions keep the
///   per-subscription values the user saved, so changing a default never
///   silently reshapes reminders already relied on;
/// - the NOTIFICATION TIME applies everywhere immediately (it is read live by
///   every scheduling pass), so changing it triggers a reschedule.
@MainActor
@Observable
public final class SettingsStore {

    /// The spec §10 defaults new entries start from.
    public struct ReminderDefaults: Hashable, Sendable {
        public var renewalLeadDays: Int
        public var trialLeadDays: Int
        public var trialBufferDays: Int

        public static let standard = ReminderDefaults(
            renewalLeadDays: 3, trialLeadDays: 5, trialBufferDays: 2
        )

        public init(renewalLeadDays: Int, trialLeadDays: Int, trialBufferDays: Int) {
            self.renewalLeadDays = renewalLeadDays
            self.trialLeadDays = trialLeadDays
            self.trialBufferDays = trialBufferDays
        }
    }

    /// Stable persistence keys - these are a schema; renaming one silently
    /// resets that setting.
    private enum Key {
        static let renewalLeadDays = "settings.defaultRenewalLeadDays"
        static let trialLeadDays = "settings.defaultTrialLeadDays"
        static let trialBufferDays = "settings.defaultTrialBufferDays"
        static let notificationHour = "settings.notificationHour"
        static let notificationMinute = "settings.notificationMinute"
    }

    public var renewalLeadDays: Int {
        didSet { userDefaults.set(renewalLeadDays, forKey: Key.renewalLeadDays) }
    }
    public var trialLeadDays: Int {
        didSet { userDefaults.set(trialLeadDays, forKey: Key.trialLeadDays) }
    }
    public var trialBufferDays: Int {
        didSet { userDefaults.set(trialBufferDays, forKey: Key.trialBufferDays) }
    }
    public var notificationHour: Int {
        didSet {
            userDefaults.set(notificationHour, forKey: Key.notificationHour)
            if notificationHour != oldValue { noteReminderTimeChanged() }
        }
    }
    public var notificationMinute: Int {
        didSet {
            userDefaults.set(notificationMinute, forKey: Key.notificationMinute)
            if notificationMinute != oldValue { noteReminderTimeChanged() }
        }
    }

    /// Fired after the notification time changes - the reschedule trigger
    /// (spec §6.2: a fire-time change re-times every pending reminder). The
    /// composition root points this at the notification status store.
    public var onReminderTimeChange: (@MainActor () async -> Void)?

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let standard = ReminderDefaults.standard
        renewalLeadDays = Self.int(Key.renewalLeadDays, in: userDefaults) ?? standard.renewalLeadDays
        trialLeadDays = Self.int(Key.trialLeadDays, in: userDefaults) ?? standard.trialLeadDays
        trialBufferDays = Self.int(Key.trialBufferDays, in: userDefaults) ?? standard.trialBufferDays
        notificationHour = Self.int(Key.notificationHour, in: userDefaults)
            ?? FireTimePolicy.standard.preferredHour
        notificationMinute = Self.int(Key.notificationMinute, in: userDefaults)
            ?? FireTimePolicy.standard.preferredMinute
    }

    /// The stored hour and minute as the `Date` a wheel picker needs, and the
    /// inverse. The one place settings touch a `Date`, and only for its clock
    /// face - no calendar day is involved and none is produced.
    ///
    /// The reference day resolves in `CalendarDay.conversionCalendar`, not
    /// `Calendar.current`. Both round-trip an hour and a minute correctly, since
    /// time of day is the same in every calendar for a given instant and zone -
    /// but `Calendar.current` reads `DateComponents(year: 2000, …)` as year 2000
    /// OF THE DEVICE'S ERA, which on a Buddhist device is 1457 CE and in a
    /// Japanese era is a year that does not exist. Nothing downstream depends on
    /// which instant it is, so this changes no behaviour; what it removes is the
    /// last `Calendar.current` in the packages, which is what lets the lint rule
    /// guarding F1's reading sites be global instead of carrying an exemption.
    ///
    /// Lives here rather than in the view because the view's binding is inside a
    /// `private struct` no test can reach, and F1's whole lesson is that an
    /// unreachable conversion is an unguarded one.
    public var notificationTimeOfDay: Date {
        CalendarDay.conversionCalendar.date(
            from: DateComponents(
                year: 2000, month: 1, day: 1, hour: notificationHour, minute: notificationMinute
            )
        ) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    /// Stores the hour and minute of a picked instant, ignoring its date.
    ///
    /// One picked time notifies AT MOST ONCE, however many components moved.
    /// Gate 3 (2026-08-16) watched a 9:00→9:05 pick run the full scheduling
    /// pass twice: `didSet` fires on a same-value assignment too, so the hour
    /// write notified alongside the minute's. The two writes here run with the
    /// per-property notification suppressed and the change judged over the
    /// pair, so an unchanged re-pick notifies nobody.
    public func setNotificationTime(from picked: Date) {
        let parts = CalendarDay.conversionCalendar.dateComponents([.hour, .minute], from: picked)
        let hour = parts.hour ?? FireTimePolicy.standard.preferredHour
        let minute = parts.minute ?? FireTimePolicy.standard.preferredMinute
        let changed = hour != notificationHour || minute != notificationMinute
        suppressReminderTimeNotification = true
        notificationHour = hour
        notificationMinute = minute
        suppressReminderTimeNotification = false
        if changed { noteReminderTimeChanged() }
    }

    /// The defaults the Add form starts new entries from.
    public var reminderDefaults: ReminderDefaults {
        ReminderDefaults(
            renewalLeadDays: renewalLeadDays,
            trialLeadDays: trialLeadDays,
            trialBufferDays: trialBufferDays
        )
    }

    /// The fire-time policy the schedulers read LIVE on every pass - a static
    /// over `UserDefaults` rather than an instance property, so background
    /// passes (BGAppRefreshTask has no view tree) see the same values the UI
    /// wrote. The evening last-call keeps its standard slot; the setting moves
    /// the main reminder hour (spec §10: default 09:00).
    public nonisolated static func fireTimePolicy(from userDefaults: UserDefaults = .standard) -> FireTimePolicy {
        var policy = FireTimePolicy.standard
        policy.preferredHour = int(Key.notificationHour, in: userDefaults) ?? policy.preferredHour
        policy.preferredMinute = int(Key.notificationMinute, in: userDefaults) ?? policy.preferredMinute
        return policy
    }

    /// True only inside `setNotificationTime`, which owns the notification for
    /// the pair of writes it makes.
    @ObservationIgnored private var suppressReminderTimeNotification = false

    private func noteReminderTimeChanged() {
        guard !suppressReminderTimeNotification, let onReminderTimeChange else { return }
        Task { await onReminderTimeChange() }
    }

    private nonisolated static func int(_ key: String, in userDefaults: UserDefaults) -> Int? {
        userDefaults.object(forKey: key) as? Int
    }
}
