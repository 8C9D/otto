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
            noteReminderTimeChanged()
        }
    }
    public var notificationMinute: Int {
        didSet {
            userDefaults.set(notificationMinute, forKey: Key.notificationMinute)
            noteReminderTimeChanged()
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

    private func noteReminderTimeChanged() {
        guard let onReminderTimeChange else { return }
        Task { await onReminderTimeChange() }
    }

    private nonisolated static func int(_ key: String, in userDefaults: UserDefaults) -> Int? {
        userDefaults.object(forKey: key) as? Int
    }
}
