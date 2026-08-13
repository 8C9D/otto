// F8 / R0-10(b), at the only level where the defect exists: a rendered
// Settings screen. UIKit-hosted, so this file runs on the simulator and
// compiles to nothing under `swift test` on a mac host.
//
// The defect is not in `ExportService` - that actor writes a file when it is
// told to, which is its job. It is in WHO tells it: `ExportSection` carried
// `.task { await regenerate() }`, so merely arriving on Settings wrote the
// complete unencrypted JSON backup and the charge CSV into the temporary
// directory, for a user who had asked for neither. Measured at `2d8913c`
// before the fix, by this test: 2 `completeSnapshot()` calls and two files on
// disk from an appearance alone.
//
// R0-10(b) is the same state seen a moment later: those URLs live in `@State`
// for as long as the screen does, so the `ShareLink` beside them keeps handing
// out the PRE-IMPORT file after an import has replaced the database.
#if canImport(UIKit)
import Foundation
import OttoDomain
import OttoRepositories
import OttoServices
import OttoStores
import SwiftUI
import Testing
import UIKit
@testable import OttoUI

/// Counts the reads an export performs. `completeSnapshot()` is the first
/// `await` in both export paths, so this counter moves as soon as either one
/// starts - it cannot miss a write that began and had not finished.
private actor CountingTransfer: DataTransferRepository {
    private(set) var snapshotCalls = 0
    /// Set by `hold()`: the next `completeSnapshot()` parks here until
    /// `release()`, so a test can make something happen while a build is
    /// genuinely suspended rather than hoping for an interleaving.
    private var gate: CheckedContinuation<Void, Never>?
    private var holding = false
    private(set) var isWaiting = false

    func hold() { holding = true }

    func release() {
        holding = false
        gate?.resume()
        gate = nil
        isWaiting = false
    }

    func completeSnapshot() async throws -> OttoDataSnapshot {
        snapshotCalls += 1
        if holding {
            isWaiting = true
            await withCheckedContinuation { continuation in
                gate = continuation
            }
        }
        return OttoDataSnapshot()
    }

    func restore(
        _ snapshot: OttoDataSnapshot, at instant: Date, watermarks: RestoreWatermarkPolicy
    ) async throws {}

    func reconstructMaterializationWatermarks() async throws {}
}

/// Counts permission reads. This is the CONTROL: `NotificationPermissionSection`
/// carries its own `.task { await notifications.refreshPermission() }`, so a
/// non-zero count proves this screen's `.task` modifiers really ran. Without it
/// an assertion that no export happened would pass just as well on a view that
/// never appeared at all.
private actor CountingClient: NotificationClient {
    private(set) var permissionCalls = 0

    func permission() async -> NotificationPermission {
        permissionCalls += 1
        return .authorized
    }

    func requestAuthorization() async -> NotificationPermission { .authorized }
    func pendingRequests() async -> [NotificationRequestSpec] { [] }
    func deliveredIdentifiers() async -> [String] { [] }
    func add(_ spec: NotificationRequestSpec) async throws {}
    func removePendingRequests(withIdentifiers identifiers: [String]) async {}
}

private struct IdleScheduler: ReminderScheduling {
    func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome {
        ScheduleOutcome(
            permission: .authorized, scheduledCount: 0, truncatedAfter: nil,
            coveredThrough: today
        )
    }
}

@MainActor
@Suite("Settings writes no financial record nobody asked for (F8 / R0-10(b))")
struct SettingsExportTests {

    /// A stored constant rather than a force-unwrap, so an invalid literal is a
    /// nil here instead of a crash inside a test - `TodaySectionPlanTests`' rule.
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
            settings: SettingsStore(
                userDefaults: UserDefaults(suiteName: suite) ?? .standard
            ),
            dates: .fixed(today: today)
        )
    }

    /// Puts the screen in a real window and lets its `.task` modifiers run.
    ///
    /// `UIHostingController.sizeThatFits` - what `DynamicTypeTests` uses - runs
    /// a layout pass and no `.task` at all, so it cannot see this defect. The
    /// view has to be in a window and the runloop has to turn.
    private func showSettings(_ model: AppModel) -> UIWindow {
        let host = UIHostingController(rootView: SettingsView().environment(model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        return window
    }

    /// Yields until `condition` holds or the budget runs out. Returns whether it
    /// held - the caller asserts on that, so a timeout is a named failure and
    /// never a silent pass.
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

    @Test("⛔ arriving on Settings writes no export at all")
    func appearanceWritesNothing() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.1",
            today: try #require(Self.today)
        )

        let window = showSettings(model)
        defer { window.isHidden = true }

        // The control first: if this never fires, the screen never ran a
        // `.task` and nothing below is evidence about the export.
        let viewTasksRan = await settle { await client.permissionCalls > 0 }
        #expect(viewTasksRan, "no .task on this screen ever ran, so this test proves nothing")

        // And then a further budget, because the export task would be a
        // SIBLING of the control and could merely be later. `completeSnapshot`
        // is the first await an export performs, so any export that had begun
        // would have registered by now.
        _ = await settle(upTo: 100) { await transfer.snapshotCalls > 0 }

        #expect(
            await transfer.snapshotCalls == 0,
            "opening Settings built a complete financial record nobody asked for"
        )
        #expect(model.preparedExport(.json) == nil)
        #expect(model.preparedExport(.chargesCSV) == nil)
    }

    @Test("⛔ an export is built only when asked, and once")
    func exportIsBuiltOnRequest() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.2",
            today: try #require(Self.today)
        )

        try await model.prepareExport(.json)

        #expect(await transfer.snapshotCalls == 1)
        let url = try #require(model.preparedExport(.json))
        #expect(url.lastPathComponent == "Otto-Export-2026-08-12.json")
        #expect(FileManager.default.fileExists(atPath: url.path))
        // The CSV is a separate request and was not made.
        #expect(model.preparedExport(.chargesCSV) == nil)
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
        _ = await settle { await transfer.isWaiting }
        #expect(model.exportAvailability(.json) == .preparing)

        model.withdrawPreparedExports()
        await transfer.release()
        _ = try await build.value

        #expect(model.preparedExport(.json) == nil)
        #expect(model.exportAvailability(.json) == .notPrepared)
    }

    /// ⛔ Two exports at once. A single-valued `preparing` flag made the JSON
    /// row a live button again the moment the CSV was tapped, and clearing it
    /// wiped the other row's state; one shared `failure` did the same for
    /// errors (`reviews-4/REVIEW-1.md` finding 6).
    @Test("⛔ the two export kinds have independent state")
    func theTwoKindsDoNotShareState() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.8",
            today: try #require(Self.today)
        )

        await transfer.hold()
        let json = Task { try await model.prepareExport(.json) }
        _ = await settle { await transfer.isWaiting }
        #expect(model.exportAvailability(.json) == .preparing)
        // The other row is untouched by the first one being in flight.
        #expect(model.exportAvailability(.chargesCSV) == .notPrepared)

        await transfer.release()
        _ = try await json.value
        #expect(model.exportAvailability(.chargesCSV) == .notPrepared)
        guard case .ready = model.exportAvailability(.json) else {
            Issue.record("the JSON row is \(model.exportAvailability(.json)), not ready")
            return
        }
    }

    /// R0-10(b). The file on disk describes the database as it was BEFORE the
    /// import; the share sheet must not still be offering it afterwards.
    @Test("⛔ an import withdraws every export prepared before it")
    func importWithdrawsAPreparedExport() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.3",
            today: try #require(Self.today)
        )

        try await model.prepareExport(.json)
        try await model.prepareExport(.chargesCSV)
        #expect(model.preparedExport(.json) != nil)
        #expect(model.preparedExport(.chargesCSV) != nil)

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("otto-tests-import-\(UUID().uuidString).json")
        try exportData(from: OttoDataSnapshot(), exportedAt: Date(timeIntervalSince1970: 0))
            .write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }

        _ = try await model.importData(from: file, strategy: .merge)

        #expect(model.preparedExport(.json) == nil)
        #expect(model.preparedExport(.chargesCSV) == nil)
    }
}
#endif
