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

    func reconcile(at instant: Date) async throws -> ReconciliationSummary {
        await journal.add("reconcile")
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
            events: stream,
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
            events: stream,
            reconciliation: SpyReconciliation(journal: journal),
            now: { Self.instant },
            sleep: { _ in await gate.wait() },
            afterConvergence: { await journal.add("afterConvergence") },
            onActivity: { await journal.add($0) }
        )

        await coordinator.handle(event(.import, .succeeded))
        while await gate.waitCount < 1 { await Task.yield() }
        // The second import begins inside the first one's delay.
        await coordinator.handle(event(.import, .started))
        await gate.open()
        for _ in 0 ..< 50 { await Task.yield() }
        #expect(await journal.entries.isEmpty)

        // Its finish schedules the pass the first one gave up.
        await coordinator.handle(event(.import, .succeeded))
        while await gate.waitCount < 2 { await Task.yield() }
        await gate.open()
        while await journal.entries.count < 2 { await Task.yield() }
        #expect(await journal.entries == ["reconcile", "afterConvergence"])
    }

    @Test("a burst of imports converges once")
    func burstConvergesOnce() async throws {
        let journal = Journal()
        let gate = Gate()
        let (stream, _) = AsyncStream.makeStream(of: SyncEvent.self)
        let coordinator = SyncCoordinator(
            events: stream,
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
        while await gate.waitCount < 3 { await Task.yield() }
        await gate.open()
        while await journal.entries.count < 2 { await Task.yield() }
        for _ in 0 ..< 50 { await Task.yield() }
        #expect(await journal.entries == ["reconcile", "afterConvergence"])
    }

    @Test("activity tracks both directions, and a success clears the last failure")
    func activityTracksTheLifecycle() async throws {
        let journal = await run([
            event(.import, .started),
            event(.export, .started),
            event(.import, .failed(.quotaExceeded)),
            event(.export, .succeeded)
        ])
        let activities = await journal.activities
        #expect(activities.map(\.isImporting) == [true, true, false, false])
        #expect(activities.map(\.isExporting) == [false, true, true, false])
        #expect(activities[2].lastFailure == .quotaExceeded)
        #expect(activities[3].lastFailure == nil)
        #expect(activities[3].lastSuccessAt == Self.instant)
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
