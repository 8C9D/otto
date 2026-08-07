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
    private var records: [UUID: CancellationRecord] = [:]
    private var failure: (any Error)?

    func seed(_ newRecords: [CancellationRecord]) {
        for record in newRecords { records[record.subscriptionID] = record }
    }

    func fail(with error: any Error) { failure = error }

    private func throwPrimedFailure() throws {
        if let failure { throw failure }
    }

    func save(_ record: CancellationRecord) async throws {
        try throwPrimedFailure()
        records[record.subscriptionID] = record
    }

    func record(forSubscription subscriptionID: UUID) async throws -> CancellationRecord? {
        try throwPrimedFailure()
        guard let record = records[subscriptionID], record.deletedAt == nil else { return nil }
        return record
    }

    func recordIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> CancellationRecord? {
        try throwPrimedFailure()
        return records[subscriptionID]
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
