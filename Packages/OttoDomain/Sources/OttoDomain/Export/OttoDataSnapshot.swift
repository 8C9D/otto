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

    /// True when nothing here is live, tombstones notwithstanding.
    ///
    /// `isEmpty` asks whether the snapshot holds any record at all, which is
    /// the right question for "is there anything to merge WITH" - a tombstone
    /// is communicable data and a replace treats it differently from a merge.
    /// It is the wrong question for "does this device have ledger progress
    /// worth keeping": a database whose every record is tombstoned has none,
    /// and it is not `isEmpty`, so the import prompt appeared and answering
    /// Merge left every watermark nil - materializing from TODAY and losing
    /// every row back to the file's last charge, which is F6 exactly.
    public var hasNoLiveRecords: Bool {
        !subscriptions.contains { $0.deletedAt == nil }
            && !paymentMethods.contains { $0.deletedAt == nil }
            && !billingEvents.contains { $0.deletedAt == nil }
            && !cancellationEpisodes.contains { $0.deletedAt == nil }
            && !priceChanges.contains { $0.deletedAt == nil }
    }
}
