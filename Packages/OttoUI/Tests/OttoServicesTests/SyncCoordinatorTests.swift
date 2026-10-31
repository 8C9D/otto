import Foundation
import OttoRepositories
import Testing
@testable import OttoServices

/// Records the order things happened in, across the seams.
private actor Journal {
    private(set) var entries: [String] = []
    private(set) var activities: [SyncActivity] = []

    func add(_ entry: String) { entries.append(entry) }
    func add(_ activity: SyncActivity) { activities.append(activity) }
}

private struct SpyReconciliation: ReconciliationRepository {
    let journal: Journal
    var failure: (any Error)?
    /// Parks the pass here, so a test can act while it is running.
    var hold: Gate?

    func reconcile(at instant: Date) async throws -> ReconciliationSummary {
        await journal.add("reconcile")
        await hold?.wait()
        if let failure { throw failure }
        return ReconciliationSummary()
    }
}

/// Holds every settle delay until the test lets it go, so "an import arrived
/// during the delay" is a position in the test rather than a race.
private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var waitCount = 0

    func wait() async {
        waitCount += 1
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private struct StubFailure: Error {}

/// Waits for async work with no handle to await. Bounded, so a regression fails
/// here at its own line instead of hanging the run.
private func eventually(
    _ condition: () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0 ..< 3_000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("the condition never became true", sourceLocation: sourceLocation)
}

/// A source that stops when released, like the real one.
private final class StreamSource: SyncEventSource, Sendable {
    let events: AsyncStream<SyncEvent>

    init(_ events: AsyncStream<SyncEvent>) {
        self.events = events
    }
}

@Suite("The post-import pass (spec §5.3, §6.2, Wave 6B)")
struct SyncCoordinatorTests {
    private static let instant = Date(timeIntervalSince1970: 50_000)

    private func event(_ kind: SyncEvent.Kind, _ phase: SyncEvent.Phase) -> SyncEvent {
        SyncEvent(kind: kind, phase: phase)
    }

    /// Runs a finite stream to the end, with no settle delay.
    private func run(_ events: [SyncEvent], reconcileFailure: (any Error)? = nil) async -> Journal {
        let journal = Journal()
        let (stream, continuation) = AsyncStream.makeStream(of: SyncEvent.self)
        events.forEach { continuation.yield($0) }
        continuation.finish()
        let coordinator = SyncCoordinator(
            source: StreamSource(stream),
            reconciliation: SpyReconciliation(journal: journal, failure: reconcileFailure),
            now: { Self.instant },
            sleep: { _ in },
            afterConvergence: { await journal.add("afterConvergence") },
            onActivity: { await journal.add($0) }
        )
        await coordinator.run()
        return journal
    }

    @Test("a finished import reconciles, THEN re-plans - reminders are planned from the converged ledger")
    func importConvergesInOrder() async {
        let journal = await run([event(.import, .started), event(.import, .succeeded)])
        #expect(await journal.entries == ["reconcile", "afterConvergence"])
    }

    @Test("nothing else runs the pass", arguments: [
        SyncEvent(kind: .import, phase: .started),
        SyncEvent(kind: .import, phase: .failed(.networkUnavailable)),
        SyncEvent(kind: .export, phase: .started),
        SyncEvent(kind: .export, phase: .succeeded),
        SyncEvent(kind: .setup, phase: .succeeded)
    ])
    func otherEventsDoNotConverge(event: SyncEvent) async {
        let journal = await run([event])
        #expect(await journal.entries.isEmpty)
    }

    @Test("a failed reconcile still re-plans: the import happened whether or not the merge did")
    func reconcileFailureStillFollowsThrough() async {
        let journal = await run([event(.import, .succeeded)], reconcileFailure: StubFailure())
        #expect(await journal.entries == ["reconcile", "afterConvergence"])
    }

    @Test("an import starting during the delay holds the pass until it has finished too")
    func noPassMidFlight() async throws {
        let journal = Journal()
        let gate = Gate()
        let (stream, _) = AsyncStream.makeStream(of: SyncEvent.self)
        let coordinator = SyncCoordinator(
            source: StreamSource(stream),
            reconciliation: SpyReconciliation(journal: journal),
            now: { Self.instant },
            sleep: { _ in await gate.wait() },
            afterConvergence: { await journal.add("afterConvergence") },
            onActivity: { await journal.add($0) }
        )

        await coordinator.handle(event(.import, .succeeded))
        await eventually { await gate.waitCount >= 1 }
        // The second import begins inside the first one's delay.
        await coordinator.handle(event(.import, .started))
        await gate.open()
        for _ in 0 ..< 50 { await Task.yield() }
        #expect(await journal.entries.isEmpty)

        // Its finish schedules the pass the first one gave up.
        await coordinator.handle(event(.import, .succeeded))
        await eventually { await gate.waitCount >= 2 }
        await gate.open()
        await eventually { await journal.entries.count >= 2 }
        #expect(await journal.entries == ["reconcile", "afterConvergence"])
    }

    @Test("a burst of imports converges once")
    func burstConvergesOnce() async throws {
        let journal = Journal()
        let gate = Gate()
        let (stream, _) = AsyncStream.makeStream(of: SyncEvent.self)
        let coordinator = SyncCoordinator(
            source: StreamSource(stream),
            reconciliation: SpyReconciliation(journal: journal),
            now: { Self.instant },
            sleep: { _ in
                await gate.wait()
                try Task.checkCancellation()
            },
            afterConvergence: { await journal.add("afterConvergence") },
            onActivity: { _ in }
        )
        for _ in 0 ..< 3 {
            await coordinator.handle(event(.import, .succeeded))
        }
        await eventually { await gate.waitCount >= 3 }
        await gate.open()
        await eventually { await journal.entries.count >= 2 }
        for _ in 0 ..< 50 { await Task.yield() }
        #expect(await journal.entries == ["reconcile", "afterConvergence"])
    }

    @Test("the coordinator keeps its source alive: a released monitor stops observing, silently")
    func coordinatorRetainsItsSource() async {
        let (stream, _) = AsyncStream.makeStream(of: SyncEvent.self)
        weak var released: StreamSource?
        let coordinator: SyncCoordinator = {
            let source = StreamSource(stream)
            released = source
            return SyncCoordinator(
                source: source,
                reconciliation: SpyReconciliation(journal: Journal()),
                now: { Self.instant },
                afterConvergence: {},
                onActivity: { _ in }
            )
        }()
        #expect(released != nil)
        withExtendedLifetime(coordinator) {}
    }

    @Test("a pass still owed when a later import FAILS is paid, without reconciling over the failure")
    func failedImportPaysTheOwedPass() async throws {
        let journal = Journal()
        let gate = Gate()
        let (stream, _) = AsyncStream.makeStream(of: SyncEvent.self)
        let coordinator = SyncCoordinator(
            source: StreamSource(stream),
            reconciliation: SpyReconciliation(journal: journal),
            now: { Self.instant },
            sleep: { _ in await gate.wait() },
            afterConvergence: { await journal.add("afterConvergence") },
            onActivity: { _ in }
        )

        // Import A lands. Import B starts inside A's delay, so A's pass stands down.
        await coordinator.handle(event(.import, .succeeded))
        await eventually { await gate.waitCount >= 1 }
        await coordinator.handle(event(.import, .started))
        await gate.open()
        for _ in 0 ..< 50 { await Task.yield() }
        #expect(await journal.entries.isEmpty)

        // B fails. A's changes are in the store and the screens must catch up,
        // but a failed import may have left a transaction half-applied.
        await coordinator.handle(event(.import, .failed(.networkUnavailable)))
        await eventually { await gate.waitCount >= 2 }
        await gate.open()
        await eventually { await !journal.entries.isEmpty }
        #expect(await journal.entries == ["afterConvergence"])

        // The next clean import is what reconciles.
        await coordinator.handle(event(.import, .succeeded))
        await eventually { await gate.waitCount >= 3 }
        await gate.open()
        await eventually { await journal.entries.count >= 3 }
        #expect(await journal.entries == ["afterConvergence", "reconcile", "afterConvergence"])
    }

    @Test("a new import never cancels a pass already running: cancelled passes report themselves failed")
    func runningPassIsNotCancelled() async throws {
        let journal = Journal()
        let hold = Gate()
        let (stream, _) = AsyncStream.makeStream(of: SyncEvent.self)
        let coordinator = SyncCoordinator(
            source: StreamSource(stream),
            reconciliation: SpyReconciliation(journal: journal, hold: hold),
            now: { Self.instant },
            sleep: { _ in },
            afterConvergence: {
                await journal.add(Task.isCancelled ? "cancelled" : "afterConvergence")
            },
            onActivity: { _ in }
        )

        await coordinator.handle(event(.import, .succeeded))
        await eventually { await hold.waitCount >= 1 }
        // Mid-pass, parked inside reconcile, another import lands.
        await coordinator.handle(event(.import, .succeeded))
        await eventually { await hold.waitCount >= 2 }
        await hold.open()
        await eventually { await journal.entries.filter { $0 != "reconcile" }.count >= 2 }
        #expect(await !journal.entries.contains("cancelled"))
    }

    @Test("activity tracks both directions")
    func activityTracksTheLifecycle() async throws {
        let journal = await run([
            event(.import, .started),
            event(.export, .started),
            event(.import, .failed(.networkUnavailable)),
            event(.export, .succeeded)
        ])
        let activities = await journal.activities
        #expect(activities.map(\.isImporting) == [true, true, false, false])
        #expect(activities.map(\.isExporting) == [false, true, true, false])
        #expect(activities[3].lastSuccessAt == Self.instant)
    }

    @Test("an import succeeding says nothing about uploads: a full iCloud stays reported until an export recovers")
    func failuresBelongToTheirDirection() async throws {
        let journal = await run([
            event(.export, .failed(.quotaExceeded)),
            event(.import, .succeeded),
            event(.export, .succeeded)
        ])
        let activities = await journal.activities
        #expect(activities[1].lastFailure == .quotaExceeded)
        #expect(activities[2].lastFailure == nil)
    }

    @Test("an export succeeding doesn't clear a failed import either")
    func importFailureSurvivesAnExport() async throws {
        let journal = await run([
            event(.import, .failed(.networkUnavailable)),
            event(.export, .succeeded)
        ])
        #expect(await journal.activities.last?.lastFailure == .networkUnavailable)
    }

    @Test("a setup failure outranks both directions and clears once any step completes")
    func setupFailureClearsOnProgress() async throws {
        let journal = await run([
            event(.export, .failed(.quotaExceeded)),
            event(.setup, .failed(.accountUnavailable)),
            event(.export, .succeeded)
        ])
        let activities = await journal.activities
        #expect(activities[1].lastFailure == .accountUnavailable)
        #expect(activities[2].lastFailure == nil)
    }

    @Test("only a finished IMPORT means this device has caught up; an export says nothing about what's inbound")
    func caughtUpMeansAnImportFinished() async throws {
        let exportOnly = await run([event(.export, .succeeded)])
        #expect(await exportOnly.activities.last?.hasFinishedImport == false)

        let failed = await run([event(.import, .failed(.networkUnavailable))])
        #expect(await failed.activities.last?.hasFinishedImport == false)

        let finished = await run([event(.import, .succeeded)])
        #expect(await finished.activities.last?.hasFinishedImport == true)
    }
}
