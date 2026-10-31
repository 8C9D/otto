import Foundation
import OttoRepositories

/// What mirroring is doing right now, as far as this session has been told.
public struct SyncActivity: Hashable, Sendable {
    public var isImporting = false
    public var isExporting = false
    /// Whether an import has finished cleanly since launch - the moment "this
    /// device has caught up" stops being a guess.
    public var hasFinishedImport = false
    public var lastSuccessAt: Date?
    /// The latest step's failure, cleared by the next success of either kind.
    public var lastFailure: SyncFailure?

    public init() {}
}

/// Runs the work a CloudKit import leaves behind (spec §5.3, §6.2).
///
/// The framework writes other devices' changes straight into the store. Nothing
/// else in the app would notice, so after a finished import this converges the
/// store with `reconcile(at:)` - which until this wave had no caller - and then
/// hands over to `afterConvergence`, which re-plans reminders and refreshes the
/// screens.
///
/// **After a FINISHED import, never mid-flight.** One user save reaches CloudKit
/// as one atomic zone write, so a finished import holds whole transactions;
/// mid-import it may not, and the §4a repairs would read a record whose partner
/// is still arriving as a conflict. A delay lets a burst of imports settle once.
/// Reconciliation's writes export and trigger the other device's pass, which
/// finds nothing to do: every rule is idempotent, so this cannot ping-pong.
public actor SyncCoordinator {

    private let events: AsyncStream<SyncEvent>
    private let reconciliation: any ReconciliationRepository
    private let now: @Sendable () -> Date
    private let settleDelay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let afterConvergence: @Sendable () async -> Void
    private let onActivity: @Sendable (SyncActivity) async -> Void

    private var activity = SyncActivity()
    private var pendingConvergence: Task<Void, Never>?

    public init(
        events: AsyncStream<SyncEvent>,
        reconciliation: any ReconciliationRepository,
        now: @escaping @Sendable () -> Date,
        settleDelay: Duration = .seconds(2),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        afterConvergence: @escaping @Sendable () async -> Void,
        onActivity: @escaping @Sendable (SyncActivity) async -> Void
    ) {
        self.events = events
        self.reconciliation = reconciliation
        self.now = now
        self.settleDelay = settleDelay
        self.sleep = sleep
        self.afterConvergence = afterConvergence
        self.onActivity = onActivity
    }

    /// Consumes events until the stream ends, which in the app is never.
    public func run() async {
        for await event in events {
            await handle(event)
        }
        // A test's finite stream: let the last scheduled pass finish.
        await pendingConvergence?.value
    }

    func handle(_ event: SyncEvent) async {
        log(event)
        apply(event)
        await onActivity(activity)
        if event.kind == .import, event.phase == .succeeded {
            scheduleConvergence()
        }
    }

    private func apply(_ event: SyncEvent) {
        switch (event.kind, event.phase) {
        case (.setup, .succeeded), (.setup, .started):
            break
        case (.setup, .failed(let failure)):
            activity.lastFailure = failure
        case (.import, .started):
            activity.isImporting = true
        case (.export, .started):
            activity.isExporting = true
        case (.import, .succeeded):
            activity.isImporting = false
            activity.hasFinishedImport = true
            recordSuccess()
        case (.export, .succeeded):
            activity.isExporting = false
            recordSuccess()
        case (.import, .failed(let failure)):
            activity.isImporting = false
            activity.lastFailure = failure
        case (.export, .failed(let failure)):
            activity.isExporting = false
            activity.lastFailure = failure
        }
    }

    private func recordSuccess() {
        activity.lastSuccessAt = now()
        activity.lastFailure = nil
    }

    private func scheduleConvergence() {
        pendingConvergence?.cancel()
        pendingConvergence = Task { [settleDelay, sleep] in
            do {
                try await sleep(settleDelay)
            } catch {
                return
            }
            await self.converge()
        }
    }

    private func converge() async {
        // The import that started during the delay reschedules this when it
        // finishes; running now is the mid-flight read the type refuses.
        guard !activity.isImporting else { return }
        do {
            let summary = try await reconciliation.reconcile(at: now())
            OttoLog.sync.notice("""
                converged ledger=\(summary.mergedLedgerGroups, privacy: .public) \
                cancellations=\(summary.mergedCancellationGroups, privacy: .public) \
                repairs=\(summary.persistedReadRepairs, privacy: .public)
                """)
        } catch {
            // Reconciliation is one save, so a failure left nothing half-done
            // and the next import retries. The import itself still happened,
            // so reminders and screens must still catch up to it.
            OttoLog.sync.error("convergence failed: \((error as NSError).code, privacy: .public)")
        }
        await afterConvergence()
    }

    private func log(_ event: SyncEvent) {
        switch event.phase {
        case .started:
            OttoLog.sync.debug("\(event.kind.rawValue, privacy: .public) started")
        case .succeeded:
            OttoLog.sync.notice("\(event.kind.rawValue, privacy: .public) succeeded")
        case .failed(let failure):
            OttoLog.sync.error("""
                \(event.kind.rawValue, privacy: .public) failed: \(String(describing: failure), privacy: .public)
                """)
        }
    }
}
