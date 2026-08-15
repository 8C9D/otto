import Foundation
import OttoDomain

/// The one gate every scheduling pass goes through (round 5, item 1: N4-7 +
/// N4-3).
///
/// F10's gate lived in `NotificationCoordinator` and covered only the five
/// trigger classes routed through `rescheduleSoon`; `handleBackgroundRefresh`,
/// `NotificationStatusStore.reschedule()` and `NotificationActionHandler`'s
/// snooze paths reached the shared `NotificationScheduler` directly, and the
/// actor does not serialise them - `reschedule` suspends repeatedly before its
/// first write, so passes interleave. Measured at the round-5 baseline with the
/// six-suspension spy: 62 of 180 iterations for the background path, 39 of 180
/// for the store path. This wrapper sits at the `ReminderScheduling` seam all
/// of them share, so the composition root gates every caller by wrapping once.
///
/// **Serialised**: a pass starts only after the pass before it has finished, so
/// two passes can never race on the same rows. **Coalesced, not queued without
/// bound**: callers arriving while a pass runs share one follow-up, and the
/// follow-up starts after every one of their calls - each caller's outcome
/// therefore describes a pass that read the store at or after its trigger,
/// which is what lets the store publish it as current coverage. The follow-up
/// runs with the most recent joiner's arguments; the staleness bound is the
/// remainder of the in-flight pass.
///
/// **Cancellation is counted, not forwarded.** A caller's cancellation cancels
/// the underlying pass only when every caller waiting on that pass has been
/// cancelled - so a `BGAppRefreshTask` expiration stops a pass only the
/// background wake-up wanted, and cannot stop one a foreground caller is
/// counting on. A cancelled caller whose pass survives keeps waiting and
/// returns the pass's outcome; a pass cancelled outright throws
/// `CancellationError` to every waiter, and an abandoned follow-up whose
/// waiters were all cancelled never runs at all.
public actor CoalescingReminderScheduler: ReminderScheduling {

    /// One pass and the callers waiting on it. A class for reference identity
    /// across suspension points; `@unchecked Sendable` because every mutable
    /// property is read and written on this actor alone - the reference crosses
    /// task boundaries, the state does not.
    private final class Pass: @unchecked Sendable {
        var arguments: PassArguments
        var waiters = 1
        var cancelledWaiters = 0
        var finished = false
        var task: Task<ScheduleOutcome, any Error>?

        init(arguments: PassArguments) {
            self.arguments = arguments
        }
    }

    private struct PassArguments {
        let now: Date
        let today: CalendarDay
        let timeZone: TimeZone
    }

    private let base: any ReminderScheduling
    private var inFlight: Pass?
    private var queued: Pass?

    public init(base: any ReminderScheduling) {
        self.base = base
    }

    @discardableResult
    public func reschedule(
        now: Date,
        today: CalendarDay,
        timeZone: TimeZone
    ) async throws -> ScheduleOutcome {
        let (pass, task) = join(PassArguments(now: now, today: today, timeZone: timeZone))
        return try await withTaskCancellationHandler {
            // A waiter's own cancellation does not interrupt this await: the
            // shared pass belongs to every caller waiting on it, and its
            // outcome is still the honest answer for a caller that was
            // cancelled while someone else's pass covered its trigger.
            try await task.value
        } onCancel: {
            Task { await self.waiterCancelled(pass) }
        }
    }

    private func join(_ arguments: PassArguments) -> (Pass, Task<ScheduleOutcome, any Error>) {
        if let queued, let task = queued.task {
            // A follow-up already waits; share it. Latest arguments win, the
            // way the coordinator's `queued` trigger always overwrote.
            queued.arguments = arguments
            queued.waiters += 1
            OttoLog.scheduling.notice("pass coalesced into queued pass")
            return (queued, task)
        }
        if let inFlight, !inFlight.finished, let predecessor = inFlight.task {
            let pass = Pass(arguments: arguments)
            let task = start(pass, after: predecessor)
            pass.task = task
            queued = pass
            OttoLog.scheduling.notice("pass deferred behind in-flight pass")
            return (pass, task)
        }
        let pass = Pass(arguments: arguments)
        let task = start(pass, after: nil)
        pass.task = task
        inFlight = pass
        return (pass, task)
    }

    private func start(
        _ pass: Pass,
        after predecessor: Task<ScheduleOutcome, any Error>?
    ) -> Task<ScheduleOutcome, any Error> {
        Task {
            // The barrier that serialises passes: the follow-up's first act is
            // to wait for the whole pass before it, result ignored - a
            // predecessor's failure is its waiters' news, not this pass's.
            if let predecessor {
                _ = try? await predecessor.value
            }
            return try await self.execute(pass)
        }
    }

    private func execute(_ pass: Pass) async throws -> ScheduleOutcome {
        if pass === queued {
            inFlight = pass
            queued = nil
        }
        defer { pass.finished = true }
        // Set only by `waiterCancelled` once every waiter on this pass has
        // been cancelled - an abandoned follow-up stops here, before the base
        // scheduler does any work.
        try Task.checkCancellation()
        return try await base.reschedule(
            now: pass.arguments.now,
            today: pass.arguments.today,
            timeZone: pass.arguments.timeZone
        )
    }

    private func waiterCancelled(_ pass: Pass) {
        pass.cancelledWaiters += 1
        guard pass.cancelledWaiters >= pass.waiters, !pass.finished else { return }
        pass.task?.cancel()
    }

    // Test probes (the R4-2 precedent: internal, reached through `@testable`,
    // so the deterministic tests await a state instead of sleeping). Production
    // never reads them.
    var probeQueuedWaiters: Int { queued?.waiters ?? 0 }
    var probeQueuedCancelledWaiters: Int { queued?.cancelledWaiters ?? 0 }
    var probeQueuedTaskIsCancelled: Bool { queued?.task?.isCancelled ?? false }
    var probeInFlightTaskIsCancelled: Bool { inFlight?.task?.isCancelled ?? false }
}
