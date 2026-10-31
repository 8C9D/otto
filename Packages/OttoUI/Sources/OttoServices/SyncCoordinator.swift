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
    /// Each direction fails and recovers on its own. Imports go on succeeding
    /// while uploads are blocked by a full iCloud, so one shared failure would
    /// let the next import report "up to date" over changes stuck on this device.
    public var setupFailure: SyncFailure?
    public var importFailure: SyncFailure?
    public var exportFailure: SyncFailure?

    public init() {}

    /// What the screens state. Setup first, because it blocks both directions;
    /// then export, because stuck outbound changes are the ones only this
    /// device holds.
    public var lastFailure: SyncFailure? {
        setupFailure ?? exportFailure ?? importFailure
    }
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
///
/// **A pass owed is a pass paid.** An import that succeeds and is then followed
/// by one that fails still changed the store, so reminders and screens must
/// catch up. Reconciliation alone waits for a clean import: a failed one may
/// have committed part of its batches, and the next launch always imports.
public actor SyncCoordinator {

    /// Held, not just read from: the real source stops observing when it is
    /// released, so taking only its stream left a coordinator that looked fine
    /// and heard nothing - the store had recorded events, this never ran, and
    /// no test could see it, because a fake stream has no owner to lose. Found
    /// by running a mirrored store on a simulator.
    private let source: any SyncEventSource
    private let reconciliation: any ReconciliationRepository
    private let now: @Sendable () -> Date
    private let settleDelay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let afterConvergence: @Sendable () async -> Void
    private let onActivity: @Sendable (SyncActivity) async -> Void

    private var activity = SyncActivity()
    private var pendingConvergence: Task<Void, Never>?
    /// Identifies the latest scheduled pass. A burst is coalesced by letting
    /// superseded delays lapse, never by cancelling: the task being replaced
    /// may already be past its delay and mid-pass, and a cancelled pass trips
    /// the scheduler's cancellation checkpoints and reports itself as failed.
    private var convergenceGeneration = 0
    /// A successful import has not been followed by a pass yet.
    private var convergenceOwed = false
    private var lastImportSucceeded = false

    public init(
        source: any SyncEventSource,
        reconciliation: any ReconciliationRepository,
        now: @escaping @Sendable () -> Date,
        settleDelay: Duration = .seconds(2),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        afterConvergence: @escaping @Sendable () async -> Void,
        onActivity: @escaping @Sendable (SyncActivity) async -> Void
    ) {
        self.source = source
        self.reconciliation = reconciliation
        self.now = now
        self.settleDelay = settleDelay
        self.sleep = sleep
        self.afterConvergence = afterConvergence
        self.onActivity = onActivity
    }

    /// Consumes events until the stream ends, which in the app is never.
    public func run() async {
        for await event in source.events {
            await handle(event)
        }
        // A test's finite stream: let the last scheduled pass finish.
        await pendingConvergence?.value
    }

    func handle(_ event: SyncEvent) async {
        log(event)
        apply(event)
        await onActivity(activity)
        guard event.kind == .import, event.phase != .started else { return }
        lastImportSucceeded = event.phase == .succeeded
        if lastImportSucceeded {
            convergenceOwed = true
        }
        if convergenceOwed {
            scheduleConvergence()
        }
    }

    private func apply(_ event: SyncEvent) {
        switch (event.kind, event.phase) {
        case (.setup, .started):
            break
        case (.setup, .succeeded):
            activity.setupFailure = nil
        case (.setup, .failed(let failure)):
            activity.setupFailure = failure
        case (.import, .started):
            activity.isImporting = true
        case (.export, .started):
            activity.isExporting = true
        case (.import, .succeeded):
            activity.isImporting = false
            activity.hasFinishedImport = true
            activity.importFailure = nil
            recordSuccess()
        case (.export, .succeeded):
            activity.isExporting = false
            activity.exportFailure = nil
            recordSuccess()
        case (.import, .failed(let failure)):
            activity.isImporting = false
            activity.importFailure = failure
        case (.export, .failed(let failure)):
            activity.isExporting = false
            activity.exportFailure = failure
        }
    }

    /// Either direction finishing proves setup has recovered.
    private func recordSuccess() {
        activity.lastSuccessAt = now()
        activity.setupFailure = nil
    }

    private func scheduleConvergence() {
        convergenceGeneration += 1
        let generation = convergenceGeneration
        pendingConvergence = Task { [settleDelay, sleep] in
            do {
                try await sleep(settleDelay)
            } catch {
                return
            }
            await self.converge(generation: generation)
        }
    }

    private func converge(generation: Int) async {
        guard generation == convergenceGeneration else { return }
        // Running now is the mid-flight read the type refuses. The pass stays
        // owed, and that import's end schedules it whichever way it goes.
        guard !activity.isImporting else { return }
        convergenceOwed = false
        if lastImportSucceeded {
            await reconcile()
        }
        await afterConvergence()
    }

    private func reconcile() async {
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
