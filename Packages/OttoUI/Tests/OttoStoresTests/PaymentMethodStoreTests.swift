import Foundation
import OttoDomain
import Testing
@testable import OttoStores

// Payment methods (spec §5.5): the form model that makes inline creation cheap,
// and the store rules the management screen relies on.

@Suite("The payment-method form (spec §5.5)")
@MainActor
struct PaymentMethodFormModelTests {

    @Test("a label plus last4 is enough - the cheap inline path builds")
    func minimalFormBuilds() throws {
        let form = PaymentMethodFormModel(dates: try fixedDates())
        form.label = "Bank Mastercard"
        form.last4 = "4821"

        let method = try #require(form.buildPaymentMethod())
        #expect(method.label == "Bank Mastercard")
        #expect(method.last4 == "4821")
        #expect(form.canSave)
    }

    @Test("with no label typed, issuer and digits suggest one - the list stays readable")
    func suggestedLabel() throws {
        let form = PaymentMethodFormModel(dates: try fixedDates())
        form.issuer = "Bank"
        form.last4 = "4821"

        #expect(form.suggestedLabel == "Bank ••4821")
        #expect(form.buildPaymentMethod()?.label == "Bank ••4821")
    }

    @Test("an empty form and a malformed last4 do not build")
    func validation() throws {
        let empty = PaymentMethodFormModel(dates: try fixedDates())
        #expect(!empty.canSave)

        let malformed = PaymentMethodFormModel(dates: try fixedDates())
        malformed.label = "Card"
        malformed.last4 = "48"
        #expect(!malformed.canSave)
        malformed.last4 = "48x1"
        #expect(!malformed.canSave)
        malformed.last4 = "4821"
        #expect(malformed.canSave)
        // Digits are optional outright - a label alone is a valid card.
        malformed.last4 = ""
        #expect(malformed.canSave)
    }

    @Test("editing keeps the identity and createdAt; the blank form defaults the expiry three years out")
    func identityAndDefaults() throws {
        let dates = try fixedDates()
        let blank = PaymentMethodFormModel(dates: dates)
        #expect(blank.expiryYear == 2029)
        #expect(blank.expiryMonth == 8)

        blank.label = "Card"
        let created = try #require(blank.buildPaymentMethod())
        let edit = PaymentMethodFormModel(editing: created, dates: dates)
        edit.label = "Renamed"
        let updated = try #require(edit.buildPaymentMethod())
        #expect(updated.id == created.id)
        #expect(updated.createdAt == created.createdAt)
    }
}

@Suite("The payment-methods store (spec §5.5)")
@MainActor
struct PaymentMethodsStoreTests {

    private func makeMethod(index: Int, label: String, isDefault: Bool = false) throws -> PaymentMethod {
        PaymentMethod(
            id: try fixtureUUID(index),
            label: label,
            last4: "0000",
            issuer: "Bank",
            expiryMonth: 12,
            expiryYear: 2029,
            isDefault: isDefault,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    @Test("saving keeps the list fresh - the inline path's new card is immediately pickable")
    func inlineCreationLandsInList() async throws {
        let repository = MockPaymentMethodRepository()
        let store = PaymentMethodsStore(repository: repository, dates: try fixedDates())
        await store.refresh()
        #expect(store.state.value == [])

        let form = PaymentMethodFormModel(dates: try fixedDates())
        form.issuer = "Bank"
        form.last4 = "4821"
        let method = try #require(form.buildPaymentMethod())
        try await store.save(method)

        #expect(store.state.value?.map(\.label) == ["Bank ••4821"])

        // And a subscription form can carry it - the inline selection.
        let subscriptionForm = SubscriptionFormModel(dates: try fixedDates())
        subscriptionForm.name = "Netflix"
        subscriptionForm.amount = 18.99
        subscriptionForm.paymentMethodID = method.id
        #expect(subscriptionForm.buildSubscription()?.paymentMethodID == method.id)
    }

    @Test("marking a card default unmarks every other - default stays singular")
    func defaultStaysSingular() async throws {
        let repository = MockPaymentMethodRepository()
        await repository.seed([
            try makeMethod(index: 901, label: "Old default", isDefault: true),
            try makeMethod(index: 902, label: "Other")
        ])
        let store = PaymentMethodsStore(repository: repository, dates: try fixedDates())

        var newDefault = try makeMethod(index: 903, label: "New default", isDefault: true)
        newDefault.updatedAt = Date(timeIntervalSince1970: 9_000)
        try await store.save(newDefault)

        let defaults = try #require(store.state.value).filter(\.isDefault)
        #expect(defaults.map(\.label) == ["New default"])
    }

    @Test("deleting soft-deletes and refreshes; the list no longer shows the card")
    func deleteRemovesFromList() async throws {
        let repository = MockPaymentMethodRepository()
        let method = try makeMethod(index: 901, label: "Card")
        await repository.seed([method])
        let store = PaymentMethodsStore(repository: repository, dates: try fixedDates())

        try await store.delete(paymentMethodID: method.id)

        #expect(store.state.value == [])
        // Soft delete: the tombstone remains for sync (spec §3.5).
        #expect(try await repository.paymentMethodsIncludingDeleted().count == 1)
    }
}
