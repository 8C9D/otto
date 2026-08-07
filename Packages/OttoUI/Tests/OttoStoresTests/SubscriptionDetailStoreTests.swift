import Foundation
import Testing
import OttoDomain
@testable import OttoStores

@MainActor
@Suite("SubscriptionDetailStore")
struct SubscriptionDetailStoreTests {

    private struct Mocks {
        let subscriptions = MockSubscriptionRepository()
        let billingEvents = MockBillingEventRepository()
        let cancellations = MockCancellationRepository()
        let priceChanges = MockPriceChangeRepository()
        let paymentMethods = MockPaymentMethodRepository()

        @MainActor
        func store(for subscriptionID: UUID) -> SubscriptionDetailStore {
            SubscriptionDetailStore(
                subscriptionID: subscriptionID,
                subscriptionRepository: subscriptions,
                billingEventRepository: billingEvents,
                cancellationRepository: cancellations,
                priceChangeRepository: priceChanges,
                paymentMethodRepository: paymentMethods
            )
        }
    }

    @Test("loads the subscription with its ledger, history, record, and payment method")
    func loadsAggregate() async throws {
        let mocks = Mocks()
        let method = PaymentMethod(
            id: try fixtureUUID(300), label: "Bank ..4821", last4: "4821", issuer: "Bank",
            expiryMonth: 11, expiryYear: 2027, isDefault: true,
            createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let subscription = try makeSubscription(
            index: 1, status: .cancelled, cycleStartDay: try day(2026, 5, 20), paymentMethodID: method.id
        )
        let event = BillingEvent(
            id: try fixtureUUID(100), subscriptionID: subscription.id,
            expectedDate: try day(2026, 6, 20), expectedAmountCents: 1099, state: .confirmedCharged,
            createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let change = PriceChange(
            id: try fixtureUUID(200), subscriptionID: subscription.id,
            effectiveDate: try day(2026, 6, 1), oldAmountCents: 999, newAmountCents: 1099,
            source: .userEdit,
            createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let record = try makeCancellationRecord(
            subscriptionID: subscription.id, nextChargeDateIfNotCancelled: try day(2026, 8, 20)
        )
        await mocks.subscriptions.seed([subscription])
        await mocks.billingEvents.seed([event])
        await mocks.priceChanges.seed([change])
        await mocks.cancellations.seed([record])
        await mocks.paymentMethods.seed([method])

        let store = mocks.store(for: subscription.id)
        #expect(store.state.isLoading)
        await store.refresh()

        let detail = try #require(store.state.value)
        #expect(detail.subscription == subscription)
        #expect(detail.events == [event])
        #expect(detail.priceHistory == [change])
        #expect(detail.cancellation == record)
        #expect(detail.paymentMethod == method)
    }

    @Test("a missing subscription is its own failure, distinct from a broken load")
    func notFound() async throws {
        let mocks = Mocks()
        let store = mocks.store(for: try fixtureUUID(9))

        await store.refresh()

        guard case .some(SubscriptionDetailStore.DetailError.subscriptionNotFound(let id)) =
            store.state.error as? SubscriptionDetailStore.DetailError
        else {
            Issue.record("expected subscriptionNotFound, got \(String(describing: store.state.error))")
            return
        }
        #expect(id == (try fixtureUUID(9)))
    }

    @Test("a repository error surfaces as failed")
    func errorSurfaces() async throws {
        let mocks = Mocks()
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 5, 20))
        await mocks.subscriptions.seed([subscription])
        await mocks.billingEvents.fail(with: TestFailure())

        let store = mocks.store(for: subscription.id)
        await store.refresh()

        #expect(store.state.error is TestFailure)
    }
}
