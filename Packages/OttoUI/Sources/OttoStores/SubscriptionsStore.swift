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
    public private(set) var cancellations: [UUID: CancellationEpisode] = [:]

    /// How many live records the last refresh could not read (spec §5.2b, v1.4).
    /// Today renders a single aggregate needs-review card whenever this is
    /// non-zero: a subscription that vanishes from every list silently is the
    /// worst available failure for this product.
    public private(set) var unreadableCount = 0

    /// The §4a read repairs the last refresh applied (spec §4a, Wave 6B-Prep):
    /// shapes a two-device merge can produce, resolved deterministically at
    /// read. Surfaced beside `unreadableCount` in the same aggregate card - a
    /// repair that closed an open pause episode decided something for the
    /// user, and they must see that it happened rather than wonder.
    public private(set) var readRepairs: [SubscriptionReadRepairReport] = []

    private let subscriptionRepository: any SubscriptionRepository
    private let cancellationRepository: any CancellationRepository
    /// For the §5.3 (v1.7) rewind floor: the earliest ledger row ever created
    /// marks where tracking began, and no edit may rewind past it.
    private let billingEventRepository: any BillingEventRepository
    private let dates: DateProvider

    /// Runs after every successful mutation - the create/edit/delete reschedule
    /// trigger (spec §6.2). The app model points this at the notification status
    /// store; previews and tests may leave it unset.
    public var onMutation: (@MainActor () async -> Void)?

    public init(
        subscriptionRepository: any SubscriptionRepository,
        cancellationRepository: any CancellationRepository,
        billingEventRepository: any BillingEventRepository,
        dates: DateProvider = .live
    ) {
        self.subscriptionRepository = subscriptionRepository
        self.cancellationRepository = cancellationRepository
        self.billingEventRepository = billingEventRepository
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
            let today = dates.today()
            var records: [UUID: CancellationEpisode] = [:]
            // Effective, not stored (spec §5.2a, v1.7) - see the same filter in
            // NotificationScheduler.
            for subscription in loaded
            where subscription.effectiveStatus(asOf: today) == .cancellationPending
                || subscription.effectiveStatus(asOf: today) == .cancelled {
                if let record = try await cancellationRepository.openEpisode(forSubscription: subscription.id) {
                    records[subscription.id] = record
                }
            }
            subscriptions = .loaded(loaded)
            cancellations = records
            unreadableCount = try await subscriptionRepository.unreadableSubscriptionCount()
            readRepairs = try await subscriptionRepository.subscriptionReadRepairs()
        } catch {
            subscriptions = .failed(error)
        }
    }

    /// Writes through the repository, then refreshes the published state. Throws
    /// so the caller can present the failure; the published state is untouched by
    /// a failed write.
    ///
    /// This is the Add/Edit choke point, so the §5.3 watermark rules are applied
    /// here through the explicit device-store operations (Wave 6B-Prep: the
    /// domain value no longer carries the watermark). An edit that moves the
    /// billing sequence earlier REWINDS to the earliest affected date, floored
    /// at the earliest ledger row ever created (tombstones included - tracking
    /// began there, and an edit must not manufacture pre-entry history); the
    /// rewind runs BEFORE the save so a crash between the two lands on the
    /// harmless side, a regressed watermark. A new entry INITIALISES at the
    /// later of the anchor and today, after its record exists (a crash between
    /// leaves a nil watermark, whose first pass observes from today - the same
    /// window the initialisation would have granted a same-day entry). Neither
    /// operation can advance a watermark; only a ledger pass does that.
    public func save(_ subscription: Subscription) async throws {
        if let current = try await subscriptionRepository.subscription(withID: subscription.id) {
            let earliestTracked = try await billingEventRepository
                .eventsIncludingDeleted(forSubscription: subscription.id)
                .map(\.expectedDate)
                .min()
            let stored = try await billingEventRepository
                .materializationWatermark(forSubscription: subscription.id)
            if let target = watermarkAfterEdit(
                from: current,
                to: subscription,
                stored: stored,
                trackedSince: earliestTracked,
                asOf: dates.today()
            ) {
                try await billingEventRepository.rewindMaterializationWatermark(
                    forSubscription: subscription.id, to: target
                )
            }
            try await subscriptionRepository.save(subscription)
        } else {
            try await subscriptionRepository.save(subscription)
            try await billingEventRepository.initializeMaterializationWatermark(
                forSubscription: subscription.id,
                at: max(subscription.cycleStartDay, dates.today())
            )
        }
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
