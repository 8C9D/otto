// The withdrawal half of F8 / R0-10(b), split out of SettingsExportTests.swift
// when the guards `reviews-4/REVIEW-4.md` finding 1 asked for pushed that file
// past SwiftLint's 400-line `file_length` and 250-line `type_body_length`. The
// seam is the obvious one: that file asks what gets BUILT and when, this one
// asks what stops being offered once the data changes.
//
// The fixtures are shared from SettingsExportTests.swift, which is why the
// spies there lost `private`.
#if canImport(UIKit)
import Foundation
import OttoDomain
import OttoRepositories
import OttoServices
import OttoStores
import Testing
@testable import OttoUI

@MainActor
@Suite("A prepared export stops being offered once the data changes (R0-10(b))")
struct SettingsExportWithdrawalTests {

    private static let today = CalendarDay(year: 2026, month: 8, day: 12)

    private func makeModel(
        transfer: CountingTransfer, client: CountingClient, suite: String, today: CalendarDay,
        withNotifications: Bool = true
    ) -> AppModel {
        let repository = PreviewRepository()
        return AppModel(
            repositories: AppModel.Repositories(
                subscriptions: repository, billingEvents: repository,
                cancellations: repository, priceChanges: repository,
                paymentMethods: repository, transfer: transfer
            ),
            notifications: withNotifications
                ? NotificationStatusStore(
                    scheduler: IdleScheduler(), client: client, dates: .fixed(today: today)
                )
                : nil,
            settings: SettingsStore(userDefaults: UserDefaults(suiteName: suite) ?? .standard),
            dates: .fixed(today: today)
        )
    }

    private func settle(
        upTo attempts: Int = 400, until condition: @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< attempts {
            if await condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    /// The other half of the same staleness, on the path a user takes far more
    /// often than an import: editing or deleting a subscription. The prepared
    /// file describes the database before the edit.
    @Test("⛔ deleting a subscription withdraws every export prepared before it")
    func aMutationWithdrawsAPreparedExport() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.4",
            today: try #require(Self.today)
        )

        try await model.prepareExport(.json)
        #expect(model.preparedExport(.json) != nil)

        await model.subscriptionsStore.refresh()
        let loaded = try #require(model.subscriptionsStore.subscriptions.value)
        let victim = try #require(loaded.first)
        try await model.subscriptionsStore.delete(subscriptionID: victim.id)

        #expect(model.preparedExport(.json) == nil)
    }

    /// ⛔ The hook itself, on the model shape that used to skip it.
    ///
    /// `subscriptionsStore.onMutation` was installed only inside
    /// `if let notifications`, so "the data changed" was observable only on a
    /// model that could schedule reminders. The suite's other tests all build a
    /// model WITH a notification store, so re-wrapping the wiring in that
    /// condition left every one of them green - `reviews-4/REVIEW-1.md`
    /// finding 5 measured it. This is the model the condition excluded.
    @Test("⛔ a model with no notification engine still withdraws on a mutation")
    func theHookIsWiredWithoutANotificationEngine() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.5",
            today: try #require(Self.today), withNotifications: false
        )
        #expect(model.notifications == nil)

        try await model.prepareExport(.json)
        #expect(model.preparedExport(.json) != nil)

        await model.subscriptionsStore.refresh()
        let loaded = try #require(model.subscriptionsStore.subscriptions.value)
        try await model.subscriptionsStore.delete(subscriptionID: try #require(loaded.first).id)

        #expect(model.preparedExport(.json) == nil)
    }

    /// ⛔ Payment methods are a stored collection of the JSON backup, and that
    /// store had no mutation hook at all. `reviews-4/REVIEW-1.md` finding 2
    /// demonstrated the stale file still on offer after a card was saved.
    @Test("⛔ saving a payment method withdraws a prepared export")
    func aPaymentMethodWriteWithdraws() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.6",
            today: try #require(Self.today)
        )

        try await model.prepareExport(.json)
        #expect(model.preparedExport(.json) != nil)

        try await model.paymentMethodsStore.save(
            PaymentMethod(
                id: UUID(), label: "Visa", last4: "4242", issuer: "Visa",
                expiryMonth: 6, expiryYear: 2030, isDefault: false,
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0)
            )
        )

        #expect(model.preparedExport(.json) == nil)
    }

    /// ⛔ A withdrawal that lands while a build is suspended must win.
    ///
    /// `prepareExport` awaits the export actor, so a `flowFinished()` or a
    /// mutation is free to run in the gap and the assignment afterwards would
    /// re-offer a file built from the older snapshot - the same staleness,
    /// relocated (`reviews-4/REVIEW-1.md` finding 3). Export and Import are rows
    /// on the same screen, so this is reachable by hand.
    @Test("⛔ a withdrawal during an in-flight build is not overwritten by it")
    func aWithdrawalDuringABuildWins() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.7",
            today: try #require(Self.today)
        )

        await transfer.hold()
        let build = Task { try await model.prepareExport(.json) }
        // The build is suspended inside `completeSnapshot()`.
        _ = await settle { await transfer.waiting > 0 }
        #expect(model.exportAvailability(.json) == .preparing)

        model.withdrawPreparedExports()
        await transfer.release()
        _ = try await build.value

        #expect(model.preparedExport(.json) == nil)
        #expect(model.exportAvailability(.json) == .notPrepared)
    }

    /// ⛔ The `catch` branch's generation guard - the only production
    /// behaviour change in the remediation range, and the one thing in it that
    /// `reviews-4/REVIEW-6.md` could delete with the whole simulator suite
    /// green. A failure recorded against a database that has since changed is
    /// as stale as a file built from it, and showing the user an error about
    /// data they have already replaced is the same defect as offering them a
    /// file built from it.
    @Test("⛔ a withdrawal during a build that FAILS also discards the failure")
    func aWithdrawalDuringAFailingBuildDiscardsTheFailure() async throws {
        let transfer = CountingTransfer()
        await transfer.fail()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.13",
            today: try #require(Self.today)
        )

        await transfer.hold()
        let build = Task { try await model.prepareExport(.json) }
        _ = await settle { await transfer.waiting > 0 }
        #expect(model.exportAvailability(.json) == .preparing)

        model.withdrawPreparedExports()
        await transfer.release()
        await #expect(throws: (any Error).self) { try await build.value }

        // The build failed AFTER the withdrawal, so its failure describes a
        // database that no longer exists.
        #expect(model.exportAvailability(.json) == .notPrepared)
    }
}
#endif
