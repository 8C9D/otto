import Foundation
import Observation
import OttoDomain
import OttoRepositories

/// The observable state behind Today and the subscription list: every live
/// subscription, plus the cancellation records that drive verification cards.
///
/// Holds domain values only, loaded through the repository protocols - it cannot
/// name a persistence type, and views cannot reach a repository except through it.
/// Main-actor bound; the repository calls are async and never block it.
@MainActor
@Observable
public final class SubscriptionsStore {
    public private(set) var subscriptions: LoadState<[Subscription]> = .loading

    /// Each cancelled or cancellation-pending subscription's record, keyed by
    /// subscription id. Loaded alongside the list because Today's verification
    /// cards are derived from both together.
    public private(set) var cancellations: [UUID: CancellationRecord] = [:]

    private let subscriptionRepository: any SubscriptionRepository
    private let cancellationRepository: any CancellationRepository
    private let dates: DateProvider

    /// Runs after every successful mutation - the create/edit/delete reschedule
    /// trigger (spec §6.2). The app model points this at the notification status
    /// store; previews and tests may leave it unset.
    public var onMutation: (@MainActor () async -> Void)?

    public init(
        subscriptionRepository: any SubscriptionRepository,
        cancellationRepository: any CancellationRepository,
        dates: DateProvider = .live
    ) {
        self.subscriptionRepository = subscriptionRepository
        self.cancellationRepository = cancellationRepository
        self.dates = dates
    }

    /// The current calendar day, for views that classify or sort by date.
    public var today: CalendarDay { dates.today() }

    /// Today's three sections, or nil until the list has loaded.
    public var overview: TodayOverview? {
        guard let subscriptions = subscriptions.value else { return nil }
        return todayOverview(subscriptions: subscriptions, cancellations: cancellations, from: dates.today())
    }

    /// Reloads everything. A repository failure becomes `.failed` - never an
    /// empty list.
    public func refresh() async {
        do {
            let loaded = try await subscriptionRepository.subscriptions()
            var records: [UUID: CancellationRecord] = [:]
            for subscription in loaded
            where subscription.status == .cancellationPending || subscription.status == .cancelled {
                if let record = try await cancellationRepository.record(forSubscription: subscription.id) {
                    records[subscription.id] = record
                }
            }
            subscriptions = .loaded(loaded)
            cancellations = records
        } catch {
            subscriptions = .failed(error)
        }
    }

    /// Writes through the repository, then refreshes the published state. Throws
    /// so the caller can present the failure; the published state is untouched by
    /// a failed write.
    public func save(_ subscription: Subscription) async throws {
        try await subscriptionRepository.save(subscription)
        await refresh()
        await onMutation?()
    }

    /// Soft-deletes at the current instant, then refreshes.
    public func delete(subscriptionID: UUID) async throws {
        try await subscriptionRepository.deleteSubscription(withID: subscriptionID, at: dates.now())
        await refresh()
        await onMutation?()
    }
}
