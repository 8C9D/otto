// Round 5, item 1 (N4-7 + N4-3): the seam gate under the REAL entry points.
//
// The host suite proves the gate's own semantics; this file proves the wiring
// claim the fix actually rests on - that a coordinator, a status store and a
// background task handed ONE `CoalescingReminderScheduler` cannot overlap
// passes, and that a `BGAppRefreshTask` expiration cancels only a pass the
// background wake-up alone is waiting on. Simulator-hosted like the coordinator
// tests, and for the same reason: the coordinator compiles to nothing on the
// host.
#if os(iOS)
import Foundation
import Testing
import OttoDomain
import OttoStores
import Synchronization
@testable import OttoServices

private struct GateSpyState {
    var live = 0
    var peak = 0
    var passes = 0
    var cancelledPasses = 0
    var released = false
}

/// Same shape as the host suite's spy: `.yielding` suspends six times to model
/// the real scheduler, `.held` parks the pass until `release()`. Outcomes are
/// stamped with their pass number in `scheduledCount`.
private final class GateSpy: ReminderScheduling {
    enum Mode { case yielding, held }

    private let state = Mutex(GateSpyState())
    private let mode: Mode
    private let coveredThrough: CalendarDay

    init(_ mode: Mode, coveredThrough: CalendarDay) {
        self.mode = mode
        self.coveredThrough = coveredThrough
    }

    var peak: Int { state.withLock { $0.peak } }
    var passes: Int { state.withLock { $0.passes } }
    var cancelledPasses: Int { state.withLock { $0.cancelledPasses } }

    func release() {
        state.withLock { $0.released = true }
    }

    func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome {
        let passNumber = state.withLock { current -> Int in
            current.passes += 1
            current.live += 1
            current.peak = max(current.peak, current.live)
            return current.passes
        }
        defer { state.withLock { $0.live -= 1 } }
        switch mode {
        case .yielding:
            for _ in 0..<6 { await Task.yield() }
        case .held:
            while !state.withLock({ $0.released }) {
                if Task.isCancelled {
                    state.withLock { $0.cancelledPasses += 1 }
                    throw CancellationError()
                }
                await Task.yield()
            }
        }
        return ScheduleOutcome(
            permission: .authorized, scheduledCount: passNumber,
            truncatedAfter: nil, coveredThrough: coveredThrough
        )
    }
}

private final class GateFakeTask: BackgroundRefreshTask, @unchecked Sendable {
    private let recorded = Mutex<[Bool]>([])
    var expirationHandler: (() -> Void)?

    var completions: [Bool] { recorded.withLock { $0 } }

    func setTaskCompleted(success: Bool) {
        recorded.withLock { $0.append(success) }
    }
}

@MainActor
@Suite("The seam gate under the real entry points (N4-7 + N4-3)")
struct SchedulingGateIntegrationTests {

    private func fixtureDay() throws -> CalendarDay {
        try #require(CalendarDay(year: 2026, month: 8, day: 15))
    }

    private func makeCoordinator(
        scheduler: any ReminderScheduling, day: CalendarDay
    ) -> NotificationCoordinator {
        NotificationCoordinator(
            scheduler: scheduler,
            handler: NotificationActionHandler(
                subscriptions: StubSubscriptionRepository(),
                flows: SubscriptionFlowService(
                    subscriptions: StubSubscriptionRepository(),
                    cancellations: StubCancellationRepository(),
                    billingEvents: StubBillingEventRepository(),
                    priceChanges: StubPriceChangeRepository()
                ),
                client: StubNotificationClient(),
                scheduler: scheduler
            ),
            client: LiveNotificationClient(center: StubCenter()),
            now: { Date(timeIntervalSince1970: 1_786_000_000) },
            today: { day },
            timeZone: { TimeZone(identifier: "America/Toronto") ?? .current }
        )
    }

    private func settle(until condition: () async -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    /// ⛔ The fix, at the entry points where the defect was measured: foreground,
    /// background refresh and a store write fired together, sixty times over,
    /// never put two passes inside the scheduler at once. At the round-5
    /// baseline this same shape overlapped in 62 of 180 (background) and 39 of
    /// 180 (store) iterations.
    @Test("⛔ foreground, background and store passes serialise through one gate")
    func threeEntryPointsSerialise() async throws {
        let day = try fixtureDay()
        for _ in 0..<60 {
            let spy = GateSpy(.yielding, coveredThrough: day)
            let gate = CoalescingReminderScheduler(base: spy)
            let coordinator = makeCoordinator(scheduler: gate, day: day)
            let store = NotificationStatusStore(scheduler: gate, client: StubNotificationClient())
            let task = GateFakeTask()

            let storePass = Task { await store.reschedule() }
            let foreground = coordinator.rescheduleSoon(.foreground)
            let background = coordinator.handleBackgroundRefresh(task)
            await storePass.value
            await foreground.value
            await background.value

            #expect(spy.peak == 1)
            #expect(task.completions == [true])
            #expect(store.outcome != nil)
        }
    }

    /// ⛔ The expiration question the ledger required this stage to answer:
    /// expiring the background task while the FOREGROUND owns the running pass
    /// cancels nothing the foreground is counting on. The background's queued
    /// follow-up - its own sole-waiter pass - is abandoned unrun, the
    /// foreground pass completes and publishes, and the `BGAppRefreshTask` is
    /// completed exactly once, unsuccessfully.
    @Test("⛔ expiration spares a pass the foreground is counting on")
    func expirationSparesTheForegroundPass() async throws {
        let day = try fixtureDay()
        let spy = GateSpy(.held, coveredThrough: day)
        let gate = CoalescingReminderScheduler(base: spy)
        let coordinator = makeCoordinator(scheduler: gate, day: day)
        let task = GateFakeTask()
        var published: [ScheduleOutcome?] = []
        coordinator.onOutcome = { published.append($0) }

        let foreground = coordinator.rescheduleSoon(.foreground)
        #expect(await settle { spy.passes == 1 })
        let background = coordinator.handleBackgroundRefresh(task)
        #expect(await settle { await gate.probeQueuedWaiters == 1 })

        task.expirationHandler?()
        #expect(await settle { await gate.probeQueuedTaskIsCancelled })
        spy.release()
        await foreground.value
        await background.value

        // The foreground's pass ran to completion, uncancelled; the abandoned
        // follow-up never reached the scheduler.
        #expect(spy.passes == 1)
        #expect(spy.cancelledPasses == 0)
        // The foreground published its outcome; the background then reported
        // its own cancelled pass as a failure, which is R4-2's rule unchanged.
        #expect(published.count == 2)
        #expect(published.first??.scheduledCount == 1)
        let lastPublished = try #require(published.last)
        #expect(lastPublished == nil)
        #expect(task.completions == [false])
    }

    /// ⛔ The other half of the answer: a pass ONLY the background wake-up is
    /// waiting on is still the expiration's to cancel - the round-4 behaviour
    /// the gate must not lose. The scheduler sees the cancellation, the task
    /// completes once as a failure, and the gate reopens for the next caller.
    @Test("⛔ expiration still cancels a pass only the background wanted")
    func expirationCancelsABackgroundOwnedPass() async throws {
        let day = try fixtureDay()
        let spy = GateSpy(.held, coveredThrough: day)
        let gate = CoalescingReminderScheduler(base: spy)
        let coordinator = makeCoordinator(scheduler: gate, day: day)
        let task = GateFakeTask()

        let background = coordinator.handleBackgroundRefresh(task)
        #expect(await settle { spy.passes == 1 })

        task.expirationHandler?()
        #expect(await settle { await gate.probeInFlightTaskIsCancelled })
        await background.value

        #expect(spy.cancelledPasses == 1)
        #expect(task.completions == [false])

        spy.release()
        let store = NotificationStatusStore(scheduler: gate, client: StubNotificationClient())
        await store.reschedule()
        #expect(store.outcome?.scheduledCount == 2)
    }
}
#endif
