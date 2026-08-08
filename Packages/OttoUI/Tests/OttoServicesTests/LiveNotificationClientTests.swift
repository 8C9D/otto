import Foundation
import Testing
import UserNotifications
@testable import OttoServices

// Wave 10: `LiveNotificationClient` had zero test coverage, and both device
// defects this wave fixes lived in exactly that gap - every engine test ran
// against a fake whose `add` never throws. These tests run the REAL client
// against a fake center that records the actual `UNNotificationRequest`
// objects, so the translation - trigger type, each component field, the
// timezone decision, interruption levels, categories, and the error path -
// is observed rather than assumed.

/// Records real `UNNotificationRequest` objects - not a boolean, not a count -
/// with the same replace-by-identifier semantics as the system center, plus an
/// injectable `add` error.
final class FakeUserNotificationCenter: UserNotificationCentering, @unchecked Sendable {
    struct CenterRefused: Error {}

    private let lock = NSLock()
    private var _pending: [UNNotificationRequest] = []
    private var _categories: Set<UNNotificationCategory> = []
    private var _status: UNAuthorizationStatus = .authorized
    private var _requestedOptions: [UNAuthorizationOptions] = []
    private var _addRefused = false
    private var _delivered: [String] = []

    var pending: [UNNotificationRequest] { lock.withLock { _pending } }
    var categories: Set<UNNotificationCategory> { lock.withLock { _categories } }
    var requestedOptions: [UNAuthorizationOptions] { lock.withLock { _requestedOptions } }

    func setStatus(_ status: UNAuthorizationStatus) {
        lock.withLock { _status = status }
    }

    func refuseAdds() {
        lock.withLock { _addRefused = true }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        lock.withLock { _categories = categories }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        lock.withLock { _status }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        lock.withLock {
            _requestedOptions.append(options)
            return _status == .authorized || _status == .provisional
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        lock.withLock { _pending }
    }

    func seedDelivered(_ identifiers: [String]) {
        lock.withLock { _delivered = identifiers }
    }

    func deliveredNotificationIdentifiers() async -> [String] {
        lock.withLock { _delivered }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try lock.withLock {
            if _addRefused { throw CenterRefused() }
            _pending.removeAll { $0.identifier == request.identifier }
            _pending.append(request)
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        let doomed = Set(identifiers)
        lock.withLock { _pending.removeAll { doomed.contains($0.identifier) } }
    }
}

@Suite("LiveNotificationClient translation (Wave 10)")
struct LiveNotificationClientTests {

    private let center = FakeUserNotificationCenter()
    private var client: LiveNotificationClient { LiveNotificationClient(center: center) }

    private func spec(
        identifier: String = "test|2026-08-20|conversionAnnouncement",
        timeSensitive: Bool = true,
        category: String = NotificationCategory.actionable
    ) -> NotificationRequestSpec {
        NotificationRequestSpec(
            identifier: identifier,
            title: "Gate Test trial converted",
            body: "Your Gate Test trial converted today.",
            year: 2026, month: 8, day: 20, hour: 9, minute: 0,
            isTimeSensitive: timeSensitive,
            categoryIdentifier: category
        )
    }

    @Test("add builds a non-repeating calendar trigger with exactly the five wall-clock fields, no timezone")
    func addTranslatesCalendarTrigger() async throws {
        try await client.add(spec())

        let request = try #require(center.pending.first)
        #expect(request.identifier == "test|2026-08-20|conversionAnnouncement")
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        let components = trigger.dateComponents
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 20)
        #expect(components.hour == 9)
        #expect(components.minute == 0)
        #expect(components.second == nil)
        // No timezone, DELIBERATELY (spec §4.1): the components are the user's
        // wall clock, and a timezone change triggers a full reschedule. A
        // timezone here would pin the instant and fire mid-night after a
        // flight.
        #expect(components.timeZone == nil)
    }

    @Test("content carries title, body, sound, category, and the time-sensitive interruption level")
    func addTranslatesContent() async throws {
        try await client.add(spec(timeSensitive: true))
        let request = try #require(center.pending.first)
        #expect(request.content.title == "Gate Test trial converted")
        #expect(request.content.body == "Your Gate Test trial converted today.")
        #expect(request.content.sound == .default)
        #expect(request.content.categoryIdentifier == NotificationCategory.actionable)
        #expect(request.content.interruptionLevel == .timeSensitive)
    }

    @Test("a non-time-sensitive spec stays at the default interruption level")
    func plainInterruptionLevel() async throws {
        try await client.add(spec(identifier: "plain", timeSensitive: false, category: ""))
        let request = try #require(center.pending.first)
        #expect(request.content.interruptionLevel == .active)
        #expect(request.content.categoryIdentifier.isEmpty)
    }

    @Test("⛔ a throwing center.add PROPAGATES - the client must not swallow the one error that loses a rung")
    func addErrorPropagates() async throws {
        center.refuseAdds()
        await #expect(throws: FakeUserNotificationCenter.CenterRefused.self) {
            try await client.add(spec())
        }
        #expect(center.pending.isEmpty)
    }

    @Test("pendingRequests parses the calendar trigger back into the identical spec")
    func pendingRoundTrip() async throws {
        let original = spec()
        try await client.add(original)
        #expect(await client.pendingRequests() == [original])
    }

    @Test("a §6.2 catch-up spec becomes a non-repeating interval trigger, not a calendar one")
    func catchUpBecomesIntervalTrigger() async throws {
        let catchUp = NotificationRequestSpec(
            identifier: "00000000-0000-0000-0000-000000000001|2026-08-20|conversionAnnouncement",
            title: "t", body: "b",
            year: 2026, month: 8, day: 20, hour: 0, minute: 0,
            isTimeSensitive: true,
            categoryIdentifier: "",
            catchUpIntervalSeconds: 5
        )
        try await client.add(catchUp)

        let request = try #require(center.pending.first)
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 5)
        #expect(!trigger.repeats)
        // And it reads back as the identical spec - the day comes from the
        // deterministic identifier, since an interval trigger has no date.
        #expect(await client.pendingRequests() == [catchUp])
    }

    @Test("delivered identifiers pass through from the center's own delivery record")
    func deliveredPassThrough() async {
        center.seedDelivered(["a|2026-08-20|renewal"])
        #expect(await client.deliveredIdentifiers() == ["a|2026-08-20|renewal"])
    }

    @Test("a request with no trigger - a shape this scheme never produces - is skipped, not misread")
    func pendingSkipsForeignRequests() async throws {
        let content = UNMutableNotificationContent()
        content.title = "foreign"
        try await center.add(UNNotificationRequest(identifier: "foreign", content: content, trigger: nil))
        try await client.add(spec())
        #expect(await client.pendingRequests().map(\.identifier) == [spec().identifier])
    }

    @Test("removePendingRequests removes exactly the named identifiers")
    func removeByIdentifier() async throws {
        try await client.add(spec(identifier: "a"))
        try await client.add(spec(identifier: "b"))
        await client.removePendingRequests(withIdentifiers: ["a"])
        #expect(center.pending.map(\.identifier) == ["b"])
    }

    @Test("registerCategories registers §6.4's categories with the exact action identifiers and foreground flags")
    func categoriesAndActions() throws {
        client.registerCategories()

        let categories = Dictionary(
            uniqueKeysWithValues: center.categories.map { ($0.identifier, $0) }
        )
        #expect(categories.count == 3)

        let reminder = try #require(categories[NotificationCategory.actionable])
        #expect(reminder.actions.map(\.identifier) == [
            NotificationAction.keepingIt.rawValue,
            NotificationAction.cancelling.rawValue,
            NotificationAction.remindLater.rawValue
        ])
        // "I'm cancelling" opens the stored URL, which needs the foreground;
        // the other two must work from a locked screen.
        for action in reminder.actions {
            #expect(action.options.contains(.foreground)
                == (action.identifier == NotificationAction.cancelling.rawValue))
        }

        let verification = try #require(categories[NotificationCategory.verification])
        #expect(verification.actions.map(\.identifier) == [
            NotificationAction.chargesStopped.rawValue,
            NotificationAction.stillCharging.rawValue
        ])
        for action in verification.actions {
            #expect(action.options.contains(.foreground)
                == (action.identifier == NotificationAction.stillCharging.rawValue))
        }

        let usage = try #require(categories[NotificationCategory.usage])
        #expect(usage.actions.map(\.identifier) == [
            NotificationAction.stillUsing.rawValue,
            NotificationAction.notUsing.rawValue
        ])
    }

    // `.ephemeral` (also mapped to .authorized) cannot be constructed on the
    // mac host - it is App-Clip-only and unavailable in macOS.
    @Test("every authorization status maps to the distinct permission Today renders", arguments: [
        (UNAuthorizationStatus.notDetermined, NotificationPermission.notDetermined),
        (.denied, .denied),
        (.provisional, .provisional),
        (.authorized, .authorized)
    ])
    func permissionMapping(status: UNAuthorizationStatus, expected: NotificationPermission) async {
        center.setStatus(status)
        #expect(await client.permission() == expected)
    }

    @Test("requestAuthorization asks for alert+badge+sound and reports the settings truth, not the dialog's")
    func requestAuthorizationReadsBack() async {
        center.setStatus(.denied)
        let outcome = await client.requestAuthorization()
        #expect(outcome == .denied)
        #expect(center.requestedOptions == [[.alert, .badge, .sound]])
    }
}
