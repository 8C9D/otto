import Foundation

/// Everything the store holds, as domain values - tombstones included, because
/// a soft-deleted row is communicable data (spec §3.5) and a backup that drops
/// it is not a backup. Export reads one of these; import resolves into one and
/// the persistence layer applies it atomically.
public struct OttoDataSnapshot: Hashable, Sendable {
    public var subscriptions: [Subscription]
    public var paymentMethods: [PaymentMethod]
    public var billingEvents: [BillingEvent]
    public var cancellationRecords: [CancellationRecord]
    public var priceChanges: [PriceChange]

    public init(
        subscriptions: [Subscription] = [],
        paymentMethods: [PaymentMethod] = [],
        billingEvents: [BillingEvent] = [],
        cancellationRecords: [CancellationRecord] = [],
        priceChanges: [PriceChange] = []
    ) {
        self.subscriptions = subscriptions
        self.paymentMethods = paymentMethods
        self.billingEvents = billingEvents
        self.cancellationRecords = cancellationRecords
        self.priceChanges = priceChanges
    }

    public var isEmpty: Bool {
        subscriptions.isEmpty && paymentMethods.isEmpty && billingEvents.isEmpty
            && cancellationRecords.isEmpty && priceChanges.isEmpty
    }
}
