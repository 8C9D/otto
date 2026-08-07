import Foundation
import Testing
import OttoDomain
@testable import OttoStores

@MainActor
@Suite("SettingsStore: defaults for new entries, live notification time")
struct SettingsStoreTests {

    /// A clean, isolated defaults suite per test.
    private func makeDefaults() throws -> UserDefaults {
        let name = "otto.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("a fresh store carries the spec §10 defaults")
    func freshDefaults() throws {
        let store = SettingsStore(userDefaults: try makeDefaults())
        #expect(store.reminderDefaults == .standard)
        #expect(store.notificationHour == FireTimePolicy.standard.preferredHour)
        #expect(store.notificationMinute == FireTimePolicy.standard.preferredMinute)
    }

    @Test("changes persist and reload")
    func persistence() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.renewalLeadDays = 7
        store.trialLeadDays = 10
        store.trialBufferDays = 4
        store.notificationHour = 20
        store.notificationMinute = 30

        let reloaded = SettingsStore(userDefaults: defaults)
        #expect(reloaded.reminderDefaults == SettingsStore.ReminderDefaults(
            renewalLeadDays: 7, trialLeadDays: 10, trialBufferDays: 4
        ))
        #expect(reloaded.notificationHour == 20)
        #expect(reloaded.notificationMinute == 30)
    }

    @Test("the fire-time policy reads the stored time and keeps the evening slot")
    func fireTimePolicy() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(userDefaults: defaults)

        #expect(SettingsStore.fireTimePolicy(from: defaults) == .standard)

        store.notificationHour = 7
        store.notificationMinute = 45
        let policy = SettingsStore.fireTimePolicy(from: defaults)
        #expect(policy.preferredHour == 7)
        #expect(policy.preferredMinute == 45)
        #expect(policy.eveningHour == FireTimePolicy.standard.eveningHour)
    }

    @Test("a notification-time change fires the reschedule hook; a default change does not")
    func rescheduleHook() async throws {
        let store = SettingsStore(userDefaults: try makeDefaults())
        var reschedules = 0
        store.onReminderTimeChange = { reschedules += 1 }

        store.renewalLeadDays = 9
        store.trialBufferDays = 1
        await Task.yield()
        #expect(reschedules == 0)

        store.notificationHour = 8
        // The hook hops through a Task; give it a beat.
        for _ in 0 ..< 10 where reschedules == 0 { await Task.yield() }
        #expect(reschedules == 1)
    }
}

@MainActor
@Suite("Form defaults come from settings (Wave 8)")
struct FormDefaultsTests {

    @Test("a new form starts from the settings defaults, and the trial-toggle swap honours them")
    func newFormUsesSettingsDefaults() throws {
        let custom = SettingsStore.ReminderDefaults(
            renewalLeadDays: 7, trialLeadDays: 12, trialBufferDays: 4
        )
        let form = SubscriptionFormModel(dates: try fixedDates(), reminderDefaults: custom)

        #expect(form.reminderLeadDays == 7)
        #expect(form.trialBufferDays == 4)

        // The untouched default swaps with the toggle (spec §10), at the
        // configured values rather than the shipped constants.
        form.isTrial = true
        #expect(form.reminderLeadDays == 12)
        form.isTrial = false
        #expect(form.reminderLeadDays == 7)

        // A user-chosen value never swaps.
        form.reminderLeadDays = 2
        form.isTrial = true
        #expect(form.reminderLeadDays == 2)
    }
}
