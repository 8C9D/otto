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

    /// F1's fifth conversion site, found by the lint rule item 3 added rather
    /// than by a test - it was the last `Calendar.current` left in the packages.
    ///
    /// Like `CalendarEraTests`, these are trivially true on a Gregorian host and
    /// only bite under the non-Gregorian harness that file documents. The
    /// difference is that the LINT RULE now fails on a Gregorian machine, which
    /// is every machine CI runs on.
    @Test("the notification-time picker round-trips an hour and a minute in any device calendar")
    func notificationTimeRoundTrips() throws {
        let store = SettingsStore(userDefaults: try makeDefaults())
        for (hour, minute) in [(0, 0), (9, 0), (13, 45), (21, 30), (23, 59)] {
            store.notificationHour = hour
            store.notificationMinute = minute
            let picked = store.notificationTimeOfDay
            store.notificationHour = 0
            store.notificationMinute = 0
            store.setNotificationTime(from: picked)
            #expect(store.notificationHour == hour)
            #expect(store.notificationMinute == minute)
        }
    }

    @Test("⛔ the picker's reference instant is the domain's era, not the device's")
    func notificationTimeReferenceInstantIsGregorian() throws {
        let store = SettingsStore(userDefaults: try makeDefaults())
        store.notificationHour = 9
        store.notificationMinute = 0

        // The instant itself, not just the hour and minute read back out of it.
        // On a Buddhist device `Calendar.current.date(from: year 2000)` is 1457
        // CE; the round trip above survives that, so only pinning the instant
        // catches a reversion.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .autoupdatingCurrent
        let expected = gregorian.date(
            from: DateComponents(year: 2000, month: 1, day: 1, hour: 9, minute: 0)
        )
        #expect(store.notificationTimeOfDay == expected)
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
