import Foundation
import Observation
import OttoDomain
import OttoRepositories
import OttoServices

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
    /// Permission and coverage state (Wave 4). Nil in previews and store tests
    /// that construct the model without a notification engine.
    public let notifications: NotificationStatusStore?
    public let dates: DateProvider

    /// A subscription the notification layer asked the UI to show - a tap on a
    /// notification, or an "I'm cancelling" follow-up. The root view presents it
    /// and clears it.
    public var requestedSubscriptionID: UUID?

    private let repositories: Repositories

    public init(
        repositories: Repositories,
        notifications: NotificationStatusStore? = nil,
        dates: DateProvider = .live
    ) {
        self.repositories = repositories
        self.notifications = notifications
        self.dates = dates
        self.subscriptionsStore = SubscriptionsStore(
            subscriptionRepository: repositories.subscriptions,
            cancellationRepository: repositories.cancellations,
            dates: dates
        )
        self.paymentMethodsStore = PaymentMethodsStore(repository: repositories.paymentMethods)
        if let notifications {
            // Every create, edit, or delete is a reschedule trigger (spec §6.2).
            self.subscriptionsStore.onMutation = { [weak notifications] in
                await notifications?.reschedule()
            }
        }
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
