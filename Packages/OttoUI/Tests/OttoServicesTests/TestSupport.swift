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
    pausedOn: CalendarDay? = nil,
    pauseEpisodes: [PauseEpisode]? = nil,
    trial: TrialTerm? = nil,
    cancellationURL: URL? = nil,
    lastUsedDate: CalendarDay? = nil
) throws -> Subscription {
    // The v1.7-era pause parameters survive as the open episode they now
    // describe (spec §5.3a).
    let episodes: [PauseEpisode]
    if let pauseEpisodes {
        episodes = pauseEpisodes
    } else if status == .paused || pausedOn != nil || pauseEndsOn != nil {
        episodes = [PauseEpisode(
            id: try fixtureUUID(index + 700),
            startedOn: pausedOn,
            scheduledResumeOn: pauseEndsOn,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )]
    } else {
        episodes = []
    }
    return Subscription(
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
        pauseEpisodes: episodes,
        trial: trial,
        cancellationURL: cancellationURL,
        lastUsedDate: lastUsedDate,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

// MARK: - Fakes

/// In-memory notification center: same replace-by-identifier semantics as
/// `UNUserNotificationCenter`, plus a switchable permission, a call log for
/// reconciliation assertions, and injectable `add` failure - the fake whose
/// `add` never threw is the gap this wave exists to close (Wave 10).
actor FakeNotificationClient: NotificationClient {
    struct AddRefused: Error {}

    var storedPermission: NotificationPermission = .authorized
    private(set) var requests: [NotificationRequestSpec] = []
    /// Every `add` call in order, including replacements and failed attempts.
    private(set) var addCalls: [NotificationRequestSpec] = []
    /// Every `removePendingRequests` call's identifiers, flattened, in order.
    private(set) var removeCalls: [String] = []
    private var remainingAddsBeforeRefusal: Int?

    func setPermission(_ permission: NotificationPermission) {
        storedPermission = permission
    }

    /// Models suspension mid-reconciliation: `count` more adds land, then the
    /// center stops accepting calls - the device state at that instant is what
    /// the loss-window tests assert on.
    func refuseAdds(after count: Int) {
        remainingAddsBeforeRefusal = count
    }

    func clearCallLog() {
        addCalls = []
        removeCalls = []
    }

    func permission() async -> NotificationPermission { storedPermission }

    func requestAuthorization() async -> NotificationPermission { storedPermission }

    func pendingRequests() async -> [NotificationRequestSpec] { requests }

    func add(_ spec: NotificationRequestSpec) async throws {
        addCalls.append(spec)
        if let remaining = remainingAddsBeforeRefusal {
            guard remaining > 0 else { throw AddRefused() }
            remainingAddsBeforeRefusal = remaining - 1
        }
        requests.removeAll { $0.identifier == spec.identifier }
        requests.append(spec)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        removeCalls.append(contentsOf: identifiers)
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

    func subscriptionReadRepairs() async throws -> [SubscriptionReadRepairReport] { [] }

    func deleteSubscription(withID id: UUID, at instant: Date) async throws {
        guard var subscription = stored[id] else { throw RepositoryError.subscriptionNotFound(id) }
        if subscription.deletedAt == nil {
            subscription.deletedAt = instant
            stored[id] = subscription
        }
    }
}

actor FakeCancellationRepository: CancellationRepository {
    private var episodesByID: [UUID: CancellationEpisode] = [:]

    func seed(_ newEpisodes: [CancellationEpisode]) {
        for episode in newEpisodes { episodesByID[episode.id] = episode }
    }

    func save(_ episode: CancellationEpisode) async throws {
        episodesByID[episode.id] = episode
    }

    func openEpisode(forSubscription subscriptionID: UUID) async throws -> CancellationEpisode? {
        try await episodes(forSubscription: subscriptionID).first { $0.isOpen }
    }

    func episodes(forSubscription subscriptionID: UUID) async throws -> [CancellationEpisode] {
        episodesByID.values
            .filter { $0.subscriptionID == subscriptionID && $0.deletedAt == nil }
            .sorted { ($0.markedCancelledAt, $0.id.uuidString) > ($1.markedCancelledAt, $1.id.uuidString) }
    }

    func episodesIncludingDeleted(
        forSubscription subscriptionID: UUID
    ) async throws -> [CancellationEpisode] {
        episodesByID.values
            .filter { $0.subscriptionID == subscriptionID }
            .sorted { ($0.markedCancelledAt, $0.id.uuidString) > ($1.markedCancelledAt, $1.id.uuidString) }
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
