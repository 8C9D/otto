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

    /// The repositories, as protocols. The composition root fills this with
    /// the persistence implementations; previews and tests fill it with mocks.
    public struct Repositories: Sendable {
        public var subscriptions: any SubscriptionRepository
        public var billingEvents: any BillingEventRepository
        public var cancellations: any CancellationRepository
        public var priceChanges: any PriceChangeRepository
        public var paymentMethods: any PaymentMethodRepository
        /// The whole-database seam export/import runs over (Wave 8).
        public var transfer: any DataTransferRepository

        public init(
            subscriptions: any SubscriptionRepository,
            billingEvents: any BillingEventRepository,
            cancellations: any CancellationRepository,
            priceChanges: any PriceChangeRepository,
            paymentMethods: any PaymentMethodRepository,
            transfer: any DataTransferRepository
        ) {
            self.subscriptions = subscriptions
            self.billingEvents = billingEvents
            self.cancellations = cancellations
            self.priceChanges = priceChanges
            self.paymentMethods = paymentMethods
            self.transfer = transfer
        }
    }

    public let subscriptionsStore: SubscriptionsStore
    public let insightsStore: InsightsStore
    public let paymentMethodsStore: PaymentMethodsStore
    /// Permission and coverage state (Wave 4). Nil in previews and store tests
    /// that construct the model without a notification engine.
    public let notifications: NotificationStatusStore?
    /// The Wave 5 flows - trial confirmation, cancellation, verification. Built
    /// over the same repositories, so the screens and the notification actions
    /// share one implementation of every state change.
    public let flows: SubscriptionFlowService
    /// Export and import (Wave 8) - the CloudKit escape hatch.
    public let exports: ExportService
    /// The user's settings (Wave 8).
    public let settings: SettingsStore
    public let dates: DateProvider

    /// A subscription the notification layer asked the UI to show - a tap on a
    /// notification, or an "I'm cancelling" follow-up. The root view presents it
    /// and clears it.
    public var requestedSubscriptionID: UUID?

    private let repositories: Repositories

    public init(
        repositories: Repositories,
        notifications: NotificationStatusStore? = nil,
        settings: SettingsStore? = nil,
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
        self.exports = ExportService(transfer: repositories.transfer)
        self.settings = settings ?? SettingsStore()
        self.dates = dates
        self.subscriptionsStore = SubscriptionsStore(
            subscriptionRepository: repositories.subscriptions,
            cancellationRepository: repositories.cancellations,
            billingEventRepository: repositories.billingEvents,
            dates: dates
        )
        self.insightsStore = InsightsStore(
            subscriptionRepository: repositories.subscriptions,
            priceChangeRepository: repositories.priceChanges,
            dates: dates
        )
        self.paymentMethodsStore = PaymentMethodsStore(
            repository: repositories.paymentMethods, dates: dates
        )
        if let notifications {
            // Every create, edit, or delete is a reschedule trigger (spec §6.2).
            self.subscriptionsStore.onMutation = { [weak notifications] in
                await notifications?.reschedule()
            }
            // So is a notification-time change: every pending reminder re-times.
            self.settings.onReminderTimeChange = { [weak notifications] in
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
        await insightsStore.refresh()
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

    /// Records that the user used this subscription today (spec §7.3) - the
    /// fact zombie detection counts from.
    public func recordUsage(subscriptionID: UUID) async throws {
        try await flows.recordUsage(
            subscriptionID: subscriptionID, on: dates.today(), now: dates.now()
        )
        await flowFinished()
    }

    /// Pauses billing (spec §5.1), recording the freeze point and the resume
    /// date when the vendor gave one.
    public func pauseSubscription(subscriptionID: UUID, resumesOn: CalendarDay?) async throws {
        try await flows.pause(
            subscriptionID: subscriptionID, resumesOn: resumesOn,
            now: dates.now(), today: dates.today()
        )
        await flowFinished()
    }

    /// Resumes billing, closing the pause episode with its actual end day -
    /// also the manual path out of an indefinite pause, which backfills the
    /// frozen watermark's gap on the next scheduler pass.
    public func resumeSubscription(subscriptionID: UUID) async throws {
        try await flows.resume(subscriptionID: subscriptionID, now: dates.now(), today: dates.today())
        await flowFinished()
    }

    /// The un-cancel (spec §5.4, §5.3a): closes the open cancellation episode
    /// as `.abandoned` - kept as history, never deleted - and returns the
    /// subscription to the status the cancellation interrupted.
    public func abandonCancellation(subscriptionID: UUID) async throws {
        try await flows.abandonCancellation(
            subscriptionID: subscriptionID, now: dates.now(), today: dates.today()
        )
        await flowFinished()
    }

    /// Supplies the resume date a deferred verification was waiting on
    /// (spec §5.4): an indefinitely paused subscription was cancelled, Otto
    /// refused to fabricate a check date, and this is the user providing the
    /// real one.
    public func supplyPausedResumeDate(subscriptionID: UUID, resumeDate: CalendarDay) async throws {
        try await flows.supplyPausedResumeDate(
            subscriptionID: subscriptionID, resumeDate: resumeDate, now: dates.now()
        )
        await flowFinished()
    }

    /// Adds evidence captured after the fact - the confirmation number the
    /// vendor page produced once the cancellation actually happened, or the
    /// next artifact of a long fight (spec §5.4, a list since v1.9).
    public func appendCancellationEvidence(subscriptionID: UUID, text: String) async throws {
        try await flows.appendCancellationEvidence(
            subscriptionID: subscriptionID, text: text, now: dates.now()
        )
        await subscriptionsStore.refresh()
    }

    /// Edits (or, with empty text, tombstones) one existing evidence note.
    public func updateCancellationEvidence(subscriptionID: UUID, noteID: UUID, text: String?) async throws {
        try await flows.updateCancellationEvidence(
            subscriptionID: subscriptionID, noteID: noteID, text: text, now: dates.now()
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

    // MARK: - Export and import (Wave 8)

    /// The full-fidelity JSON export, as a shareable file URL.
    public func exportJSONFile() async throws -> URL {
        try await exports.exportJSONFile(exportedAt: dates.now(), today: dates.today())
    }

    /// The one-way charges CSV, as a shareable file URL.
    public func exportChargesCSVFile() async throws -> URL {
        try await exports.exportChargesCSVFile(today: dates.today())
    }

    /// What an import of `url` would bring, and whether the merge-or-replace
    /// question even arises. Touches nothing.
    public func importPreview(from url: URL) async throws -> ImportPreview {
        try await exports.importPreview(from: url)
    }

    /// Runs the import, then treats it as the large mutation it is: reschedule
    /// (which also materializes the imported subscriptions' ledgers) and
    /// refresh every published list.
    public func importData(from url: URL, strategy: ImportStrategy) async throws -> ImportSummary {
        let summary = try await exports.performImport(from: url, strategy: strategy, now: dates.now())
        await flowFinished()
        await paymentMethodsStore.refresh()
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

    /// A form model for adding (nil) or editing, seeded with the settings
    /// screen's defaults (Wave 8).
    public func formModel(editing subscription: Subscription? = nil) -> SubscriptionFormModel {
        if let subscription {
            SubscriptionFormModel(
                editing: subscription, dates: dates, reminderDefaults: settings.reminderDefaults
            )
        } else {
            SubscriptionFormModel(dates: dates, reminderDefaults: settings.reminderDefaults)
        }
    }

    /// A payment-method form model for adding (nil) or editing (spec §5.5).
    public func paymentMethodFormModel(editing method: PaymentMethod? = nil) -> PaymentMethodFormModel {
        if let method {
            PaymentMethodFormModel(editing: method, dates: dates)
        } else {
            PaymentMethodFormModel(dates: dates)
        }
    }
}
