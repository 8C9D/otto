import Foundation
import OttoDomain
import Synchronization
import Testing
@testable import OttoServices

/// What a refused pass throws. File-scope because SwiftLint's `nesting` rule
/// allows one level and the spy is already nested one deep.
private struct SeamPassRefused: Error {}

/// The spy's whole state under one lock, file-scope for the same reason.
private struct SeamSpyState {
    var live = 0
    var peak = 0
    var passes = 0
    var cancelledPasses = 0
    /// `.held` passes with a number above this wait; `release()` opens them
    /// all, `release(upTo:)` opens a prefix so a test can hold the follow-up
    /// while its predecessor completes (reviews-5/REVIEW-1.md finding 5).
    var releasedUpTo = 0
    /// The `today` each pass ran with, in pass order - what pins the
    /// latest-joiner-arguments semantic (reviews-5/REVIEW-1.md finding 4).
    var passDays: [CalendarDay] = []
}

/// The scheduler stand-in behind the gate. Two modes: `.yielding` suspends six
/// times inside the pass - the round-4 spy that models the real scheduler's
/// suspension points before its first write - and `.held` parks the pass until
/// `release()`, which is what makes the deterministic tests deterministic.
/// Every outcome is stamped with its pass number in `scheduledCount`, so a test
/// can assert WHICH pass answered a caller, not just that one did.
private final class SeamSpy: ReminderScheduling {
    enum Mode { case yielding, held }

    private let state = Mutex(SeamSpyState())
    private let mode: Mode
    private let failingPasses: Set<Int>
    private let coveredThrough: CalendarDay

    init(_ mode: Mode, coveredThrough: CalendarDay, failingPasses: Set<Int> = []) {
        self.mode = mode
        self.coveredThrough = coveredThrough
        self.failingPasses = failingPasses
    }

    var peak: Int { state.withLock { $0.peak } }
    var passes: Int { state.withLock { $0.passes } }
    var cancelledPasses: Int { state.withLock { $0.cancelledPasses } }
    var passDays: [CalendarDay] { state.withLock { $0.passDays } }

    func release() {
        state.withLock { $0.releasedUpTo = Int.max }
    }

    func release(upTo passNumber: Int) {
        state.withLock { $0.releasedUpTo = max($0.releasedUpTo, passNumber) }
    }

    func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome {
        let passNumber = state.withLock { current -> Int in
            current.passes += 1
            current.live += 1
            current.peak = max(current.peak, current.live)
            current.passDays.append(today)
            return current.passes
        }
        defer { state.withLock { $0.live -= 1 } }
        switch mode {
        case .yielding:
            for _ in 0..<6 { await Task.yield() }
        case .held:
            while state.withLock({ $0.releasedUpTo }) < passNumber {
                if Task.isCancelled {
                    state.withLock { $0.cancelledPasses += 1 }
                    throw CancellationError()
                }
                await Task.yield()
            }
        }
        if failingPasses.contains(passNumber) { throw SeamPassRefused() }
        return ScheduleOutcome(
            permission: .authorized, scheduledCount: passNumber,
            truncatedAfter: nil, coveredThrough: coveredThrough
        )
    }
}

/// N4-7 + N4-3 (round 5, item 1): the coalescing gate at the seam every
/// scheduling caller shares.
@Suite("CoalescingReminderScheduler: one pass at a time, honestly shared")
struct CoalescingReminderSchedulerTests {

    private let now = Date(timeIntervalSince1970: 1_786_000_000)
    private let zone = TimeZone(identifier: "America/Toronto") ?? .current

    private func fixtureDay() throws -> CalendarDay {
        try #require(CalendarDay(year: 2026, month: 8, day: 15))
    }

    /// Awaits a condition the concurrency machinery will reach, bounded so a
    /// broken gate fails the test rather than hanging the suite.
    private func settle(until condition: () async -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    // MARK: - The defect, and the gate that closes it

    /// ⛔ Characterisation of the DEFECT (N4-7): the bare seam does not
    /// serialise. Two concurrent callers interleave inside the pass - measured
    /// through the real entry points at the round-5 baseline in 62 of 180
    /// (background) and 39 of 180 (store) iterations. Sixty iterations of the
    /// direct two-caller shape make a zero-overlap run astronomically unlikely,
    /// so this asserts the defect's existence without asserting its rate.
    @Test("⛔ the bare seam lets two concurrent passes interleave")
    func bareSeamInterleaves() async throws {
        let day = try fixtureDay()
        var sawOverlap = false
        for _ in 0..<60 where !sawOverlap {
            let spy = SeamSpy(.yielding, coveredThrough: day)
            async let first = spy.reschedule(now: now, today: day, timeZone: zone)
            async let second = spy.reschedule(now: now, today: day, timeZone: zone)
            _ = try await (first, second)
            sawOverlap = spy.peak >= 2
        }
        #expect(sawOverlap)
    }

    /// ⛔ The fix, structurally: through the gate the peak is 1 on EVERY
    /// iteration, not most of them - a pass starts only after its predecessor
    /// has finished, so overlap is inexpressible rather than unlikely.
    @Test("⛔ the gate serialises every iteration, and never runs more than two passes")
    func gateSerialises() async throws {
        let day = try fixtureDay()
        for _ in 0..<60 {
            let spy = SeamSpy(.yielding, coveredThrough: day)
            let gate = CoalescingReminderScheduler(base: spy)
            async let first = gate.reschedule(now: now, today: day, timeZone: zone)
            async let second = gate.reschedule(now: now, today: day, timeZone: zone)
            _ = try await (first, second)
            #expect(spy.peak == 1)
            #expect(spy.passes <= 2)
        }
    }

    // MARK: - Coalescing and freshness

    /// ⛔ Callers arriving while a pass runs share ONE follow-up, and every one
    /// of them is answered by that follow-up - a pass that started after their
    /// calls, so its outcome describes state their triggers are part of. The
    /// coordinator's F10 gate made this promise for five trigger classes; the
    /// seam gate makes it for every caller.
    @Test("⛔ three callers during a pass share one follow-up, and get ITS outcome")
    func callersDuringAPassShareOneFreshFollowUp() async throws {
        let day = try fixtureDay()
        let spy = SeamSpy(.held, coveredThrough: day)
        let gate = CoalescingReminderScheduler(base: spy)
        let first = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { spy.passes == 1 })

        let second = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        let third = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        let fourth = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { await gate.probeQueuedWaiters == 3 })
        spy.release()

        #expect(try await first.value.scheduledCount == 1)
        #expect(try await second.value.scheduledCount == 2)
        #expect(try await third.value.scheduledCount == 2)
        #expect(try await fourth.value.scheduledCount == 2)
        #expect(spy.passes == 2)

        // A caller arriving AFTER the coalesced episode gets a fresh pass, not
        // the drained follow-up's stale outcome. This assertion exists because
        // a falsification survived without it: a gate that never clears its
        // queued slot passed every other test in this suite while answering
        // every later caller with pass 2's result forever.
        let fifth = try await gate.reschedule(now: now, today: day, timeZone: zone)
        #expect(fifth.scheduledCount == 3)
        #expect(spy.passes == 3)
    }

    /// ⛔ The gate must not survive its own chain (the round-4 falsification
    /// that produced "the gate never reopens"): sequential callers each get
    /// their own pass.
    @Test("⛔ sequential callers each run a fresh pass")
    func theGateReopensBetweenCalls() async throws {
        let day = try fixtureDay()
        let spy = SeamSpy(.yielding, coveredThrough: day)
        let gate = CoalescingReminderScheduler(base: spy)

        let first = try await gate.reschedule(now: now, today: day, timeZone: zone)
        let second = try await gate.reschedule(now: now, today: day, timeZone: zone)
        let third = try await gate.reschedule(now: now, today: day, timeZone: zone)

        #expect(first.scheduledCount == 1)
        #expect(second.scheduledCount == 2)
        #expect(third.scheduledCount == 3)
        #expect(spy.passes == 3)
    }

    /// ⛔ A failing pass fails ITS waiters and nobody else: the follow-up still
    /// runs, and its callers get its result, not the predecessor's error.
    @Test("⛔ a predecessor's failure reaches its own waiter and spares the follow-up's")
    func aFailedPassDoesNotPoisonTheFollowUp() async throws {
        let day = try fixtureDay()
        let spy = SeamSpy(.held, coveredThrough: day, failingPasses: [1])
        let gate = CoalescingReminderScheduler(base: spy)
        let first = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { spy.passes == 1 })
        let second = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { await gate.probeQueuedWaiters == 1 })
        spy.release()

        await #expect(throws: SeamPassRefused.self) { try await first.value }
        #expect(try await second.value.scheduledCount == 2)
        #expect(spy.passes == 2)
    }

    // MARK: - Cancellation is counted, not forwarded

    /// ⛔ A pass with ONE waiter is that waiter's to cancel: the base scheduler
    /// receives the cancellation (its checkpoints abort the pass), the caller
    /// gets `CancellationError`, and the gate reopens.
    @Test("⛔ cancelling the sole waiter cancels the underlying pass")
    func soleWaiterCancellationReachesThePass() async throws {
        let day = try fixtureDay()
        let spy = SeamSpy(.held, coveredThrough: day)
        let gate = CoalescingReminderScheduler(base: spy)
        let only = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { spy.passes == 1 })

        only.cancel()

        await #expect(throws: CancellationError.self) { try await only.value }
        #expect(spy.cancelledPasses == 1)

        spy.release()
        let next = try await gate.reschedule(now: now, today: day, timeZone: zone)
        #expect(next.scheduledCount == 2)
    }

    /// ⛔ The expiration hazard the ledger named, in miniature: a pass with two
    /// waiters survives one waiter's cancellation. The cancelled caller keeps
    /// waiting and receives the shared outcome - the pass covered its trigger,
    /// so the outcome is still the honest answer - and the base scheduler never
    /// sees a cancellation.
    @Test("⛔ a shared pass survives one waiter's cancellation")
    func aSharedPassSurvivesOneWaitersCancellation() async throws {
        let day = try fixtureDay()
        let spy = SeamSpy(.held, coveredThrough: day)
        let gate = CoalescingReminderScheduler(base: spy)
        let first = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { spy.passes == 1 })
        let second = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        let third = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { await gate.probeQueuedWaiters == 2 })

        second.cancel()
        #expect(await settle { await gate.probeQueuedCancelledWaiters == 1 })
        spy.release()

        #expect(try await first.value.scheduledCount == 1)
        #expect(try await second.value.scheduledCount == 2)
        #expect(try await third.value.scheduledCount == 2)
        #expect(spy.cancelledPasses == 0)
        #expect(spy.passes == 2)
    }

    /// ⛔ A follow-up whose every waiter has been cancelled is abandoned before
    /// the base scheduler does any work - the pass count does not move.
    @Test("⛔ a follow-up all of whose waiters cancelled never runs")
    func anAbandonedFollowUpNeverRuns() async throws {
        let day = try fixtureDay()
        let spy = SeamSpy(.held, coveredThrough: day)
        let gate = CoalescingReminderScheduler(base: spy)
        let first = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { spy.passes == 1 })
        let second = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { await gate.probeQueuedWaiters == 1 })

        second.cancel()
        // Abandonment VACATES the slot (the finding-1 fix); the probe that
        // watched the corpse's cancelled task watched a mechanism that no
        // longer exists.
        #expect(await settle { await gate.probeQueuedWaiters == 0 })
        spy.release()

        #expect(try await first.value.scheduledCount == 1)
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(spy.passes == 1)
    }

    /// ⛔ The starvation `reviews-5/REVIEW-1.md` finding 1 measured, as a
    /// permanent guard: after an abandoned follow-up is cancelled, its corpse
    /// must not occupy the queued slot - an uncancelled caller arriving before
    /// the in-flight pass finishes gets a FRESH follow-up and a real pass, not
    /// the corpse's `CancellationError`. Before the fix this test's late caller
    /// threw and `spy.passes` stayed 1, deterministically.
    @Test("⛔ a caller after an abandoned follow-up gets a fresh pass, not the corpse")
    func aCallerAfterAnAbandonedFollowUpGetsAFreshPass() async throws {
        let day = try fixtureDay()
        let spy = SeamSpy(.held, coveredThrough: day)
        let gate = CoalescingReminderScheduler(base: spy)
        let first = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { spy.passes == 1 })
        let second = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { await gate.probeQueuedWaiters == 1 })

        second.cancel()
        // The fix in one observable: abandoning the follow-up VACATES the slot.
        #expect(await settle { await gate.probeQueuedWaiters == 0 })

        let third = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { await gate.probeQueuedWaiters == 1 })
        spy.release()

        #expect(try await first.value.scheduledCount == 1)
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(try await third.value.scheduledCount == 2)
        #expect(spy.passes == 2)
        #expect(spy.peak == 1)
    }

    /// ⛔ The latest-joiner-arguments semantic, pinned (`reviews-5/REVIEW-1.md`
    /// finding 4): the follow-up runs with the MOST RECENT joiner's arguments.
    /// Deleting `queued.arguments = arguments` left every shipped test green,
    /// because every caller passed the same fixture day; these callers do not.
    @Test("⛔ the follow-up runs with the most recent joiner's arguments")
    func theFollowUpRunsWithTheLatestJoinersArguments() async throws {
        let day = try fixtureDay()
        let laterDay = day.adding(days: 1)
        let latestDay = day.adding(days: 2)
        let spy = SeamSpy(.held, coveredThrough: day)
        let gate = CoalescingReminderScheduler(base: spy)
        let first = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { spy.passes == 1 })
        let second = Task { try await gate.reschedule(now: now, today: laterDay, timeZone: zone) }
        #expect(await settle { await gate.probeQueuedWaiters == 1 })
        let third = Task { try await gate.reschedule(now: now, today: latestDay, timeZone: zone) }
        #expect(await settle { await gate.probeQueuedWaiters == 2 })
        spy.release()

        _ = try await (first.value, second.value, third.value)
        #expect(spy.passDays == [day, latestDay])
    }

    /// ⛔ Serialisation in the caller-during-the-follow-up window
    /// (`reviews-5/REVIEW-1.md` finding 5): a mutant that deletes the
    /// promotion's `inFlight = pass` overlaps 58 of 60 iterations in the
    /// reviewer's probe yet survived every shipped host test, because none sent
    /// a caller while the follow-up itself was running. This one does, staged
    /// deterministically: pass 1 completes, the follow-up is held mid-run, and
    /// only then does the third caller arrive - it must queue behind the
    /// follow-up, not start a concurrent pass.
    @Test("⛔ a caller during the follow-up pass queues behind it")
    func aCallerDuringTheFollowUpQueuesBehindIt() async throws {
        let day = try fixtureDay()
        let spy = SeamSpy(.held, coveredThrough: day)
        let gate = CoalescingReminderScheduler(base: spy)
        let first = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { spy.passes == 1 })
        let second = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { await gate.probeQueuedWaiters == 1 })

        spy.release(upTo: 1)
        #expect(await settle { spy.passes == 2 })

        let third = Task { try await gate.reschedule(now: now, today: day, timeZone: zone) }
        #expect(await settle { await gate.probeQueuedWaiters == 1 })
        #expect(spy.passes == 2)
        spy.release()

        #expect(try await first.value.scheduledCount == 1)
        #expect(try await second.value.scheduledCount == 2)
        #expect(try await third.value.scheduledCount == 3)
        #expect(spy.passes == 3)
        #expect(spy.peak == 1)
    }
}
