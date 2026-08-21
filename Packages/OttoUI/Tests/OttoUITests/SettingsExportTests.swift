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
actor CountingTransfer: DataTransferRepository {
    private(set) var snapshotCalls = 0
    /// Set by `hold()`: the next `completeSnapshot()` parks here until
    /// `release()`, so a test can make something happen while a build is
    /// genuinely suspended rather than hoping for an interleaving.
    private var gates: [CheckedContinuation<Void, Never>] = []
    private var holding = false
    private var failing = false
    private(set) var waiting = 0

    struct SnapshotRefused: Error {}

    func hold() { holding = true }
    func fail() { failing = true }

    /// Releases every parked build, so a test can hold TWO at once.
    func release() {
        holding = false
        for gate in gates { gate.resume() }
        gates.removeAll()
        waiting = 0
    }

    func completeSnapshot() async throws -> OttoDataSnapshot {
        snapshotCalls += 1
        if holding {
            waiting += 1
            await withCheckedContinuation { continuation in
                gates.append(continuation)
            }
        }
        if failing { throw SnapshotRefused() }
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
actor CountingClient: NotificationClient {
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

struct IdleScheduler: ReminderScheduling {
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
            settings: SettingsStore(userDefaults: freshDefaults(suite)),
            dates: .fixed(today: today)
        )
    }

    /// The suite persists in the simulator container between RUNS, so a fixed
    /// name must be wiped or a prior run's writes leak in - a leftover stored
    /// time turned the reminder-time test's pick into an unchanged re-pick,
    /// which correctly notifies nobody (`0787150`) and so withdraws nothing.
    private func freshDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
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

    /// ⛔ Two exports at once, which is the state finding 6 was about and the
    /// first version of this test never produced.
    ///
    /// `reviews-4/REVIEW-4.md` finding 1 restored the single-valued state
    /// machine exactly - `preparing = [kind]`, `preparing.removeAll()`,
    /// `exportFailures.removeAll()` - and the whole simulator suite stayed
    /// green, because this test started ONE build and a shared flag is only
    /// wrong when two are in flight. It starts both now.
    @Test("⛔ the two export kinds have independent in-flight state")
    func theTwoKindsDoNotShareState() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.8",
            today: try #require(Self.today)
        )

        await transfer.hold()
        let json = Task { try await model.prepareExport(.json) }
        let csv = Task { try await model.prepareExport(.chargesCSV) }
        let bothParked = await settle { await transfer.waiting == 2 }
        #expect(bothParked, "both builds never reached the transfer, so this proves nothing")

        // A single-valued flag can only say one of these.
        #expect(model.exportAvailability(.json) == .preparing)
        #expect(model.exportAvailability(.chargesCSV) == .preparing)

        await transfer.release()
        _ = try await json.value
        _ = try await csv.value
        guard case .ready = model.exportAvailability(.json),
              case .ready = model.exportAvailability(.chargesCSV) else {
            Issue.record("json=\(model.exportAvailability(.json)) csv=\(model.exportAvailability(.chargesCSV))")
            return
        }
    }

    /// ⛔ And a failure recorded for one kind is not wiped by the other
    /// succeeding - the second half of finding 6, which one shared `failure`
    /// string could not represent either.
    @Test("⛔ a failure on one kind survives the other kind succeeding")
    func aFailureOnOneKindIsNotClearedByTheOther() async throws {
        let failing = CountingTransfer()
        await failing.fail()
        let client = CountingClient()
        let model = makeModel(
            transfer: failing, client: client, suite: "otto.tests.settingsexport.9",
            today: try #require(Self.today)
        )

        await #expect(throws: (any Error).self) { try await model.prepareExport(.json) }
        guard case .failed = model.exportAvailability(.json) else {
            Issue.record("the JSON row is \(model.exportAvailability(.json)), not failed")
            return
        }

        // The CSV build cannot succeed against a failing transfer either, so
        // drive the other direction: a fresh REQUEST for the CSV must not
        // clear the JSON row's recorded failure.
        await model.requestExport(.chargesCSV).value
        guard case .failed = model.exportAvailability(.json) else {
            Issue.record("the CSV request cleared the JSON row's failure")
            return
        }
    }

    /// ⛔ `requestExport` is what the view's button calls, and it was added by
    /// the stage-1 remediation with nothing exercising it
    /// (`reviews-4/REVIEW-4.md` finding 1): its body could be emptied with
    /// every gate in the project green. It is one layer below the closure no
    /// test can reach, and this is the lowest layer that is reachable.
    @Test("⛔ the call the export button makes actually builds the file")
    func requestExportBuildsTheFile() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.10",
            today: try #require(Self.today)
        )

        await model.requestExport(.json).value

        #expect(await transfer.snapshotCalls == 1)
        let url = try #require(model.preparedExport(.json))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// ⛔ Deleting a payment method, not only saving one. The stage-1
    /// remediation added the hook to both and tested one.
    @Test("⛔ deleting a payment method withdraws a prepared export")
    func aPaymentMethodDeleteWithdraws() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.11",
            today: try #require(Self.today)
        )
        let method = PaymentMethod(
            id: UUID(), label: "Visa", last4: "4242", issuer: "Visa",
            expiryMonth: 6, expiryYear: 2030, isDefault: false,
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0)
        )
        try await model.paymentMethodsStore.save(method)

        try await model.prepareExport(.json)
        #expect(model.preparedExport(.json) != nil)

        try await model.paymentMethodsStore.delete(paymentMethodID: method.id)

        #expect(model.preparedExport(.json) == nil)
    }

    /// ⛔ The reminder-time path, whose comment claiming it "changes no record"
    /// was measured false in the stage-1 review. The reschedule it triggers
    /// materializes ledger rows the CSV prints, so it withdraws - and nothing
    /// observed that until now.
    @Test("⛔ a notification-time change withdraws a prepared export")
    func aReminderTimeChangeWithdraws() async throws {
        let transfer = CountingTransfer()
        let client = CountingClient()
        let model = makeModel(
            transfer: transfer, client: client, suite: "otto.tests.settingsexport.12",
            today: try #require(Self.today)
        )

        try await model.prepareExport(.json)
        #expect(model.preparedExport(.json) != nil)

        let picked = try #require(
            CalendarDay.conversionCalendar.date(
                from: DateComponents(year: 2000, month: 1, day: 1, hour: 7, minute: 30)
            )
        )
        model.settings.setNotificationTime(from: picked)
        let withdrawn = await settle { await MainActor.run { model.preparedExport(.json) == nil } }

        #expect(withdrawn, "a notification-time change left the prepared export on offer")
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
