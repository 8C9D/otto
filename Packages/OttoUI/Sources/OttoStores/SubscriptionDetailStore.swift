import Foundation
import Observation
import OttoDomain
import OttoRepositories

/// Everything the Detail screen shows for one subscription, loaded together.
public struct SubscriptionDetail: Sendable {
    public var subscription: Subscription
    public var events: [BillingEvent]
    public var priceHistory: [PriceChange]
    public var cancellation: CancellationEpisode?
    public var paymentMethod: PaymentMethod?

    public init(
        subscription: Subscription,
        events: [BillingEvent],
        priceHistory: [PriceChange],
        cancellation: CancellationEpisode?,
        paymentMethod: PaymentMethod?
    ) {
        self.subscription = subscription
        self.events = events
        self.priceHistory = priceHistory
        self.cancellation = cancellation
        self.paymentMethod = paymentMethod
    }
}

/// The observable state behind the Detail screen - one subscription with its
/// ledger, price history, cancellation record, and payment method.
@MainActor
@Observable
public final class SubscriptionDetailStore {
    /// The subscription vanished between navigation and load - deleted elsewhere.
    /// Its own case so the view can distinguish "gone" from "broken".
    public enum DetailError: Error {
        case subscriptionNotFound(UUID)
    }

    public private(set) var state: LoadState<SubscriptionDetail> = .loading

    public let subscriptionID: UUID
    private let subscriptionRepository: any SubscriptionRepository
    private let billingEventRepository: any BillingEventRepository
    private let cancellationRepository: any CancellationRepository
    private let priceChangeRepository: any PriceChangeRepository
    private let paymentMethodRepository: any PaymentMethodRepository

    public init(
        subscriptionID: UUID,
        subscriptionRepository: any SubscriptionRepository,
        billingEventRepository: any BillingEventRepository,
        cancellationRepository: any CancellationRepository,
        priceChangeRepository: any PriceChangeRepository,
        paymentMethodRepository: any PaymentMethodRepository
    ) {
        self.subscriptionID = subscriptionID
        self.subscriptionRepository = subscriptionRepository
        self.billingEventRepository = billingEventRepository
        self.cancellationRepository = cancellationRepository
        self.priceChangeRepository = priceChangeRepository
        self.paymentMethodRepository = paymentMethodRepository
    }

    public func refresh() async {
        do {
            guard let subscription = try await subscriptionRepository.subscription(withID: subscriptionID) else {
                state = .failed(DetailError.subscriptionNotFound(subscriptionID))
                return
            }
            let events = try await billingEventRepository.events(forSubscription: subscriptionID)
            let history = try await priceChangeRepository.history(forSubscription: subscriptionID)
            let cancellation = try await cancellationRepository.openEpisode(forSubscription: subscriptionID)
            var paymentMethod: PaymentMethod?
            if let paymentMethodID = subscription.paymentMethodID {
                paymentMethod = try await paymentMethodRepository.paymentMethod(withID: paymentMethodID)
            }
            state = .loaded(SubscriptionDetail(
                subscription: subscription,
                events: events,
                priceHistory: history,
                cancellation: cancellation,
                paymentMethod: paymentMethod
            ))
        } catch {
            state = .failed(error)
        }
    }
}
