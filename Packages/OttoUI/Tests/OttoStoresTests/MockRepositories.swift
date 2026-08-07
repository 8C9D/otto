import Foundation
import OttoDomain
import OttoRepositories

// In-memory repository fakes. Each can be primed with data and primed to fail,
// so store tests exercise both paths without touching persistence.

actor MockSubscriptionRepository: SubscriptionRepository {
    private var stored: [UUID: Subscription] = [:]
    private var failure: (any Error)?
    private(set) var savedValues: [Subscription] = []

    func seed(_ subscriptions: [Subscription]) {
        for subscription in subscriptions { stored[subscription.id] = subscription }
    }

    func fail(with error: any Error) { failure = error }
    func recover() { failure = nil }

    private func throwPrimedFailure() throws {
        if let failure { throw failure }
    }

    func save(_ subscription: Subscription) async throws {
        try throwPrimedFailure()
        stored[subscription.id] = subscription
        savedValues.append(subscription)
    }

    func subscription(withID id: UUID) async throws -> Subscription? {
        try throwPrimedFailure()
        guard let subscription = stored[id], subscription.deletedAt == nil else { return nil }
        return subscription
    }

    func subscriptions() async throws -> [Subscription] {
        try throwPrimedFailure()
        return stored.values.filter { $0.deletedAt == nil }
            .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
    }

    func subscriptionsIncludingDeleted() async throws -> [Subscription] {
        try throwPrimedFailure()
        return stored.values.sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
    }

    /// Primed by tests; the mock's dictionary of domain values cannot hold a
    /// genuinely unmappable record.
    private var primedUnreadableCount = 0

    func primeUnreadableCount(_ count: Int) { primedUnreadableCount = count }

    func unreadableSubscriptionCount() async throws -> Int {
        try throwPrimedFailure()
        return primedUnreadableCount
    }

    /// Primed by tests, like the unreadable count: the mock's dictionary of
    /// domain values cannot hold a shape a read would repair.
    private var primedReadRepairs: [SubscriptionReadRepairReport] = []

    func primeReadRepairs(_ reports: [SubscriptionReadRepairReport]) { primedReadRepairs = reports }

    func subscriptionReadRepairs() async throws -> [SubscriptionReadRepairReport] {
        try throwPrimedFailure()
        return primedReadRepairs
    }

    func deleteSubscription(withID id: UUID, at instant: Date) async throws {
        try throwPrimedFailure()
        guard var subscription = stored[id] else { throw RepositoryError.subscriptionNotFound(id) }
        if subscription.deletedAt == nil {
            subscription.deletedAt = instant
            stored[id] = subscription
        }
    }
}

actor MockCancellationRepository: CancellationRepository {
    private var episodesByID: [UUID: CancellationEpisode] = [:]
    private var failure: (any Error)?

    func seed(_ newEpisodes: [CancellationEpisode]) {
        for episode in newEpisodes { episodesByID[episode.id] = episode }
    }

    func fail(with error: any Error) { failure = error }

    private func throwPrimedFailure() throws {
        if let failure { throw failure }
    }

    func save(_ episode: CancellationEpisode) async throws {
        try throwPrimedFailure()
        episodesByID[episode.id] = episode
    }

    func openEpisode(forSubscription subscriptionID: UUID) async throws -> CancellationEpisode? {
        try await episodes(forSubscription: subscriptionID).first { $0.isOpen }
    }

    func episodes(forSubscription subscriptionID: UUID) async throws -> [CancellationEpisode] {
        try throwPrimedFailure()
        return episodesByID.values
            .filter { $0.subscriptionID == subscriptionID && $0.deletedAt == nil }
            .sorted { ($0.markedCancelledAt, $0.id.uuidString) > ($1.markedCancelledAt, $1.id.uuidString) }
    }

    func episodesIncludingDeleted(
        forSubscription subscriptionID: UUID
    ) async throws -> [CancellationEpisode] {
        try throwPrimedFailure()
        return episodesByID.values
            .filter { $0.subscriptionID == subscriptionID }
            .sorted { ($0.markedCancelledAt, $0.id.uuidString) > ($1.markedCancelledAt, $1.id.uuidString) }
    }
}

actor MockBillingEventRepository: BillingEventRepository {
    private var events: [UUID: BillingEvent] = [:]
    private var failure: (any Error)?

    func seed(_ newEvents: [BillingEvent]) {
        for event in newEvents { events[event.id] = event }
    }

    func fail(with error: any Error) { failure = error }

    private func throwPrimedFailure() throws {
        if let failure { throw failure }
    }

    func save(_ event: BillingEvent) async throws {
        try throwPrimedFailure()
        events[event.id] = event
    }

    func events(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] {
        try throwPrimedFailure()
        return events.values
            .filter { $0.subscriptionID == subscriptionID && $0.deletedAt == nil }
            .sorted { ($0.expectedDate, $0.id.uuidString) < ($1.expectedDate, $1.id.uuidString) }
    }

    func eventsIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] {
        try throwPrimedFailure()
        return events.values
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
        try throwPrimedFailure()
        return []
    }

    func invalidateOutdatedUpcomingEvents(
        for subscription: Subscription,
        asOf today: CalendarDay,
        at instant: Date
    ) async throws -> [BillingEvent] {
        try throwPrimedFailure()
        return []
    }

    private var watermarks: [UUID: CalendarDay] = [:]

    /// Test seeding: the direct write the production protocol deliberately
    /// does not offer (only initialise-once and rewind exist there).
    func seedWatermark(_ day: CalendarDay?, forSubscription subscriptionID: UUID) {
        watermarks[subscriptionID] = day
    }

    func materializationWatermark(forSubscription subscriptionID: UUID) async throws -> CalendarDay? {
        try throwPrimedFailure()
        return watermarks[subscriptionID]
    }

    func initializeMaterializationWatermark(
        forSubscription subscriptionID: UUID, at day: CalendarDay
    ) async throws {
        try throwPrimedFailure()
        if watermarks[subscriptionID] == nil { watermarks[subscriptionID] = day }
    }

    func rewindMaterializationWatermark(
        forSubscription subscriptionID: UUID, to day: CalendarDay
    ) async throws {
        try throwPrimedFailure()
        if let current = watermarks[subscriptionID], day < current { watermarks[subscriptionID] = day }
    }
}

actor MockPriceChangeRepository: PriceChangeRepository {
    private var changes: [UUID: PriceChange] = [:]
    private var failure: (any Error)?

    func seed(_ newChanges: [PriceChange]) {
        for change in newChanges { changes[change.id] = change }
    }

    func fail(with error: any Error) { failure = error }

    private func throwPrimedFailure() throws {
        if let failure { throw failure }
    }

    func append(_ change: PriceChange) async throws {
        try throwPrimedFailure()
        changes[change.id] = change
    }

    func history(forSubscription subscriptionID: UUID) async throws -> [PriceChange] {
        try throwPrimedFailure()
        return changes.values
            .filter { $0.subscriptionID == subscriptionID && $0.deletedAt == nil }
            .sorted { ($0.effectiveDate, $0.createdAt) < ($1.effectiveDate, $1.createdAt) }
    }

    func historyIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [PriceChange] {
        try throwPrimedFailure()
        return changes.values
            .filter { $0.subscriptionID == subscriptionID }
            .sorted { ($0.effectiveDate, $0.createdAt) < ($1.effectiveDate, $1.createdAt) }
    }
}

actor MockPaymentMethodRepository: PaymentMethodRepository {
    private var methods: [UUID: PaymentMethod] = [:]
    private var failure: (any Error)?

    func seed(_ newMethods: [PaymentMethod]) {
        for method in newMethods { methods[method.id] = method }
    }

    func fail(with error: any Error) { failure = error }

    private func throwPrimedFailure() throws {
        if let failure { throw failure }
    }

    func save(_ method: PaymentMethod) async throws {
        try throwPrimedFailure()
        methods[method.id] = method
    }

    func paymentMethod(withID id: UUID) async throws -> PaymentMethod? {
        try throwPrimedFailure()
        guard let method = methods[id], method.deletedAt == nil else { return nil }
        return method
    }

    func paymentMethods() async throws -> [PaymentMethod] {
        try throwPrimedFailure()
        return methods.values.filter { $0.deletedAt == nil }
            .sorted { ($0.label, $0.id.uuidString) < ($1.label, $1.id.uuidString) }
    }

    func paymentMethodsIncludingDeleted() async throws -> [PaymentMethod] {
        try throwPrimedFailure()
        return methods.values.sorted { ($0.label, $0.id.uuidString) < ($1.label, $1.id.uuidString) }
    }

    func deletePaymentMethod(withID id: UUID, at instant: Date) async throws {
        try throwPrimedFailure()
        guard var method = methods[id] else { throw RepositoryError.paymentMethodNotFound(id) }
        if method.deletedAt == nil {
            method.deletedAt = instant
            methods[id] = method
        }
    }
}
