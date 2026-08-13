// R4-2. `NotificationCoordinator` is inside `#if os(iOS)` and compiles to
// nothing under host `swift test`, so reverting `rescheduleSoon` to its pre-fix
// shape left all 580 host tests green and `swiftlint --strict` clean. That path
// carries every unattended trigger - foreground, timezone change, significant
// time change, notification delivered, notification acted on - and the
// background refresh, and none of it was reachable from any test.
//
// UIKit-hosted like `DynamicTypeTests`, so this file runs on the simulator and
// compiles to nothing on a mac host. It is the carry-over `docs/next-wave.md`
// records as "simulator-hosted NotificationCoordinator tests".
#if os(iOS)
import Foundation
import Testing
import OttoDomain
import OttoRepositories
import Synchronization
import UserNotifications
@testable import OttoServices

/// Outside the `@MainActor` suite: the coordinator's `now`/`today` closures are
/// `@Sendable` and cannot capture main-actor state.
private let fixtureToday = CalendarDay(year: 2026, month: 8, day: 11)
private let fixtureInstant = Date(timeIntervalSince1970: 1_786_000_000)

/// What a failing pass throws. File-scope because SwiftLint's `nesting` rule
/// allows one level and the spy is already nested in the suite.
private struct PassRefused: Error {}

/// The spy's whole state under one lock. File-scope for the same reason
/// `PassRefused` is: `SchedulerSpy` is already one level deep inside the suite,
/// so a type nested inside IT is two, which `nesting` refuses. Splitting it out
/// is the fix; re-thresholding the rule is not available and would be wrong.
private struct SpyState {
    var passes: [CalendarDay] = []
    var outcome: ScheduleOutcome?
    /// How many passes are inside `reschedule` right now, and the most there
    /// have ever been at once. F10's measurement.
    var live = 0
    var peak = 0
}

@MainActor
@Suite("NotificationCoordinator: the triggers nothing could reach (R4-2)")
struct NotificationCoordinatorTests {

    // MARK: - Fixtures

    /// Records every pass and answers with whatever the test wants. A
    /// `Mutex` rather than an actor because `reschedule` is called from the
    /// coordinator's own `Task` and the assertions read it from the test.
    ///
    /// `live`/`peakConcurrency` are F10's measurement: how many passes were
    /// inside `reschedule` at once. `duringPass` is how a test makes a trigger
    /// arrive while a pass is genuinely in flight, which is the only state in
    /// which coalescing has anything to decide.
    private final class SchedulerSpy: ReminderScheduling {
        private let state: Mutex<SpyState>
        /// Run on the main actor from inside the first pass, once.
        private let duringPass: Mutex<(@MainActor @Sendable () -> Void)?> = Mutex(nil)
        private let firedDuringPass = Mutex(false)

        init(outcome: ScheduleOutcome?) {
            state = Mutex(SpyState(outcome: outcome))
        }

        func fireDuringFirstPass(_ body: @escaping @MainActor @Sendable () -> Void) {
            duringPass.withLock { $0 = body }
        }

        var passes: [CalendarDay] { state.withLock { $0.passes } }
        var peakConcurrency: Int { state.withLock { $0.peak } }

        func reschedule(now: Date, today: CalendarDay, timeZone: TimeZone) async throws -> ScheduleOutcome {
            let outcome = state.withLock { current -> ScheduleOutcome? in
                current.passes.append(today)
                current.live += 1
                current.peak = max(current.peak, current.live)
                return current.outcome
            }
            defer { state.withLock { $0.live -= 1 } }

            let pending = duringPass.withLock { $0 }
            let alreadyFired = firedDuringPass.withLock { was -> Bool in
                let previous = was
                was = true
                return previous
            }
            if let pending, !alreadyFired {
                await MainActor.run { pending() }
            } else {
                // A suspension point, so a sibling pass CAN interleave here if
                // anything let one start. Without it every pass would run to
                // completion before the next began and the concurrency
                // measurement would be vacuously 1.
                await Task.yield()
            }

            guard let outcome else { throw PassRefused() }
            return outcome
        }
    }

    /// A `BGAppRefreshTask` stand-in. The real type has no public initializer,
    /// which is why the handler takes the protocol.
    private final class FakeRefreshTask: BackgroundRefreshTask, @unchecked Sendable {
        private let recorded = Mutex<[Bool]>([])
        var expirationHandler: (() -> Void)?

        var completions: [Bool] { recorded.withLock { $0 } }

        func setTaskCompleted(success: Bool) {
            recorded.withLock { $0.append(success) }
        }
    }

    private func makeCoordinator(scheduler: SchedulerSpy) throws -> NotificationCoordinator {
        let day = try #require(fixtureToday)
        return NotificationCoordinator(
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
            // The injected centre keeps `UNUserNotificationCenter.current()` -
            // which needs an app bundle a test bundle does not have - untouched.
            client: LiveNotificationClient(center: StubCenter()),
            now: { fixtureInstant },
            today: { day },
            timeZone: { TimeZone(identifier: "America/Toronto") ?? .current }
        )
    }

    private func healthyOutcome() throws -> ScheduleOutcome {
        ScheduleOutcome(
            permission: .authorized,
            scheduledCount: 4,
            truncatedAfter: nil,
            coveredThrough: try #require(fixtureToday).adding(days: 90)
        )
    }

    // MARK: - The foreground trigger

    @Test("⛔ the foreground trigger runs a pass and publishes its outcome")
    func foregroundPassPublishes() async throws {
        let scheduler = SchedulerSpy(outcome: try healthyOutcome())
        let coordinator = try makeCoordinator(scheduler: scheduler)
        var published: [ScheduleOutcome?] = []
        coordinator.onOutcome = { published.append($0) }

        await coordinator.appDidBecomeActive().value

        #expect(scheduler.passes == [try #require(fixtureToday)])
        #expect(published.count == 1)
        #expect(published.first??.scheduledCount == 4)
    }

    @Test("⛔ a FAILED foreground pass publishes nil rather than leaving the last success standing")
    func foregroundFailurePublishesNil() async throws {
        let scheduler = SchedulerSpy(outcome: nil)
        let coordinator = try makeCoordinator(scheduler: scheduler)
        var published: [ScheduleOutcome?] = []
        coordinator.onOutcome = { published.append($0) }

        await coordinator.appDidBecomeActive().value

        // The whole point of round 1's F3 fix, and the half of it that had no
        // test: a pass that threw must REPORT the failure, because dropping it
        // leaves the store publishing the last successful outcome and Today
        // stating coverage this pass just failed to renew.
        #expect(published.count == 1)
        let reported = try #require(published.first)
        #expect(reported == nil)
    }

    // MARK: - Coalescing (F10)

    /// ⛔ F10. Every §6.2 trigger used to spawn its own unstructured `Task`.
    ///
    /// Measured at `00cb0f1`, before the gate, with this exact test: five
    /// triggers produced **5 passes**, and the peak concurrency varied run to
    /// run - 3 on the builder's single run, and **2, 5, 3, 3** across
    /// `reviews-4/REVIEW-3.md`'s four. The PASS COUNT is a property of the
    /// code and reproduces every time; the peak is a property of the executor
    /// and does not, so only the pass count belongs in a record. What every
    /// run agrees on is that more than one full reschedule was in flight -
    /// each loading every subscription, reconciling every ledger and writing
    /// every watermark, against the same rows.
    ///
    /// This is not a contrived burst: a foreground open fires `.foreground`
    /// while a delivered notification fires `.notificationDelivered`, and a
    /// timezone change and a significant-time change arrive together.
    ///
    /// Deterministic without a sleep. The triggers are fired with no `await`
    /// between them, so every `Task` the coordinator creates is still queued
    /// when the last one is submitted; what differs is only whether five tasks
    /// or one exist to run.
    @Test("⛔ five triggers fired together run ONE pass, not five")
    func triggersCoalesce() async throws {
        let scheduler = SchedulerSpy(outcome: try healthyOutcome())
        let coordinator = try makeCoordinator(scheduler: scheduler)
        var published: [ScheduleOutcome?] = []
        coordinator.onOutcome = { published.append($0) }

        // Only the five trigger classes production actually routes through
        // this gate. `.stateChange` goes through NotificationStatusStore and
        // `.backgroundRefresh` through handleBackgroundRefresh, and neither
        // reaches `rescheduleSoon` in the app - firing them here depicted a
        // gate wider than the one that exists (`reviews-4/REVIEW-3.md`
        // finding 2).
        let triggers: [RescheduleTrigger] = [
            .foreground, .notificationDelivered, .timeZoneChange,
            .significantTimeChange, .notificationAction
        ]
        let tasks = triggers.map { coordinator.rescheduleSoon($0) }
        for task in tasks { await task.value }

        #expect(scheduler.passes.count == 1)
        #expect(scheduler.peakConcurrency == 1)
        // Every caller's task is the same chain, so awaiting any of them awaits
        // the work that caller's trigger caused.
        #expect(published.count == 1)
    }

    /// ⛔ Coalescing must not become dropping. A trigger that arrives after the
    /// in-flight pass has already read the store describes a change that pass
    /// cannot have seen, so exactly one follow-up has to run - and exactly one,
    /// however many arrive.
    @Test("⛔ a trigger that arrives DURING a pass gets one follow-up, and only one")
    func aTriggerDuringAPassIsNotSwallowed() async throws {
        let scheduler = SchedulerSpy(outcome: try healthyOutcome())
        let coordinator = try makeCoordinator(scheduler: scheduler)
        scheduler.fireDuringFirstPass { [weak coordinator] in
            // Three more, all while the first pass is genuinely in flight, and
            // all trigger classes this gate really carries.
            _ = coordinator?.rescheduleSoon(.notificationDelivered)
            _ = coordinator?.rescheduleSoon(.notificationAction)
            _ = coordinator?.rescheduleSoon(.timeZoneChange)
        }

        await coordinator.rescheduleSoon(.foreground).value

        #expect(scheduler.passes.count == 2)
        #expect(scheduler.peakConcurrency == 1)
    }

    /// The gate must not survive its own chain: a trigger arriving after
    /// everything has settled starts a fresh pass rather than returning a
    /// finished task and doing nothing.
    @Test("⛔ a later trigger still runs, once the chain has drained")
    func theGateReopensAfterTheChainDrains() async throws {
        let scheduler = SchedulerSpy(outcome: try healthyOutcome())
        let coordinator = try makeCoordinator(scheduler: scheduler)

        await coordinator.rescheduleSoon(.foreground).value
        await coordinator.rescheduleSoon(.notificationDelivered).value
        await coordinator.rescheduleSoon(.timeZoneChange).value

        #expect(scheduler.passes.count == 3)
        #expect(scheduler.peakConcurrency == 1)
    }

    /// **Characterisation, not a regression guard.** The gate covers
    /// `rescheduleSoon`, which is what F10 names; `handleBackgroundRefresh`
    /// builds its own `Task` because it also owns the completion latch and the
    /// expiration race, and it does NOT go through the gate. A background
    /// wake-up that lands while the app is in the foreground therefore runs a
    /// second pass rather than being coalesced into the first.
    ///
    /// **They do overlap, about one run in six.** An earlier version of this
    /// comment said `peakConcurrency == 2` "does not reproduce", on the
    /// strength of one run that scheduled serially. `reviews-4/REVIEW-3.md`
    /// finding 1 ran this exact scenario 60 times per execution, four times
    /// over, and measured the two passes genuinely interleaving in **45 of 240
    /// iterations**:
    ///
    ///     peak distribution [(1, 49), (2, 11)] / [(1, 49), (2, 11)]
    ///                       [(1, 47), (2, 13)] / [(1, 50), (2, 10)]
    ///
    /// Re-measured here independently rather than taken on the reviewer's
    /// word, with a spy that suspends six times to model what the real
    /// scheduler does before its first write - **74 of 180 iterations**:
    ///
    ///     [(1, 34), (2, 26)] / [(1, 39), (2, 21)] / [(1, 33), (2, 27)]
    ///
    /// So the rate is not a fixed property either; it rises with the number of
    /// suspension points the pass has, and the real pass has more than the
    /// shipped spy. `NotificationScheduler` is an actor, but `reschedule`
    /// suspends repeatedly before it writes anything, so the actor interleaves
    /// passes rather than serialising them. That overlap IS F10, still live on
    /// this path. Measuring a non-deterministic quantity once and recording
    /// the sample as the property is the same mistake the twelve-run flake
    /// protocol exists to prevent, made from the other side.
    ///
    /// This test asserts only the part that holds on every run, because an
    /// assertion that is true 18 % of the time is a flaky test rather than a
    /// guard. The overlap is recorded as **N4-3**, at P2.
    ///
    /// Not fixed here: routing the background pass through the same chain
    /// changes what `expirationHandler` cancels, and there is a THIRD ungated
    /// entry point besides - `NotificationStatusStore.reschedule()` - so the
    /// fix belongs at the `ReminderScheduling` seam the three callers share,
    /// not in this class. `PROD-READINESS-4.md` N4-3 and N4-7.
    @Test("the background pass is NOT coalesced with the foreground one")
    func theBackgroundPassIsOutsideTheGate() async throws {
        let scheduler = SchedulerSpy(outcome: try healthyOutcome())
        let coordinator = try makeCoordinator(scheduler: scheduler)
        let task = FakeRefreshTask()

        let foreground = coordinator.rescheduleSoon(.foreground)
        let background = coordinator.handleBackgroundRefresh(task)
        await foreground.value
        await background.value

        #expect(scheduler.passes.count == 2)
    }

    // MARK: - The background refresh

    @Test("⛔ a background pass publishes its outcome, which it never did")
    func backgroundPassPublishes() async throws {
        let scheduler = SchedulerSpy(outcome: try healthyOutcome())
        let coordinator = try makeCoordinator(scheduler: scheduler)
        let task = FakeRefreshTask()
        var published: [ScheduleOutcome?] = []
        coordinator.onOutcome = { published.append($0) }

        await coordinator.handleBackgroundRefresh(task).value

        #expect(scheduler.passes.count == 1)
        #expect(published.count == 1)
        #expect(published.first??.scheduledCount == 4)
        #expect(task.completions == [true])
    }

    @Test("⛔ a FAILED background pass publishes nil and completes the task unsuccessfully")
    func backgroundFailurePublishesNil() async throws {
        let scheduler = SchedulerSpy(outcome: nil)
        let coordinator = try makeCoordinator(scheduler: scheduler)
        let task = FakeRefreshTask()
        var published: [ScheduleOutcome?] = []
        coordinator.onOutcome = { published.append($0) }

        await coordinator.handleBackgroundRefresh(task).value

        #expect(published.count == 1)
        let reported = try #require(published.first)
        #expect(reported == nil)
        #expect(task.completions == [false])
    }

    @Test("expiration completes the task exactly once, even after the pass returns")
    func expirationCompletesOnce() async throws {
        let scheduler = SchedulerSpy(outcome: try healthyOutcome())
        let coordinator = try makeCoordinator(scheduler: scheduler)
        let task = FakeRefreshTask()

        let work = coordinator.handleBackgroundRefresh(task)
        // Expiration fires while the pass is in flight - the device-observed
        // Gate 2 sequence that produced two `setTaskCompleted` calls before the
        // latch existed.
        task.expirationHandler?()
        await work.value

        #expect(task.completions == [false])
    }
}
#endif
