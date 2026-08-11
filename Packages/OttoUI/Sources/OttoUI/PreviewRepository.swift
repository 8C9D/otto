#if DEBUG
import Foundation
import OttoDomain
import OttoRepositories

// The in-memory repository the previews run against. Split out of
// PreviewSupport.swift, which passed SwiftLint's 400-line file_length; the seam
// is the obvious one - PreviewSupport.swift holds the FIXTURES, this holds the
// repository that serves them.

/// One in-memory actor implementing every repository protocol, pre-seeded
/// with the preview fixtures.
actor PreviewRepository:
    SubscriptionRepository, BillingEventRepository, CancellationRepository,
    PriceChangeRepository, PaymentMethodRepository, DataTransferRepository {

    private var subscriptions: [UUID: Subscription] = [:]
    private var events: [UUID: BillingEvent] = [:]
    private var cancellations: [UUID: CancellationEpisode] = [:]
    private var priceChanges: [UUID: PriceChange] = [:]
    private var paymentMethods: [UUID: PaymentMethod] = [:]

    init() {
        let fixtures = PreviewData.fixtures()
        for subscription in fixtures.subscriptions { subscriptions[subscription.id] = subscription }
        for record in fixtures.cancellations { cancellations[record.id] = record }
        for event in fixtures.events { events[event.id] = event }
        for change in fixtures.priceChanges { priceChanges[change.id] = change }
    }

    // MARK: SubscriptionRepository

    func save(_ subscription: Subscription) async throws {
        subscriptions[subscription.id] = subscription
    }

    func subscription(withID id: UUID) async throws -> Subscription? {
        subscriptions[id].flatMap { $0.deletedAt == nil ? $0 : nil }
    }

    func subscriptions() async throws -> [Subscription] {
        subscriptions.values.filter { $0.deletedAt == nil }
            .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
    }

    func subscriptionsIncludingDeleted() async throws -> [Subscription] {
        Array(subscriptions.values)
    }

    /// Both default to "nothing to review", which is what every preview wants.
    /// A test seeds them to check that Today's input actually READS them - with
    /// both at their defaults the assertion would be `0 == 0` and would hold
    /// however the mapping was wired.
    private var seededUnreadableCount = 0
    private var seededReadRepairs: [SubscriptionReadRepairReport] = []

    func seedNeedsReview(unreadableCount: Int, readRepairs: [SubscriptionReadRepairReport]) {
        seededUnreadableCount = unreadableCount
        seededReadRepairs = readRepairs
    }

    func unreadableSubscriptionCount() async throws -> Int { seededUnreadableCount }

    func subscriptionReadRepairs() async throws -> [SubscriptionReadRepairReport] { seededReadRepairs }

    func deleteSubscription(withID id: UUID, at instant: Date) async throws {
        guard var subscription = subscriptions[id] else { return }
        if subscription.deletedAt == nil {
            subscription.deletedAt = instant
            subscriptions[id] = subscription
        }
    }

    // MARK: BillingEventRepository

    func save(_ event: BillingEvent) async throws {
        events[event.id] = event
    }

    func events(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] {
        events.values.filter { $0.subscriptionID == subscriptionID && $0.deletedAt == nil }
            .sorted { ($0.expectedDate, $0.id.uuidString) < ($1.expectedDate, $1.id.uuidString) }
    }

    func eventsIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] {
        events.values.filter { $0.subscriptionID == subscriptionID }
            .sorted { ($0.expectedDate, $0.id.uuidString) < ($1.expectedDate, $1.id.uuidString) }
    }

    func materializeEvents(
        for subscription: Subscription,
        from today: CalendarDay,
        horizonDays: Int,
        maxReminderLeadDays: Int,
        at instant: Date
    ) async throws -> [BillingEvent] {
        []
    }

    func invalidateOutdatedUpcomingEvents(
        for subscription: Subscription,
        asOf today: CalendarDay,
        at instant: Date
    ) async throws -> [BillingEvent] {
        []
    }

    // Previews never materialize, so the watermark operations hold a token map.
    private var watermarks: [UUID: CalendarDay] = [:]

    func materializationWatermark(forSubscription subscriptionID: UUID) async throws -> CalendarDay? {
        watermarks[subscriptionID]
    }

    func initializeMaterializationWatermark(
        forSubscription subscriptionID: UUID, at day: CalendarDay
    ) async throws {
        if watermarks[subscriptionID] == nil { watermarks[subscriptionID] = day }
    }

    func rewindMaterializationWatermark(
        forSubscription subscriptionID: UUID, to day: CalendarDay
    ) async throws {
        if let stored = watermarks[subscriptionID], day < stored { watermarks[subscriptionID] = day }
    }

    // MARK: CancellationRepository

    func save(_ episode: CancellationEpisode) async throws {
        cancellations[episode.id] = episode
    }

    func openEpisode(forSubscription subscriptionID: UUID) async throws -> CancellationEpisode? {
        try await episodes(forSubscription: subscriptionID).first { $0.isOpen }
    }

    func episodes(forSubscription subscriptionID: UUID) async throws -> [CancellationEpisode] {
        cancellations.values
            .filter { $0.subscriptionID == subscriptionID && $0.deletedAt == nil }
            .sorted { ($0.markedCancelledAt, $0.id.uuidString) > ($1.markedCancelledAt, $1.id.uuidString) }
    }

    func episodesIncludingDeleted(
        forSubscription subscriptionID: UUID
    ) async throws -> [CancellationEpisode] {
        cancellations.values
            .filter { $0.subscriptionID == subscriptionID }
            .sorted { ($0.markedCancelledAt, $0.id.uuidString) > ($1.markedCancelledAt, $1.id.uuidString) }
    }

    // MARK: PriceChangeRepository

    func append(_ change: PriceChange) async throws {
        priceChanges[change.id] = change
    }

    func history(forSubscription subscriptionID: UUID) async throws -> [PriceChange] {
        priceChanges.values.filter { $0.subscriptionID == subscriptionID && $0.deletedAt == nil }
            .sorted { ($0.effectiveDate, $0.createdAt) < ($1.effectiveDate, $1.createdAt) }
    }

    func historyIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [PriceChange] {
        priceChanges.values.filter { $0.subscriptionID == subscriptionID }
            .sorted { ($0.effectiveDate, $0.createdAt) < ($1.effectiveDate, $1.createdAt) }
    }

    // MARK: PaymentMethodRepository

    func save(_ method: PaymentMethod) async throws {
        paymentMethods[method.id] = method
    }

    func paymentMethod(withID id: UUID) async throws -> PaymentMethod? {
        paymentMethods[id].flatMap { $0.deletedAt == nil ? $0 : nil }
    }

    func paymentMethods() async throws -> [PaymentMethod] {
        paymentMethods.values.filter { $0.deletedAt == nil }
            .sorted { ($0.label, $0.id.uuidString) < ($1.label, $1.id.uuidString) }
    }

    func paymentMethodsIncludingDeleted() async throws -> [PaymentMethod] {
        Array(paymentMethods.values)
    }

    func deletePaymentMethod(withID id: UUID, at instant: Date) async throws {
        guard var method = paymentMethods[id] else { return }
        if method.deletedAt == nil {
            method.deletedAt = instant
            paymentMethods[id] = method
        }
    }

    // MARK: DataTransferRepository

    func completeSnapshot() async throws -> OttoDataSnapshot {
        OttoDataSnapshot(
            subscriptions: subscriptions.values.sorted { $0.id.uuidString < $1.id.uuidString },
            paymentMethods: paymentMethods.values.sorted { $0.id.uuidString < $1.id.uuidString },
            billingEvents: events.values.sorted { $0.id.uuidString < $1.id.uuidString },
            cancellationEpisodes: cancellations.values.sorted { $0.id.uuidString < $1.id.uuidString },
            priceChanges: priceChanges.values.sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    func restore(
        _ snapshot: OttoDataSnapshot, at instant: Date, watermarks: RestoreWatermarkPolicy
    ) async throws {
        subscriptions = Dictionary(uniqueKeysWithValues: snapshot.subscriptions.map { ($0.id, $0) })
        paymentMethods = Dictionary(uniqueKeysWithValues: snapshot.paymentMethods.map { ($0.id, $0) })
        events = Dictionary(uniqueKeysWithValues: snapshot.billingEvents.map { ($0.id, $0) })
        cancellations = Dictionary(
            uniqueKeysWithValues: snapshot.cancellationEpisodes.map { ($0.subscriptionID, $0) }
        )
        priceChanges = Dictionary(uniqueKeysWithValues: snapshot.priceChanges.map { ($0.id, $0) })
        if watermarks == .reconstruct {
            try await reconstructMaterializationWatermarks()
        }
    }

    func reconstructMaterializationWatermarks() async throws {
        watermarks = subscriptions.values
            .filter { $0.deletedAt == nil }
            .reduce(into: [:]) { result, subscription in
                let latest = events.values
                    .filter { $0.subscriptionID == subscription.id && $0.deletedAt == nil }
                    .map(\.expectedDate)
                    .max()
                result[subscription.id] = latest ?? subscription.cycleStartDay
            }
    }
}
#endif
