import Foundation

/// Everything the store holds, as domain values - tombstones included, because
/// a soft-deleted row is communicable data (spec §3.5) and a backup that drops
/// it is not a backup. Export reads one of these; import resolves into one and
/// the persistence layer applies it atomically.
public struct OttoDataSnapshot: Hashable, Sendable {
    public var subscriptions: [Subscription]
    public var paymentMethods: [PaymentMethod]
    public var billingEvents: [BillingEvent]
    public var cancellationEpisodes: [CancellationEpisode]
    public var priceChanges: [PriceChange]

    public init(
        subscriptions: [Subscription] = [],
        paymentMethods: [PaymentMethod] = [],
        billingEvents: [BillingEvent] = [],
        cancellationEpisodes: [CancellationEpisode] = [],
        priceChanges: [PriceChange] = []
    ) {
        self.subscriptions = subscriptions
        self.paymentMethods = paymentMethods
        self.billingEvents = billingEvents
        self.cancellationEpisodes = cancellationEpisodes
        self.priceChanges = priceChanges
    }

    public var isEmpty: Bool {
        subscriptions.isEmpty && paymentMethods.isEmpty && billingEvents.isEmpty
            && cancellationEpisodes.isEmpty && priceChanges.isEmpty
    }

    /// True when no subscription here is live - i.e. this device has no ledger
    /// progress worth keeping.
    ///
    /// `isEmpty` asks whether the snapshot holds any record at all, which is
    /// the right question for "is there anything to merge WITH" - a tombstone
    /// is communicable data and a replace treats it differently from a merge.
    /// It is the wrong question for the watermark policy: a database whose
    /// subscriptions are all tombstoned has no progress to keep, and it is not
    /// `isEmpty`, so the import prompt appeared and answering Merge left every
    /// watermark nil - materializing from TODAY and losing every row back to
    /// the file's last charge, which is F6 exactly.
    ///
    /// Subscriptions, and only subscriptions, because **a watermark is
    /// per-subscription**: nothing else in a snapshot can carry ledger
    /// progress. Requiring every record type to be tombstoned instead would
    /// miss the state a user actually reaches - `deleteSubscription` cascades
    /// to trials, episodes, billing events and price changes but NOT to
    /// payment methods, which are not children of a subscription, so a device
    /// that deleted every subscription and kept its card would still have
    /// answered "something is live" and still lost its watermarks.
    public var hasNoLiveSubscriptions: Bool {
        !subscriptions.contains { $0.deletedAt == nil }
    }
}
