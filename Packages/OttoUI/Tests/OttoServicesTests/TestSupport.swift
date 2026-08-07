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
    lastMaterializedThrough: CalendarDay? = nil,
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
        lastMaterializedThrough: lastMaterializedThrough,
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
    private var saveFailure: (any Error)?

    func seed(_ subscriptions: [Subscription]) {
        for subscription in subscriptions { stored[subscription.id] = subscription }
    }

    /// Primes the next saves to fail - for asserting what a flow leaves behind
    /// when it dies mid-way.
    func failSaves(with error: any Error) { saveFailure = error }
    func recoverSaves() { saveFailure = nil }

    func save(_ subscription: Subscription) async throws {
        if let saveFailure { throw saveFailure }
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

    func unreadableSubscriptionCount() async throws -> Int { 0 }

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

/// In-memory ledger with the same materialization and invalidation semantics as
/// the SwiftData store - both defer every decision to the domain's
/// `expectedCharges`/`isExpectedCharge`, so the fake stays honest without
/// dragging SwiftData into this target. Call counters let scheduler tests assert
/// upkeep happens at scheduling time (spec §5.3).
actor FakeBillingEventRepository: BillingEventRepository {
    private var stored: [UUID: BillingEvent] = [:]
    private(set) var invalidateCalls: [UUID] = []
    private(set) var materializeCalls: [UUID] = []

    func seed(_ events: [BillingEvent]) {
        for event in events { stored[event.id] = event }
    }

    func save(_ event: BillingEvent) async throws {
        stored[event.id] = event
    }

    func events(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] {
        try await eventsIncludingDeleted(forSubscription: subscriptionID)
            .filter { $0.deletedAt == nil }
    }

    func eventsIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] {
        stored.values
            .filter { $0.subscriptionID == subscriptionID }
            .sorted { ($0.expectedDate, $0.id.uuidString) < ($1.expectedDate, $1.id.uuidString) }
    }

    func materializeEvents(
        for subscription: Subscription,
        from today: CalendarDay,
        horizonDays: Int,
        maxReminderLeadDays: Int,
        at instant: Date
    ) async throws -> [BillingEvent] {
        materializeCalls.append(subscription.id)
        guard subscription.deletedAt == nil, horizonDays >= 0, maxReminderLeadDays >= 0 else {
            return []
        }
        // The window reaches back to the watermark, mirroring the store
        // (spec §5.3, v1.5). The mock has no stored record of its own, so the
        // passed value's watermark stands in for it.
        let charges = expectedCharges(
            for: subscription,
            from: min(subscription.lastMaterializedThrough ?? today, today),
            through: today.adding(days: horizonDays + maxReminderLeadDays),
            asOf: today
        )
        // Dedup mirrors the store: live rows and non-.upcoming tombstones block;
        // tombstoned .upcoming rows are invalidation artifacts and do not.
        let blockedDates = Set(
            stored.values
                .filter { $0.subscriptionID == subscription.id }
                .filter { $0.deletedAt == nil || $0.state != .upcoming }
                .map(\.expectedDate)
        )
        var created: [BillingEvent] = []
        for charge in charges where !blockedDates.contains(charge.day) {
            let event = BillingEvent(
                id: UUID(),
                subscriptionID: subscription.id,
                expectedDate: charge.day,
                expectedAmountCents: charge.amountCents,
                state: .upcoming,
                createdAt: instant,
                updatedAt: instant
            )
            stored[event.id] = event
            created.append(event)
        }
        return created
    }

    func invalidateOutdatedUpcomingEvents(
        for subscription: Subscription,
        asOf today: CalendarDay,
        at instant: Date
    ) async throws -> [BillingEvent] {
        invalidateCalls.append(subscription.id)
        var invalidated: [BillingEvent] = []
        for var event in stored.values
        where event.subscriptionID == subscription.id && event.deletedAt == nil && event.state == .upcoming {
            if isExpectedCharge(
                day: event.expectedDate, amountCents: event.expectedAmountCents,
                for: subscription, asOf: today
            ) { continue }
            event.deletedAt = instant
            event.updatedAt = instant
            stored[event.id] = event
            invalidated.append(event)
        }
        return invalidated.sorted { ($0.expectedDate, $0.id.uuidString) < ($1.expectedDate, $1.id.uuidString) }
    }
}

/// One assembled scheduler (and, on demand, its flow service and action handler)
/// over fresh fakes.
struct SchedulerFixture {
    let scheduler: NotificationScheduler
    let client: FakeNotificationClient
    let subscriptions: FakeSubscriptionRepository
    let cancellations: FakeCancellationRepository
    let billingEvents: FakeBillingEventRepository
    let priceChanges: FakePriceChangeRepository

    init() {
        client = FakeNotificationClient()
        subscriptions = FakeSubscriptionRepository()
        cancellations = FakeCancellationRepository()
        billingEvents = FakeBillingEventRepository()
        priceChanges = FakePriceChangeRepository()
        scheduler = NotificationScheduler(
            subscriptions: subscriptions,
            cancellations: cancellations,
            billingEvents: billingEvents,
            client: client
        )
    }

    var flows: SubscriptionFlowService {
        SubscriptionFlowService(
            subscriptions: subscriptions,
            cancellations: cancellations,
            billingEvents: billingEvents,
            priceChanges: priceChanges
        )
    }

    var handler: NotificationActionHandler {
        NotificationActionHandler(
            subscriptions: subscriptions,
            flows: flows,
            client: client,
            scheduler: scheduler
        )
    }
}

actor FakePriceChangeRepository: PriceChangeRepository {
    private var changes: [UUID: PriceChange] = [:]

    func append(_ change: PriceChange) async throws {
        changes[change.id] = change
    }

    func history(forSubscription subscriptionID: UUID) async throws -> [PriceChange] {
        changes.values
            .filter { $0.subscriptionID == subscriptionID && $0.deletedAt == nil }
            .sorted { ($0.effectiveDate, $0.createdAt) < ($1.effectiveDate, $1.createdAt) }
    }

    func historyIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [PriceChange] {
        changes.values
            .filter { $0.subscriptionID == subscriptionID }
            .sorted { ($0.effectiveDate, $0.createdAt) < ($1.effectiveDate, $1.createdAt) }
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
