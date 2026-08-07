import Foundation
import OttoDomain
import OttoRepositories
import Testing
@testable import OttoServices

/// Unwraps a validated `CalendarDay`, failing the calling test at its own line.
func day(
    _ year: Int,
    _ month: Int,
    _ dayOfMonth: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> CalendarDay {
    try #require(CalendarDay(year: year, month: month, day: dayOfMonth), sourceLocation: sourceLocation)
}

/// A deterministic UUID so fixture failures reproduce identically run to run.
func fixtureUUID(
    _ index: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> UUID {
    let uuidString = String(format: "00000000-0000-0000-0000-%012d", index)
    return try #require(UUID(uuidString: uuidString), sourceLocation: sourceLocation)
}

func makeTrialTerm(
    index: Int = 500,
    startDate: CalendarDay,
    lengthDays: Int = 14,
    bufferDays: Int = 2,
    convertsToAmountCents: Int = 1100,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> TrialTerm {
    try #require(
        TrialTerm(
            id: try fixtureUUID(index),
            startDate: startDate,
            lengthDays: lengthDays,
            bufferDays: bufferDays,
            convertsToAmountCents: convertsToAmountCents,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        sourceLocation: sourceLocation
    )
}

func makeSubscription(
    index: Int = 0,
    name: String = "FoodApp",
    status: SubscriptionStatus = .active,
    amountCents: Int = 1100,
    cycle: BillingCycle = .monthly,
    cycleStartDay: CalendarDay,
    reminderLeadDays: Int = 3,
    sameDayReminder: Bool = false,
    pauseEndsOn: CalendarDay? = nil,
    trial: TrialTerm? = nil,
    cancellationURL: URL? = nil,
    lastUsedDate: CalendarDay? = nil
) throws -> Subscription {
    Subscription(
        id: try fixtureUUID(index),
        name: name,
        category: .foodAndDelivery,
        status: status,
        amountCents: amountCents,
        currencyCode: "CAD",
        cycle: cycle,
        cycleStartDay: cycleStartDay,
        reminderLeadDays: reminderLeadDays,
        sameDayReminder: sameDayReminder,
        pauseEndsOn: pauseEndsOn,
        trial: trial,
        cancellationURL: cancellationURL,
        lastUsedDate: lastUsedDate,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

// MARK: - Fakes

/// In-memory notification center: same replace-by-identifier semantics as
/// `UNUserNotificationCenter`, plus a switchable permission.
actor FakeNotificationClient: NotificationClient {
    var storedPermission: NotificationPermission = .authorized
    private(set) var requests: [NotificationRequestSpec] = []

    func setPermission(_ permission: NotificationPermission) {
        storedPermission = permission
    }

    func permission() async -> NotificationPermission { storedPermission }

    func requestAuthorization() async -> NotificationPermission { storedPermission }

    func pendingRequests() async -> [NotificationRequestSpec] { requests }

    func add(_ spec: NotificationRequestSpec) async throws {
        requests.removeAll { $0.identifier == spec.identifier }
        requests.append(spec)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        let doomed = Set(identifiers)
        requests.removeAll { doomed.contains($0.identifier) }
    }
}

/// Repository fakes - the same shapes as the store-layer mocks, duplicated here
/// because test targets cannot share sources without a support target earning
/// its keep.
actor FakeSubscriptionRepository: SubscriptionRepository {
    private var stored: [UUID: Subscription] = [:]
    private(set) var savedValues: [Subscription] = []

    func seed(_ subscriptions: [Subscription]) {
        for subscription in subscriptions { stored[subscription.id] = subscription }
    }

    func save(_ subscription: Subscription) async throws {
        stored[subscription.id] = subscription
        savedValues.append(subscription)
    }

    func subscription(withID id: UUID) async throws -> Subscription? {
        guard let subscription = stored[id], subscription.deletedAt == nil else { return nil }
        return subscription
    }

    func subscriptions() async throws -> [Subscription] {
        stored.values.filter { $0.deletedAt == nil }
            .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
    }

    func subscriptionsIncludingDeleted() async throws -> [Subscription] {
        stored.values.sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
    }

    func deleteSubscription(withID id: UUID, at instant: Date) async throws {
        guard var subscription = stored[id] else { throw RepositoryError.subscriptionNotFound(id) }
        if subscription.deletedAt == nil {
            subscription.deletedAt = instant
            stored[id] = subscription
        }
    }
}

actor FakeCancellationRepository: CancellationRepository {
    private var records: [UUID: CancellationRecord] = [:]

    func seed(_ newRecords: [CancellationRecord]) {
        for record in newRecords { records[record.subscriptionID] = record }
    }

    func save(_ record: CancellationRecord) async throws {
        records[record.subscriptionID] = record
    }

    func record(forSubscription subscriptionID: UUID) async throws -> CancellationRecord? {
        guard let record = records[subscriptionID], record.deletedAt == nil else { return nil }
        return record
    }

    func recordIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> CancellationRecord? {
        records[subscriptionID]
    }
}

/// Records ledger calls so tests can assert the scheduler performs upkeep at
/// scheduling time (spec §5.3) without dragging SwiftData into this target.
actor FakeBillingEventRepository: BillingEventRepository {
    private(set) var invalidateCalls: [UUID] = []
    private(set) var materializeCalls: [UUID] = []

    func save(_ event: BillingEvent) async throws {}

    func events(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] { [] }

    func eventsIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] { [] }

    func materializeEvents(
        for subscription: Subscription,
        from today: CalendarDay,
        horizonDays: Int,
        maxReminderLeadDays: Int,
        at instant: Date
    ) async throws -> [BillingEvent] {
        materializeCalls.append(subscription.id)
        return []
    }

    func invalidateOutdatedUpcomingEvents(
        for subscription: Subscription,
        asOf today: CalendarDay,
        at instant: Date
    ) async throws -> [BillingEvent] {
        invalidateCalls.append(subscription.id)
        return []
    }
}

/// One assembled scheduler (and, on demand, its action handler) over fresh fakes.
struct SchedulerFixture {
    let scheduler: NotificationScheduler
    let client: FakeNotificationClient
    let subscriptions: FakeSubscriptionRepository
    let cancellations: FakeCancellationRepository
    let billingEvents: FakeBillingEventRepository

    init() {
        client = FakeNotificationClient()
        subscriptions = FakeSubscriptionRepository()
        cancellations = FakeCancellationRepository()
        billingEvents = FakeBillingEventRepository()
        scheduler = NotificationScheduler(
            subscriptions: subscriptions,
            cancellations: cancellations,
            billingEvents: billingEvents,
            client: client
        )
    }

    var handler: NotificationActionHandler {
        NotificationActionHandler(
            subscriptions: subscriptions,
            cancellations: cancellations,
            client: client,
            scheduler: scheduler
        )
    }
}

let torontoZone = TimeZone(identifier: "America/Toronto") ?? .current

/// 2026-08-06 at 08:00 Toronto - before the 09:00 preferred hour, so same-day
/// reminders are schedulable.
func fixtureNow() throws -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 6
    components.hour = 8
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = torontoZone
    return try #require(gregorian.date(from: components))
}
