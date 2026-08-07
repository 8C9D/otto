#if DEBUG
import Foundation
import OttoDomain
import OttoRepositories
import OttoStores

// In-memory repositories and fixture data for previews. Debug-only; the app's
// composition root injects the real persistence instead.

/// The preview data set, grouped so callers take what they need.
struct PreviewFixtures {
    var subscriptions: [Subscription] = []
    var cancellations: [CancellationEpisode] = []
    var events: [BillingEvent] = []
    var priceChanges: [PriceChange] = []
}

/// The fixed "today" every preview renders against: 2026-08-06.
enum PreviewData {
    static var today: CalendarDay {
        guard let day = CalendarDay(year: 2026, month: 8, day: 6) else {
            preconditionFailure("The preview date is invalid")
        }
        return day
    }

    static let now = Date(timeIntervalSince1970: 1_786_000_000)

    @MainActor
    static func model() -> AppModel {
        let repository = PreviewRepository()
        let model = AppModel(
            repositories: AppModel.Repositories(
                subscriptions: repository,
                billingEvents: repository,
                cancellations: repository,
                priceChanges: repository,
                paymentMethods: repository,
                transfer: repository
            ),
            // A throwaway suite: previews must not write the real defaults.
            settings: SettingsStore(
                userDefaults: UserDefaults(suiteName: "otto.previews") ?? .standard
            ),
            dates: .fixed(today: today, now: now)
        )
        return model
    }

    // MARK: - Fixtures, including the awkward cases

    static func fixtures() -> PreviewFixtures {
        var fixtures = PreviewFixtures()
        addNetflix(to: &fixtures)
        addFoodAppTrial(to: &fixtures)
        addPausedGym(to: &fixtures)
        addCancelledCrave(to: &fixtures)
        // An annual subscription beyond the 30-day horizon - the Later section.
        if let anchor = CalendarDay(year: 2025, month: 11, day: 12) {
            fixtures.subscriptions.append(subscription(
                index: 5, name: "iCloud+", category: .cloudAndStorage,
                amountCents: 12900, anchor: anchor, cycle: .annual
            ))
        }
        return fixtures
    }

    /// A 31-anchored monthly subscription - the clamping case - with a ledger
    /// and a price history.
    private static func addNetflix(to fixtures: inout PreviewFixtures) {
        guard let anchor = CalendarDay(year: 2026, month: 1, day: 31) else { return }
        let netflix = subscription(
            index: 1, name: "Netflix", category: .streamingAndVideo,
            amountCents: 2099, anchor: anchor
        )
        fixtures.subscriptions.append(netflix)
        if let expected = CalendarDay(year: 2026, month: 8, day: 31) {
            fixtures.events.append(BillingEvent(
                id: uuid(101), subscriptionID: netflix.id, expectedDate: expected,
                expectedAmountCents: 2099, state: .upcoming, createdAt: now, updatedAt: now
            ))
        }
        if let julyCharge = CalendarDay(year: 2026, month: 7, day: 31) {
            fixtures.events.append(BillingEvent(
                id: uuid(102), subscriptionID: netflix.id, expectedDate: julyCharge,
                expectedAmountCents: 2099, state: .confirmedCharged,
                userConfirmedAt: now, createdAt: now, updatedAt: now
            ))
        }
        if let effective = CalendarDay(year: 2026, month: 3, day: 31) {
            fixtures.priceChanges.append(PriceChange(
                id: uuid(201), subscriptionID: netflix.id, effectiveDate: effective,
                oldAmountCents: 1899, newAmountCents: 2099,
                source: .userEdit, note: "Standard plan price increase",
                createdAt: now, updatedAt: now
            ))
        }
    }

    /// A trial two days from conversion - inside its cancel-by window.
    private static func addFoodAppTrial(to fixtures: inout PreviewFixtures) {
        guard let trialStart = CalendarDay(year: 2026, month: 7, day: 25),
              let trial = TrialTerm(
                  id: uuid(501), startDate: trialStart, lengthDays: 14, bufferDays: 2,
                  convertsToAmountCents: 1099, createdAt: now, updatedAt: now
              ) else { return }
        fixtures.subscriptions.append(subscription(
            index: 2, name: "FoodApp", category: .foodAndDelivery,
            amountCents: 1099, anchor: trialStart, status: .trial, trial: trial
        ))
    }

    /// A paused subscription with a resume date.
    private static func addPausedGym(to fixtures: inout PreviewFixtures) {
        guard let anchor = CalendarDay(year: 2026, month: 2, day: 10),
              let resumes = CalendarDay(year: 2026, month: 9, day: 10) else { return }
        fixtures.subscriptions.append(subscription(
            index: 3, name: "GoodLife Fitness", category: .fitnessAndHealth,
            amountCents: 4200, anchor: anchor, status: .paused, pauseEndsOn: resumes
        ))
    }

    /// A cancelled subscription with a verification check due - and no payment
    /// method, like every fixture here (the awkward case is the default).
    private static func addCancelledCrave(to fixtures: inout PreviewFixtures) {
        guard let anchor = CalendarDay(year: 2026, month: 5, day: 20),
              let checkDate = CalendarDay(year: 2026, month: 8, day: 3) else { return }
        let cancelled = subscription(
            index: 4, name: "Crave", category: .streamingAndVideo,
            amountCents: 999, anchor: anchor, status: .cancelled
        )
        fixtures.subscriptions.append(cancelled)
        fixtures.cancellations.append(CancellationEpisode(
            id: uuid(601), subscriptionID: cancelled.id, markedCancelledAt: now,
            nextChargeDateIfNotCancelled: checkDate, verificationState: .pending,
            evidenceNote: "Confirmation #58291", createdAt: now, updatedAt: now
        ))
    }

    private static func subscription(
        index: Int,
        name: String,
        category: OttoDomain.Category,
        amountCents: Int,
        anchor: CalendarDay,
        cycle: BillingCycle = .monthly,
        status: SubscriptionStatus = .active,
        pauseEndsOn: CalendarDay? = nil,
        trial: TrialTerm? = nil
    ) -> Subscription {
        // A paused fixture needs its open episode (spec §5.3a) - the invariant
        // holds in previews too.
        let pauseEpisodes: [PauseEpisode] = status == .paused
            ? [PauseEpisode(
                id: uuid(index + 700),
                startedOn: anchor,
                scheduledResumeOn: pauseEndsOn,
                createdAt: now,
                updatedAt: now
            )]
            : []
        return Subscription(
            id: uuid(index),
            name: name,
            category: category,
            status: status,
            amountCents: amountCents,
            currencyCode: "CAD",
            cycle: cycle,
            cycleStartDay: anchor,
            reminderLeadDays: status == .trial ? 5 : 3,
            pauseEpisodes: pauseEpisodes,
            trial: trial,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))
            ?? UUID()
    }
}

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

    func unreadableSubscriptionCount() async throws -> Int { 0 }

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

    func restore(_ snapshot: OttoDataSnapshot) async throws {
        subscriptions = Dictionary(uniqueKeysWithValues: snapshot.subscriptions.map { ($0.id, $0) })
        paymentMethods = Dictionary(uniqueKeysWithValues: snapshot.paymentMethods.map { ($0.id, $0) })
        events = Dictionary(uniqueKeysWithValues: snapshot.billingEvents.map { ($0.id, $0) })
        cancellations = Dictionary(
            uniqueKeysWithValues: snapshot.cancellationEpisodes.map { ($0.subscriptionID, $0) }
        )
        priceChanges = Dictionary(uniqueKeysWithValues: snapshot.priceChanges.map { ($0.id, $0) })
    }
}
#endif
