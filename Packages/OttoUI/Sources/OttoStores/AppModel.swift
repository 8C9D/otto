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
    /// The Wave 5 flows - trial confirmation, cancellation, verification. Built
    /// over the same repositories, so the screens and the notification actions
    /// share one implementation of every state change.
    public let flows: SubscriptionFlowService
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
        self.flows = SubscriptionFlowService(
            subscriptions: repositories.subscriptions,
            cancellations: repositories.cancellations,
            billingEvents: repositories.billingEvents,
            priceChanges: repositories.priceChanges
        )
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

    // MARK: - Wave 5 flows

    /// Every flow method runs the state work, then reschedules (a state change
    /// is a §6.2 trigger) and refreshes the published lists so every screen
    /// reflects it.
    private func flowFinished() async {
        await notifications?.reschedule()
        await subscriptionsStore.refresh()
    }

    /// The user confirmed they know the trial converted (spec §5.2a): records,
    /// never deletes, and the Needs-action card retires because the stored state
    /// now says what the derivation said.
    public func confirmTrialConversion(subscriptionID: UUID) async throws {
        try await flows.confirmTrialConversion(
            subscriptionID: subscriptionID, now: dates.now(), today: dates.today()
        )
        await flowFinished()
    }

    /// "Keeping it" from a screen: same acknowledgement the notification action
    /// writes (spec §6.4).
    public func keepCurrentCharge(subscriptionID: UUID) async throws {
        try await flows.acknowledgeCurrentCharge(
            subscriptionID: subscriptionID, now: dates.now(), today: dates.today()
        )
        await flowFinished()
    }

    /// Marks the subscription cancelling (spec §5.4) - same state work as the
    /// notification action, plus whatever evidence the screen captured.
    @discardableResult
    public func startCancellation(
        subscriptionID: UUID, evidenceNote: String?
    ) async throws -> CancellationStart? {
        let start = try await flows.startCancellation(
            subscriptionID: subscriptionID,
            evidenceNote: evidenceNote,
            now: dates.now(),
            today: dates.today()
        )
        await flowFinished()
        return start
    }

    /// Saves the evidence captured after the fact - the confirmation number the
    /// vendor page produced once the cancellation actually happened.
    public func updateCancellationEvidence(subscriptionID: UUID, note: String?) async throws {
        try await flows.updateCancellationEvidence(
            subscriptionID: subscriptionID, note: note, now: dates.now()
        )
        await subscriptionsStore.refresh()
    }

    /// Answers a verification check (spec §5.4). Returns the dispute summary on
    /// the no-path; nil on the yes-path, which archives.
    public func answerVerification(
        subscriptionID: UUID, chargesStopped: Bool
    ) async throws -> DisputeSummary? {
        let summary = try await flows.answerVerification(
            subscriptionID: subscriptionID,
            chargesStopped: chargesStopped,
            now: dates.now(),
            today: dates.today()
        )
        await flowFinished()
        return summary
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
