import Foundation
import Observation
import OttoDomain
import OttoRepositories

/// The app's shared model graph, created once at the composition root with the
/// concrete repositories and handed to the view tree. Everything downstream sees
/// repository protocols and domain values only.
@MainActor
@Observable
public final class AppModel {

    /// The five repositories, as protocols. The composition root fills this with
    /// the persistence implementations; previews and tests fill it with mocks.
    public struct Repositories: Sendable {
        public var subscriptions: any SubscriptionRepository
        public var billingEvents: any BillingEventRepository
        public var cancellations: any CancellationRepository
        public var priceChanges: any PriceChangeRepository
        public var paymentMethods: any PaymentMethodRepository

        public init(
            subscriptions: any SubscriptionRepository,
            billingEvents: any BillingEventRepository,
            cancellations: any CancellationRepository,
            priceChanges: any PriceChangeRepository,
            paymentMethods: any PaymentMethodRepository
        ) {
            self.subscriptions = subscriptions
            self.billingEvents = billingEvents
            self.cancellations = cancellations
            self.priceChanges = priceChanges
            self.paymentMethods = paymentMethods
        }
    }

    public let subscriptionsStore: SubscriptionsStore
    public let paymentMethodsStore: PaymentMethodsStore
    public let dates: DateProvider

    private let repositories: Repositories

    public init(repositories: Repositories, dates: DateProvider = .live) {
        self.repositories = repositories
        self.dates = dates
        self.subscriptionsStore = SubscriptionsStore(
            subscriptionRepository: repositories.subscriptions,
            cancellationRepository: repositories.cancellations,
            dates: dates
        )
        self.paymentMethodsStore = PaymentMethodsStore(repository: repositories.paymentMethods)
    }

    /// A fresh detail store for one subscription's screen.
    public func detailStore(for subscriptionID: UUID) -> SubscriptionDetailStore {
        SubscriptionDetailStore(
            subscriptionID: subscriptionID,
            subscriptionRepository: repositories.subscriptions,
            billingEventRepository: repositories.billingEvents,
            cancellationRepository: repositories.cancellations,
            priceChangeRepository: repositories.priceChanges,
            paymentMethodRepository: repositories.paymentMethods
        )
    }

    /// A form model for adding (nil) or editing.
    public func formModel(editing subscription: Subscription? = nil) -> SubscriptionFormModel {
        if let subscription {
            SubscriptionFormModel(editing: subscription, dates: dates)
        } else {
            SubscriptionFormModel(dates: dates)
        }
    }
}
